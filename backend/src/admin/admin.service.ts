import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { AccountService } from '../auth/account.service.js';
import { dayRangeUtc } from '../bookings/availability.js';
import { Db } from '../db/db.service.js';

const TODAY = `(now() AT TIME ZONE 'America/Bogota')::date`;

@Injectable()
export class AdminService {
  constructor(
    private readonly db: Db,
    private readonly account: AccountService,
  ) {}

  // ---------- Usuarios ----------

  async listUsers(q: { search?: string; role?: string; limit?: number; offset?: number }) {
    const { rows } = await this.db.query(
      `SELECT id, name, email, phone, role, suspended_at AS "suspendedAt", deleted_at AS "deletedAt",
              created_at AS "createdAt"
       FROM users
       WHERE ($1::text IS NULL OR name ILIKE '%' || $1 || '%' OR email ILIKE '%' || $1 || '%')
         AND ($2::user_role IS NULL OR role = $2::user_role)
       ORDER BY created_at DESC LIMIT $3 OFFSET $4`,
      [q.search ?? null, q.role ?? null, q.limit ?? 30, q.offset ?? 0],
    );
    return rows;
  }

  /** Los administradores no se suspenden ni se borran desde la API (ni a sí mismos). */
  private async target(adminId: string, userId: string) {
    const u = (
      await this.db.query<{ id: string; role: string; deleted_at: Date | null }>(
        'SELECT id, role, deleted_at FROM users WHERE id = $1',
        [userId],
      )
    ).rows[0];
    if (!u) throw new NotFoundException({ code: 'USER_NOT_FOUND', message: 'Usuario no encontrado' });
    if (u.role === 'admin' || u.id === adminId) {
      throw new ForbiddenException({ code: 'ADMIN_PROTECTED', message: 'No se puede modificar a un administrador' });
    }
    if (u.deleted_at) throw new ConflictException({ code: 'USER_DELETED', message: 'La cuenta ya fue eliminada' });
    return u;
  }

  async suspendUser(adminId: string, userId: string) {
    const u = await this.target(adminId, userId);
    await this.db.tx(async (c) => {
      await c.query('UPDATE users SET suspended_at = COALESCE(suspended_at, now()) WHERE id = $1', [userId]);
      await c.query('UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [userId]);
      if (u.role === 'owner') {
        // Un dueño suspendido no debe seguir apareciendo en el buscador.
        await c.query(
          `UPDATE courts SET status = 'suspended', suspended_by_admin = true WHERE owner_id = $1 AND status <> 'suspended'`,
          [userId],
        );
      }
    });
    return { id: userId, suspended: true };
  }

  async restoreUser(adminId: string, userId: string) {
    await this.target(adminId, userId);
    await this.db.query('UPDATE users SET suspended_at = NULL WHERE id = $1', [userId]);
    return { id: userId, suspended: false };
  }

  async deleteUser(adminId: string, userId: string) {
    await this.target(adminId, userId);
    await this.account.anonymizeUser(userId);
    return { id: userId, deleted: true };
  }

  // ---------- Canchas ----------

  async listCourts(q: { status?: string; search?: string; limit?: number; offset?: number }) {
    const { rows } = await this.db.query(
      `SELECT c.id, c.name, c.city, c.status, c.suspended_by_admin AS "suspendedByAdmin",
              c.price_per_hour AS "pricePerHour", c.created_at AS "createdAt",
              u.id AS "ownerId", u.name AS "ownerName", u.phone AS "ownerPhone", u.email AS "ownerEmail",
              (SELECT MAX(ends_on)::text FROM subscription_periods WHERE court_id = c.id) AS "activeUntil",
              EXISTS (SELECT 1 FROM payments p WHERE p.court_id = c.id AND p.kind = 'subscription' AND p.status = 'pending')
                AS "pendingSubscription"
       FROM courts c JOIN users u ON u.id = c.owner_id
       WHERE ($1::court_status IS NULL OR c.status = $1::court_status)
         AND ($2::text IS NULL OR c.name ILIKE '%' || $2 || '%' OR c.city ILIKE '%' || $2 || '%')
       ORDER BY c.created_at DESC LIMIT $3 OFFSET $4`,
      [q.status ?? null, q.search ?? null, q.limit ?? 30, q.offset ?? 0],
    );
    return rows;
  }

  async suspendCourt(courtId: string) {
    const r = await this.db.query(
      `UPDATE courts SET status = 'suspended', suspended_by_admin = true WHERE id = $1 RETURNING id`,
      [courtId],
    );
    if (r.rowCount === 0) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });
    return { id: courtId, status: 'suspended' };
  }

  /** Reactiva una cancha suspendida solo si tiene una mensualidad vigente. */
  async reactivateCourt(courtId: string) {
    const r = await this.db.query<{ ok: boolean }>(
      `SELECT EXISTS (SELECT 1 FROM subscription_periods WHERE court_id = $1 AND starts_on <= ${TODAY} AND ${TODAY} < ends_on) AS ok`,
      [courtId],
    );
    const exists = await this.db.query('SELECT 1 FROM courts WHERE id = $1', [courtId]);
    if (exists.rowCount === 0) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });
    if (!r.rows[0]!.ok) {
      throw new ConflictException({ code: 'NO_ACTIVE_SUBSCRIPTION', message: 'La cancha no tiene una mensualidad vigente' });
    }
    await this.db.query(`UPDATE courts SET status = 'active', suspended_by_admin = false WHERE id = $1`, [courtId]);
    return { id: courtId, status: 'active' };
  }

  // ---------- Reseñas reportadas ----------

  async listReportedReviews() {
    const { rows } = await this.db.query(
      `SELECT r.id, r.stars, r.body, r.hidden_at AS "hiddenAt", r.created_at AS "createdAt",
              c.id AS "courtId", c.name AS "courtName", u.id AS "authorId", u.name AS "authorName",
              COUNT(rr.id)::int AS reports, array_remove(array_agg(DISTINCT rr.reason), NULL) AS reasons
       FROM review_reports rr
       JOIN reviews r ON r.id = rr.review_id
       JOIN courts c ON c.id = r.court_id
       JOIN users u ON u.id = r.author_id
       WHERE rr.resolved_at IS NULL
       GROUP BY r.id, c.id, u.id ORDER BY COUNT(rr.id) DESC, r.created_at DESC`,
    );
    return rows;
  }

  /** Oculta la reseña (deja de verse y de contar en la calificación) y cierra sus reportes. */
  async hideReview(reviewId: string) {
    const r = await this.db.query('UPDATE reviews SET hidden_at = COALESCE(hidden_at, now()) WHERE id = $1 RETURNING id', [reviewId]);
    if (r.rowCount === 0) throw new NotFoundException({ code: 'REVIEW_NOT_FOUND', message: 'Reseña no encontrada' });
    await this.db.query('UPDATE review_reports SET resolved_at = now() WHERE review_id = $1 AND resolved_at IS NULL', [reviewId]);
    return { id: reviewId, hidden: true };
  }

  /** Conserva la reseña y descarta los reportes. */
  async dismissReports(reviewId: string) {
    const r = await this.db.query('UPDATE review_reports SET resolved_at = now() WHERE review_id = $1 AND resolved_at IS NULL', [reviewId]);
    return { id: reviewId, dismissed: r.rowCount ?? 0 };
  }

  // ---------- Transacciones y métricas ----------

  /** Pagos aprobados (reservas y mensualidades) con total del filtro. Fechas YYYY-MM-DD, hora de Colombia. */
  async transactions(q: { kind?: string; from?: string; to?: string; limit?: number; offset?: number }) {
    const from = q.from ? dayRangeUtc(q.from) : null;
    const to = q.to ? dayRangeUtc(q.to) : null;
    if ((q.from && !from) || (q.to && !to)) {
      throw new BadRequestException({ code: 'BAD_DATE', message: 'Fecha inválida (usa YYYY-MM-DD)' });
    }
    const params: unknown[] = [q.kind ?? null, from?.from ?? null, to?.to ?? null];
    const where = `p.status = 'approved' AND ($1::payment_kind IS NULL OR p.kind = $1::payment_kind)
      AND ($2::timestamptz IS NULL OR p.reviewed_at >= $2) AND ($3::timestamptz IS NULL OR p.reviewed_at < $3)`;
    const [items, total] = await Promise.all([
      this.db.query(
        `SELECT p.id, p.kind, p.amount, p.reviewed_at AS "date", c.name AS "courtName", u.name AS "payerName"
         FROM payments p JOIN courts c ON c.id = p.court_id JOIN users u ON u.id = p.payer_id
         WHERE ${where} ORDER BY p.reviewed_at DESC LIMIT $4 OFFSET $5`,
        [...params, q.limit ?? 30, q.offset ?? 0],
      ),
      this.db.query<{ count: number; amount: number }>(
        `SELECT COUNT(*)::int AS count, COALESCE(SUM(p.amount), 0)::bigint::float AS amount FROM payments p WHERE ${where}`,
        params,
      ),
    ]);
    return { count: total.rows[0]!.count, totalAmount: total.rows[0]!.amount, items: items.rows };
  }

  async metrics() {
    const [users, courts, bookings, money, pending] = await Promise.all([
      this.db.query<{ role: string; n: number }>(
        `SELECT role::text, COUNT(*)::int AS n FROM users WHERE deleted_at IS NULL GROUP BY role`,
      ),
      this.db.query<{ status: string; n: number }>(`SELECT status::text, COUNT(*)::int AS n FROM courts GROUP BY status`),
      this.db.query<{ status: string; n: number }>(`SELECT status::text, COUNT(*)::int AS n FROM bookings WHERE NOT owner_block GROUP BY status`),
      this.db.query<{ subs_total: number; subs_month: number; bookings_30d: number; bookings_30d_value: number; new_users_30d: number }>(
        `SELECT
           COALESCE((SELECT SUM(amount) FROM payments WHERE kind = 'subscription' AND status = 'approved'), 0)::float AS subs_total,
           COALESCE((SELECT SUM(amount) FROM payments WHERE kind = 'subscription' AND status = 'approved'
             AND date_trunc('month', reviewed_at AT TIME ZONE 'America/Bogota') = date_trunc('month', now() AT TIME ZONE 'America/Bogota')), 0)::float AS subs_month,
           (SELECT COUNT(*) FROM bookings WHERE status = 'confirmed' AND NOT owner_block AND created_at > now() - interval '30 days')::int AS bookings_30d,
           COALESCE((SELECT SUM(total) FROM bookings WHERE status = 'confirmed' AND NOT owner_block AND created_at > now() - interval '30 days'), 0)::float AS bookings_30d_value,
           (SELECT COUNT(*) FROM users WHERE created_at > now() - interval '30 days' AND deleted_at IS NULL)::int AS new_users_30d`,
      ),
      this.db.query<{ subs: number; reports: number }>(
        `SELECT (SELECT COUNT(*) FROM payments WHERE kind = 'subscription' AND status = 'pending')::int AS subs,
                (SELECT COUNT(DISTINCT review_id) FROM review_reports WHERE resolved_at IS NULL)::int AS reports`,
      ),
    ]);
    const group = (rows: { n: number }[], key: 'role' | 'status') =>
      Object.fromEntries((rows as unknown as Record<string, string | number>[]).map((r) => [r[key] as string, r.n as number]));
    const m = money.rows[0]!;
    return {
      users: group(users.rows, 'role'),
      courts: group(courts.rows, 'status'),
      bookings: group(bookings.rows, 'status'),
      revenue: { subscriptionsTotal: m.subs_total, subscriptionsThisMonth: m.subs_month },
      last30Days: { confirmedBookings: m.bookings_30d, bookingsValue: m.bookings_30d_value, newUsers: m.new_users_30d },
      pending: { subscriptionPayments: pending.rows[0]!.subs, reportedReviews: pending.rows[0]!.reports },
    };
  }
}

import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Db } from '../db/db.service.js';
import { type Notice, NotificationsService } from '../notifications/notifications.service.js';
import { StorageService } from '../storage/storage.service.js';
import type { Role } from '../auth/auth.service.js';

export interface PaymentFilters {
  status?: 'pending' | 'approved' | 'rejected';
  kind?: 'booking' | 'subscription';
  courtId?: string;
  limit?: number;
  offset?: number;
}

const PAYMENT_COLS = `
  p.id, p.kind, p.status, p.amount, p.reject_reason AS "rejectReason", p.created_at AS "createdAt",
  p.reviewed_at AS "reviewedAt", c.id AS "courtId", c.name AS "courtName",
  u.name AS "payerName", u.phone AS "payerPhone", u.email AS "payerEmail",
  b.id AS "bookingId", b.start_at AS "startAt", b.hours, b.total AS "bookingTotal"`;

const PAYMENT_FROM = `
  FROM payments p
  JOIN courts c ON c.id = p.court_id
  JOIN users u ON u.id = p.payer_id
  LEFT JOIN bookings b ON b.id = p.booking_id`;

@Injectable()
export class PaymentsService {
  private readonly subscriptionPrice: number;

  constructor(
    private readonly db: Db,
    private readonly storage: StorageService,
    private readonly notifications: NotificationsService,
    config: ConfigService,
  ) {
    this.subscriptionPrice = Number(config.get('SUBSCRIPTION_PRICE') ?? 100_000);
  }

  // ---------- Jugador: comprobante del anticipo ----------

  async submitBookingProof(playerId: string, bookingId: string, file: Buffer | undefined) {
    const pre = await this.db.query<{ status: string }>(
      'SELECT status FROM bookings WHERE id = $1 AND player_id = $2',
      [bookingId, playerId],
    );
    if (!pre.rows[0]) throw new NotFoundException({ code: 'BOOKING_NOT_FOUND', message: 'Reserva no encontrada' });
    if (!['pending_payment', 'rejected'].includes(pre.rows[0].status)) {
      throw new ConflictException({ code: 'NOT_PAYABLE', message: 'Esta reserva no espera un comprobante' });
    }

    const proof = await this.storage.saveImage(file, 'proofs');
    try {
      const notices: Notice[] = [];
      const result = await this.db.tx(async (c) => {
        const b = (
          await c.query<{ status: string; deposit: number; court_id: string; owner_id: string; court_name: string }>(
            `SELECT b.status, b.deposit, b.court_id, c.owner_id, c.name AS court_name
             FROM bookings b JOIN courts c ON c.id = b.court_id
             WHERE b.id = $1 AND b.player_id = $2 FOR UPDATE OF b`,
            [bookingId, playerId],
          )
        ).rows[0];
        if (!b || !['pending_payment', 'rejected'].includes(b.status)) {
          throw new ConflictException({ code: 'NOT_PAYABLE', message: 'Esta reserva no espera un comprobante' });
        }
        const p = await c.query<{ id: string }>(
          `INSERT INTO payments (kind, booking_id, court_id, payer_id, amount, proof_path)
           VALUES ('booking', $1, $2, $3, $4, $5) RETURNING id`,
          [bookingId, b.court_id, playerId, b.deposit, proof],
        );
        await c.query(`UPDATE bookings SET status = 'pending_review' WHERE id = $1`, [bookingId]);
        const n: Notice = {
          userId: b.owner_id,
          title: 'Nuevo comprobante de pago',
          body: `Tienes un comprobante por revisar en ${b.court_name}.`,
          data: { type: 'payment_pending', paymentId: p.rows[0]!.id },
        };
        await this.notifications.record(c, n);
        notices.push(n);
        return { paymentId: p.rows[0]!.id, bookingStatus: 'pending_review' as const };
      });
      await this.notifications.deliver(notices);
      return result;
    } catch (e) {
      await this.storage.remove('proofs', proof);
      throw e;
    }
  }

  // ---------- Dueño: revisar pagos de reservas ----------

  async listForOwner(ownerId: string, f: PaymentFilters) {
    const params: unknown[] = [ownerId];
    const where = [`c.owner_id = $1`, `p.kind = 'booking'`];
    if (f.status) where.push(`p.status = $${params.push(f.status)}`);
    if (f.courtId) where.push(`c.id = $${params.push(f.courtId)}`);
    params.push(f.limit ?? 30, f.offset ?? 0);
    const { rows } = await this.db.query(
      `SELECT ${PAYMENT_COLS} ${PAYMENT_FROM} WHERE ${where.join(' AND ')}
       ORDER BY p.created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params,
    );
    return rows;
  }

  async reviewBookingPayment(ownerId: string, paymentId: string, approve: boolean, reason?: string) {
    const notices: Notice[] = [];
    await this.db.tx(async (c) => {
      const p = (
        await c.query<{ status: string; booking_id: string; payer_id: string; b_status: string; court_name: string }>(
          `SELECT p.status, p.booking_id, p.payer_id, b.status AS b_status, c.name AS court_name
           FROM payments p JOIN courts c ON c.id = p.court_id JOIN bookings b ON b.id = p.booking_id
           WHERE p.id = $1 AND p.kind = 'booking' AND c.owner_id = $2 FOR UPDATE OF p, b`,
          [paymentId, ownerId],
        )
      ).rows[0];
      if (!p) throw new NotFoundException({ code: 'PAYMENT_NOT_FOUND', message: 'Pago no encontrado' });
      if (p.status !== 'pending') {
        throw new ConflictException({ code: 'ALREADY_REVIEWED', message: 'Este pago ya fue revisado' });
      }
      if (p.b_status !== 'pending_review') {
        throw new ConflictException({ code: 'BOOKING_CHANGED', message: 'La reserva ya no está esperando revisión' });
      }
      await c.query(
        `UPDATE payments SET status = $2, reviewed_by = $3, reviewed_at = now(), reject_reason = $4 WHERE id = $1`,
        [paymentId, approve ? 'approved' : 'rejected', ownerId, approve ? null : (reason ?? null)],
      );
      await c.query(`UPDATE bookings SET status = $2 WHERE id = $1`, [p.booking_id, approve ? 'confirmed' : 'rejected']);
      const n: Notice = approve
        ? {
            userId: p.payer_id,
            title: 'Pago aprobado',
            body: `Tu reserva en ${p.court_name} quedó confirmada.`,
            data: { type: 'booking_confirmed', bookingId: p.booking_id },
            email: true,
          }
        : {
            userId: p.payer_id,
            title: 'Pago rechazado',
            body: `Tu comprobante en ${p.court_name} fue rechazado${reason ? `: ${reason}` : ''}. Sube uno nuevo para conservar tu hora.`,
            data: { type: 'payment_rejected', bookingId: p.booking_id },
            email: true,
          };
      await this.notifications.record(c, n);
      notices.push(n);
    });
    await this.notifications.deliver(notices);
    return { id: paymentId, status: approve ? 'approved' : 'rejected' };
  }

  // ---------- Dueño: mensualidad ----------

  async submitSubscriptionProof(ownerId: string, courtId: string, file: Buffer | undefined) {
    const court = await this.db.query<{ name: string }>('SELECT name FROM courts WHERE id = $1 AND owner_id = $2', [
      courtId,
      ownerId,
    ]);
    if (!court.rows[0]) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });
    const pending = await this.db.query(
      `SELECT 1 FROM payments WHERE court_id = $1 AND kind = 'subscription' AND status = 'pending'`,
      [courtId],
    );
    if (pending.rowCount) {
      throw new ConflictException({ code: 'ALREADY_PENDING', message: 'Ya tienes un pago de mensualidad en revisión' });
    }

    const proof = await this.storage.saveImage(file, 'proofs');
    try {
      const notices: Notice[] = [];
      const result = await this.db.tx(async (c) => {
        const p = await c.query<{ id: string }>(
          `INSERT INTO payments (kind, court_id, payer_id, amount, proof_path)
           VALUES ('subscription', $1, $2, $3, $4) RETURNING id`,
          [courtId, ownerId, this.subscriptionPrice, proof],
        );
        for (const adminId of await this.notifications.adminIds()) {
          const n: Notice = {
            userId: adminId,
            title: 'Pago de mensualidad por revisar',
            body: `${court.rows[0]!.name} envió su comprobante de mensualidad.`,
            data: { type: 'subscription_pending', paymentId: p.rows[0]!.id },
          };
          await this.notifications.record(c, n);
          notices.push(n);
        }
        return { paymentId: p.rows[0]!.id, amount: this.subscriptionPrice };
      });
      await this.notifications.deliver(notices);
      return result;
    } catch (e) {
      await this.storage.remove('proofs', proof);
      if ((e as { code?: string }).code === '23505') {
        throw new ConflictException({ code: 'ALREADY_PENDING', message: 'Ya tienes un pago de mensualidad en revisión' });
      }
      throw e;
    }
  }

  // ---------- Admin: mensualidades ----------

  async listForAdmin(f: PaymentFilters) {
    const params: unknown[] = [];
    const where = ['TRUE'];
    if (f.status) where.push(`p.status = $${params.push(f.status)}`);
    if (f.kind) where.push(`p.kind = $${params.push(f.kind)}`);
    if (f.courtId) where.push(`c.id = $${params.push(f.courtId)}`);
    params.push(f.limit ?? 30, f.offset ?? 0);
    const { rows } = await this.db.query(
      `SELECT ${PAYMENT_COLS} ${PAYMENT_FROM} WHERE ${where.join(' AND ')}
       ORDER BY p.created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params,
    );
    return rows;
  }

  /**
   * Aprueba o rechaza el pago de una mensualidad. Al aprobar se crea un periodo
   * de 30 días (continuo si todavía hay uno vigente) y la cancha pasa a activa,
   * salvo que el admin la haya suspendido a mano.
   */
  async reviewSubscription(adminId: string, paymentId: string, approve: boolean, reason?: string) {
    const notices: Notice[] = [];
    const result = await this.db.tx(async (c) => {
      const p = (
        await c.query<{ status: string; court_id: string; court_name: string; owner_id: string; suspended_by_admin: boolean }>(
          `SELECT p.status, p.court_id, c.name AS court_name, c.owner_id, c.suspended_by_admin
           FROM payments p JOIN courts c ON c.id = p.court_id
           WHERE p.id = $1 AND p.kind = 'subscription' FOR UPDATE OF p, c`,
          [paymentId],
        )
      ).rows[0];
      if (!p) throw new NotFoundException({ code: 'PAYMENT_NOT_FOUND', message: 'Pago no encontrado' });
      if (p.status !== 'pending') {
        throw new ConflictException({ code: 'ALREADY_REVIEWED', message: 'Este pago ya fue revisado' });
      }
      await c.query(
        `UPDATE payments SET status = $2, reviewed_by = $3, reviewed_at = now(), reject_reason = $4 WHERE id = $1`,
        [paymentId, approve ? 'approved' : 'rejected', adminId, approve ? null : (reason ?? null)],
      );

      let periodEnds: string | null = null;
      if (approve) {
        const per = await c.query<{ starts_on: string; ends_on: string }>(
          `WITH s AS (
             SELECT GREATEST((now() AT TIME ZONE 'America/Bogota')::date,
                             COALESCE((SELECT MAX(ends_on) FROM subscription_periods WHERE court_id = $1), '-infinity'::date)) AS d)
           INSERT INTO subscription_periods (court_id, payment_id, starts_on, ends_on)
           SELECT $1, $2, s.d, s.d + 30 FROM s RETURNING starts_on::text, ends_on::text`,
          [p.court_id, paymentId],
        );
        periodEnds = per.rows[0]!.ends_on;
        if (!p.suspended_by_admin) {
          await c.query(`UPDATE courts SET status = 'active' WHERE id = $1`, [p.court_id]);
        }
      }
      const n: Notice = approve
        ? {
            userId: p.owner_id,
            title: 'Mensualidad aprobada',
            body: p.suspended_by_admin
              ? `Recibimos el pago de ${p.court_name}, pero la cancha está suspendida por el administrador.`
              : `${p.court_name} está activa y visible hasta el ${periodEnds}.`,
            data: { type: 'subscription_approved', courtId: p.court_id },
            email: true,
          }
        : {
            userId: p.owner_id,
            title: 'Mensualidad rechazada',
            body: `El comprobante de ${p.court_name} fue rechazado${reason ? `: ${reason}` : ''}. Sube uno nuevo.`,
            data: { type: 'subscription_rejected', courtId: p.court_id },
            email: true,
          };
      await this.notifications.record(c, n);
      notices.push(n);
      return { id: paymentId, status: approve ? 'approved' : 'rejected', activeUntil: periodEnds };
    });
    await this.notifications.deliver(notices);
    return result;
  }

  /**
   * El admin registra una mensualidad cobrada fuera de la app (transferencia, efectivo...):
   * crea el pago como aprobado y reutiliza reviewSubscription para abrir el periodo de 30 días.
   */
  async registerManualSubscription(adminId: string, courtId: string, amount?: number, note?: string) {
    const court = (
      await this.db.query<{ owner_id: string }>('SELECT owner_id FROM courts WHERE id = $1', [courtId])
    ).rows[0];
    if (!court) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });
    const proof = note?.trim() ? `manual:${note.trim().slice(0, 200)}` : 'manual';
    const ins = await this.db.query<{ id: string }>(
      `INSERT INTO payments (kind, court_id, payer_id, amount, proof_path)
       VALUES ('subscription', $1, $2, $3, $4) RETURNING id`,
      [courtId, court.owner_id, amount ?? this.subscriptionPrice, proof],
    );
    const paymentId = ins.rows[0]!.id;
    try {
      return await this.reviewSubscription(adminId, paymentId, true);
    } catch (e) {
      await this.db.query(`DELETE FROM payments WHERE id = $1 AND status = 'pending'`, [paymentId]);
      throw e;
    }
  }

  // ---------- Comprobantes (descarga privada) ----------

  /** Ruta del comprobante si el usuario es quien lo subió, el dueño de la cancha o un administrador. */
  async proofPath(userId: string, role: Role, paymentId: string): Promise<string> {
    const { rows } = await this.db.query<{ proof_path: string; payer_id: string; owner_id: string }>(
      `SELECT p.proof_path, p.payer_id, c.owner_id FROM payments p JOIN courts c ON c.id = p.court_id WHERE p.id = $1`,
      [paymentId],
    );
    const p = rows[0];
    const allowed = p && (role === 'admin' || p.payer_id === userId || p.owner_id === userId);
    if (!p || !allowed) throw new NotFoundException({ code: 'PAYMENT_NOT_FOUND', message: 'Comprobante no encontrado' });
    const path = this.storage.pathOf('proofs', p.proof_path);
    if (!path) throw new NotFoundException({ code: 'PAYMENT_NOT_FOUND', message: 'Comprobante no encontrado' });
    return path;
  }
}

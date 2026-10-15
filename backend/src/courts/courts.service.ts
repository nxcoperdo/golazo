import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { AccountService } from '../auth/account.service.js';
import { Db } from '../db/db.service.js';
import { StorageService } from '../storage/storage.service.js';
import { dayRangeUtc, hourSlots } from '../bookings/availability.js';
import type { CreateCourtDto, ListCourtsQuery, PaymentMethodDto, UpdateCourtDto } from './courts.dto.js';

/** Columnas públicas de una cancha, con foto principal, calificación y (opcional) distancia. */
const COURT_SELECT = (distanceSql: string) => `
  c.id, c.name, c.description, c.city, c.address, c.covered, c.court_type AS "courtType",
  c.price_per_hour AS "pricePerHour", c.open_hour AS "openHour", c.close_hour AS "closeHour",
  c.requires_deposit AS "requiresDeposit", c.deposit_percent AS "depositPercent",
  c.status, ST_Y(c.location::geometry) AS lat, ST_X(c.location::geometry) AS lng,
  (SELECT '/v1/files/courts/' || p.path FROM court_photos p WHERE p.court_id = c.id ORDER BY p.position LIMIT 1) AS "photoUrl",
  (SELECT COALESCE(ROUND(AVG(r.stars)::numeric, 1), 0)::float FROM reviews r
     WHERE r.court_id = c.id AND r.hidden_at IS NULL) AS rating,
  (SELECT COUNT(*)::int FROM reviews r WHERE r.court_id = c.id AND r.hidden_at IS NULL) AS "reviewCount",
  ${distanceSql} AS "distanceM"`;

const PHOTO_URL = '/v1/files/courts/';
const MAX_PHOTOS = 8;

@Injectable()
export class CourtsService {
  constructor(
    private readonly db: Db,
    private readonly storage: StorageService,
    private readonly account: AccountService,
  ) {}

  /** Listado público: solo canchas activas. */
  async list(q: ListCourtsQuery) {
    const params: unknown[] = [];
    const p = (v: unknown): string => {
      params.push(v);
      return `$${params.length}`;
    };
    const where = [`c.status = 'active'`];
    if (q.city) where.push(`c.city = ${p(q.city)}`);
    if (q.maxPrice != null) where.push(`c.price_per_hour <= ${p(q.maxPrice)}`);
    if (q.covered != null) where.push(`c.covered = ${p(q.covered)}`);
    if (q.courtType != null) where.push(`c.court_type = ${p(q.courtType)}`);

    let distance = 'NULL::float8';
    let order = 'c.name';
    if (q.lat != null && q.lng != null) {
      const point = `ST_SetSRID(ST_MakePoint(${p(q.lng)}::float8, ${p(q.lat)}::float8), 4326)::geography`;
      distance = `ST_Distance(c.location, ${point})`;
      order = `"distanceM", c.name`;
      if (q.radiusKm != null) where.push(`ST_DWithin(c.location, ${point}, ${p(q.radiusKm * 1000)}::float8)`);
    }
    const limit = p(q.limit ?? 20);
    const offset = p(q.offset ?? 0);

    const { rows } = await this.db.query(
      `SELECT ${COURT_SELECT(distance)} FROM courts c
       WHERE ${where.join(' AND ')} ORDER BY ${order} LIMIT ${limit} OFFSET ${offset}`,
      params,
    );
    return rows;
  }

  async detail(id: string) {
    const { rows } = await this.db.query(
      `SELECT ${COURT_SELECT('NULL::float8')} FROM courts c WHERE c.id = $1 AND c.status = 'active'`,
      [id],
    );
    if (!rows[0]) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });
    const photos = await this.db.query<{ path: string }>(
      'SELECT path FROM court_photos WHERE court_id = $1 ORDER BY position',
      [id],
    );
    return { ...rows[0], photos: photos.rows.map((r) => `${PHOTO_URL}${r.path}`) };
  }

  async availability(id: string, date: string) {
    const range = dayRangeUtc(date);
    if (!range) throw new BadRequestException({ code: 'BAD_DATE', message: 'Fecha inválida (usa YYYY-MM-DD)' });

    const court = await this.db.query<{ open_hour: number; close_hour: number }>(
      `SELECT open_hour, close_hour FROM courts WHERE id = $1 AND status = 'active'`,
      [id],
    );
    const c = court.rows[0];
    if (!c) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });

    // Mismas reservas que bloquean el índice EXCLUDE (incluye "rechazada").
    const b = await this.db.query<{ start_at: Date; end_at: Date }>(
      `SELECT start_at, end_at FROM bookings
       WHERE court_id = $1 AND status IN ('pending_payment','pending_review','confirmed','rejected')
         AND start_at < $3 AND end_at > $2`,
      [id, range.from, range.to],
    );
    return {
      date,
      hours: hourSlots({
        openHour: c.open_hour,
        closeHour: c.close_hour,
        dayStart: range.from,
        bookings: b.rows.map((r) => ({ startAt: r.start_at, endAt: r.end_at })),
        now: new Date(),
      }),
    };
  }

  // ---- Dueño ----

  /** Crea la cancha en estado `pending`: no es visible hasta que se apruebe la mensualidad. */
  async create(ownerId: string, dto: CreateCourtDto) {
    await this.account.assertVerified(ownerId);
    if (dto.closeHour <= dto.openHour) {
      throw new BadRequestException({ code: 'BAD_HOURS', message: 'El cierre debe ser después de la apertura' });
    }
    const { rows } = await this.db.query<{ id: string }>(
      `INSERT INTO courts (owner_id, name, description, city, address, location, covered, court_type,
                           price_per_hour, open_hour, close_hour, requires_deposit, deposit_percent)
       VALUES ($1,$2,$3,$4,$5, ST_SetSRID(ST_MakePoint($6::float8,$7::float8),4326)::geography,
               $8,$9,$10,$11,$12,$13,$14) RETURNING id`,
      [ownerId, dto.name.trim(), dto.description ?? null, dto.city.trim(), dto.address.trim(), dto.lng, dto.lat,
       dto.covered, dto.courtType ?? 5, dto.pricePerHour, dto.openHour, dto.closeHour, dto.requiresDeposit, dto.depositPercent ?? 30],
    );
    return this.ownerDetail(ownerId, rows[0]!.id);
  }

  async listOwn(ownerId: string) {
    const { rows } = await this.db.query(
      `SELECT ${COURT_SELECT('NULL::float8')} FROM courts c WHERE c.owner_id = $1 ORDER BY c.created_at DESC`,
      [ownerId],
    );
    return rows;
  }

  async ownerDetail(ownerId: string, id: string) {
    const { rows } = await this.db.query(
      `SELECT ${COURT_SELECT('NULL::float8')} FROM courts c WHERE c.id = $1 AND c.owner_id = $2`,
      [id, ownerId],
    );
    if (!rows[0]) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });
    const [photos, methods, sub] = await Promise.all([
      this.db.query<{ id: string; path: string }>(
        'SELECT id, path FROM court_photos WHERE court_id = $1 ORDER BY position',
        [id],
      ),
      this.db.query<PaymentMethodDto>(
        'SELECT label, account, holder FROM court_payment_methods WHERE court_id = $1 ORDER BY label',
        [id],
      ),
      this.db.query<{ activeUntil: string | null; pending: boolean }>(
        `SELECT (SELECT MAX(ends_on)::text FROM subscription_periods WHERE court_id = $1) AS "activeUntil",
                EXISTS (SELECT 1 FROM payments WHERE court_id = $1 AND kind = 'subscription' AND status = 'pending') AS pending`,
        [id],
      ),
    ]);
    return {
      ...rows[0],
      photos: photos.rows.map((r) => ({ id: r.id, url: `${PHOTO_URL}${r.path}` })),
      paymentMethods: methods.rows,
      subscription: { activeUntil: sub.rows[0]!.activeUntil, pendingReview: sub.rows[0]!.pending },
    };
  }

  async update(ownerId: string, id: string, dto: UpdateCourtDto) {
    const current = await this.db.query<{ open_hour: number; close_hour: number }>(
      'SELECT open_hour, close_hour FROM courts WHERE id = $1 AND owner_id = $2',
      [id, ownerId],
    );
    const cur = current.rows[0];
    if (!cur) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });
    if ((dto.closeHour ?? cur.close_hour) <= (dto.openHour ?? cur.open_hour)) {
      throw new BadRequestException({ code: 'BAD_HOURS', message: 'El cierre debe ser después de la apertura' });
    }
    if ((dto.lat == null) !== (dto.lng == null)) {
      throw new BadRequestException({ code: 'BAD_LOCATION', message: 'Envía lat y lng juntos' });
    }

    const sets: string[] = [];
    const params: unknown[] = [];
    const set = (col: string, v: unknown) => {
      params.push(v);
      sets.push(`${col} = $${params.length}`);
    };
    if (dto.name !== undefined) set('name', dto.name.trim());
    if (dto.description !== undefined) set('description', dto.description);
    if (dto.city !== undefined) set('city', dto.city.trim());
    if (dto.address !== undefined) set('address', dto.address.trim());
    if (dto.covered !== undefined) set('covered', dto.covered);
    if (dto.courtType !== undefined) set('court_type', dto.courtType);
    if (dto.pricePerHour !== undefined) set('price_per_hour', dto.pricePerHour);
    if (dto.openHour !== undefined) set('open_hour', dto.openHour);
    if (dto.closeHour !== undefined) set('close_hour', dto.closeHour);
    if (dto.requiresDeposit !== undefined) set('requires_deposit', dto.requiresDeposit);
    if (dto.depositPercent !== undefined) set('deposit_percent', dto.depositPercent);
    if (dto.lat != null && dto.lng != null) {
      params.push(dto.lng, dto.lat);
      sets.push(`location = ST_SetSRID(ST_MakePoint($${params.length - 1}::float8, $${params.length}::float8), 4326)::geography`);
    }
    if (sets.length > 0) {
      params.push(id, ownerId);
      await this.db.query(
        `UPDATE courts SET ${sets.join(', ')} WHERE id = $${params.length - 1} AND owner_id = $${params.length}`,
        params,
      );
    }
    return this.ownerDetail(ownerId, id);
  }

  /** Reemplaza la lista completa de cuentas de cobro. */
  async setPaymentMethods(ownerId: string, id: string, methods: PaymentMethodDto[]) {
    await this.db.tx(async (c) => {
      const own = await c.query('SELECT 1 FROM courts WHERE id = $1 AND owner_id = $2 FOR UPDATE', [id, ownerId]);
      if (own.rowCount === 0) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });
      await c.query('DELETE FROM court_payment_methods WHERE court_id = $1', [id]);
      for (const m of methods) {
        await c.query(
          'INSERT INTO court_payment_methods (court_id, label, account, holder) VALUES ($1,$2,$3,$4)',
          [id, m.label.trim(), m.account.trim(), m.holder.trim()],
        );
      }
    });
    return this.ownerDetail(ownerId, id);
  }

  async addPhoto(ownerId: string, courtId: string, file: Buffer | undefined) {
    const own = await this.db.query<{ n: number }>(
      `SELECT (SELECT COUNT(*)::int FROM court_photos WHERE court_id = c.id) AS n
       FROM courts c WHERE c.id = $1 AND c.owner_id = $2`,
      [courtId, ownerId],
    );
    if (!own.rows[0]) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });
    if (own.rows[0].n >= MAX_PHOTOS) {
      throw new ConflictException({ code: 'TOO_MANY_PHOTOS', message: `Máximo ${MAX_PHOTOS} fotos por cancha` });
    }
    const name = await this.storage.saveImage(file, 'courts');
    try {
      await this.db.query('INSERT INTO court_photos (court_id, path, position) VALUES ($1, $2, $3)', [
        courtId,
        name,
        own.rows[0].n,
      ]);
    } catch (e) {
      await this.storage.remove('courts', name);
      throw e;
    }
    return this.ownerDetail(ownerId, courtId);
  }

  async removePhoto(ownerId: string, courtId: string, photoId: string) {
    const del = await this.db.query<{ path: string }>(
      `DELETE FROM court_photos p USING courts c
       WHERE p.id = $1 AND p.court_id = $2 AND c.id = p.court_id AND c.owner_id = $3 RETURNING p.path`,
      [photoId, courtId, ownerId],
    );
    if (!del.rows[0]) throw new NotFoundException({ code: 'PHOTO_NOT_FOUND', message: 'Foto no encontrada' });
    await this.storage.remove('courts', del.rows[0].path);
    return this.ownerDetail(ownerId, courtId);
  }

  /** Ciudades que tienen canchas activas (para el selector de la app). */
  async cities() {
    const { rows } = await this.db.query<{ city: string; courts: number }>(
      `SELECT city, COUNT(*)::int AS courts FROM courts WHERE status = 'active' GROUP BY city ORDER BY city`,
    );
    return rows;
  }

  /** El dueño oculta su cancha del buscador (no cancela reservas ya hechas). */
  async pause(ownerId: string, id: string) {
    const r = await this.db.query(
      `UPDATE courts SET status = 'suspended', suspended_by_admin = false
       WHERE id = $1 AND owner_id = $2 AND status = 'active'`,
      [id, ownerId],
    );
    if (r.rowCount === 0) {
      await this.ownerDetail(ownerId, id); // 404 si no es suya
      throw new ConflictException({ code: 'NOT_ACTIVE', message: 'La cancha no está activa' });
    }
    return this.ownerDetail(ownerId, id);
  }

  /** Vuelve a mostrarla, solo si tiene mensualidad vigente y el admin no la suspendió. */
  async resume(ownerId: string, id: string) {
    const c = (
      await this.db.query<{ status: string; suspended_by_admin: boolean; has_period: boolean }>(
        `SELECT status, suspended_by_admin,
                EXISTS (SELECT 1 FROM subscription_periods sp WHERE sp.court_id = courts.id
                        AND sp.starts_on <= (now() AT TIME ZONE 'America/Bogota')::date
                        AND (now() AT TIME ZONE 'America/Bogota')::date < sp.ends_on) AS has_period
         FROM courts WHERE id = $1 AND owner_id = $2`,
        [id, ownerId],
      )
    ).rows[0];
    if (!c) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });
    if (c.suspended_by_admin) {
      throw new ForbiddenException({ code: 'SUSPENDED_BY_ADMIN', message: 'La suspendió el administrador' });
    }
    if (!c.has_period) {
      throw new ConflictException({ code: 'NO_ACTIVE_SUBSCRIPTION', message: 'Paga tu mensualidad para volver a mostrarla' });
    }
    await this.db.query(`UPDATE courts SET status = 'active' WHERE id = $1 AND owner_id = $2`, [id, ownerId]);
    return this.ownerDetail(ownerId, id);
  }
}

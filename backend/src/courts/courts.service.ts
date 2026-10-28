import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { AccountService } from '../auth/account.service.js';
import { Db } from '../db/db.service.js';
import { StorageService } from '../storage/storage.service.js';
import { dayRangeUtc, hourSlots } from '../bookings/availability.js';
import type pg from 'pg';
import type { CourtVariantDto, CreateCourtDto, ListCourtsQuery, PaymentMethodDto, UpdateCourtDto } from './courts.dto.js';

/** Columnas públicas de una cancha, con foto principal, calificación y (opcional) distancia. */
const COURT_SELECT = (distanceSql: string) => `
  c.id, c.name, c.description, c.city, c.address, c.covered, c.court_types AS "courtTypes", c.court_types[1] AS "courtType",
  c.price_per_hour AS "pricePerHour", c.open_hour AS "openHour", c.close_hour AS "closeHour",
  c.requires_deposit AS "requiresDeposit", c.deposit_percent AS "depositPercent",
  c.status, ST_Y(c.location::geometry) AS lat, ST_X(c.location::geometry) AS lng,
  (SELECT COALESCE(json_agg(json_build_object('id', v.id, 'courtType', v.court_type, 'pricePerHour', v.price_per_hour)
                            ORDER BY v.court_type), '[]'::json)
     FROM court_variants v WHERE v.court_id = c.id AND v.active) AS variants,
  (SELECT '/v1/files/courts/' || p.path FROM court_photos p WHERE p.court_id = c.id ORDER BY p.position LIMIT 1) AS "photoUrl",
  (SELECT COALESCE(ROUND(AVG(r.stars)::numeric, 1), 0)::float FROM reviews r
     WHERE r.court_id = c.id AND r.hidden_at IS NULL) AS rating,
  (SELECT COUNT(*)::int FROM reviews r WHERE r.court_id = c.id AND r.hidden_at IS NULL) AS "reviewCount",
  ${distanceSql} AS "distanceM"`;

/**
 * Tipos con precio de la cancha. Acepta `variants` (forma nueva) o `courtTypes`/`courtType` +
 * `pricePerHour` (forma antigua, un mismo precio para todos). `priceOf` completa el precio que falte.
 */
function resolveVariants(
  dto: { variants?: CourtVariantDto[]; courtTypes?: number[]; courtType?: number; pricePerHour?: number },
  priceOf: (type: number) => number | undefined = () => undefined,
): CourtVariantDto[] | undefined {
  let list: CourtVariantDto[] | undefined = dto.variants;
  if (!list) {
    const raw = dto.courtTypes ?? (dto.courtType != null ? [dto.courtType] : undefined);
    if (raw) {
      list = [...new Set(raw)].map((courtType) => {
        const pricePerHour = dto.pricePerHour ?? priceOf(courtType);
        if (pricePerHour == null || !Number.isFinite(pricePerHour)) {
          throw new BadRequestException({ code: 'PRICE_REQUIRED', message: 'Indica el precio de cada tipo de cancha' });
        }
        return { courtType, pricePerHour };
      });
    }
  }
  if (!list) return undefined;
  if (new Set(list.map((v) => v.courtType)).size !== list.length) {
    throw new BadRequestException({ code: 'DUPLICATE_TYPE', message: 'Cada tipo de cancha solo puede aparecer una vez' });
  }
  return [...list].sort((a, b) => a.courtType - b.courtType);
}

/** Deja activos solo los tipos de [variants] (con su precio) y sincroniza el resumen de la cancha. */
async function saveVariants(c: pg.PoolClient, courtId: string, variants: CourtVariantDto[]): Promise<void> {
  for (const v of variants) {
    await c.query(
      `INSERT INTO court_variants (court_id, court_type, price_per_hour) VALUES ($1,$2,$3)
       ON CONFLICT (court_id, court_type) DO UPDATE SET price_per_hour = EXCLUDED.price_per_hour, active = true`,
      [courtId, v.courtType, v.pricePerHour],
    );
  }
  // Los tipos que ya no se ofrecen se desactivan (conservan sus reservas pasadas).
  const types = variants.map((v) => v.courtType);
  await c.query('UPDATE court_variants SET active = false WHERE court_id = $1 AND NOT (court_type = ANY($2::smallint[]))', [courtId, types]);
  await c.query('UPDATE courts SET court_types = $2::smallint[], price_per_hour = $3 WHERE id = $1', [
    courtId,
    types,
    Math.min(...variants.map((v) => v.pricePerHour)),
  ]);
}

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
    if (q.courtType != null) where.push(`${p(q.courtType)}::smallint = ANY(c.court_types)`);

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

  async availability(id: string, date: string, courtType?: number) {
    const range = dayRangeUtc(date);
    if (!range) throw new BadRequestException({ code: 'BAD_DATE', message: 'Fecha inválida (usa YYYY-MM-DD)' });

    const court = await this.db.query<{ open_hour: number; close_hour: number }>(
      `SELECT open_hour, close_hour FROM courts WHERE id = $1 AND status = 'active'`,
      [id],
    );
    const c = court.rows[0];
    if (!c) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });

    // Sin tipo: el más barato (igual que al reservar desde una app antigua).
    const variant = (
      await this.db.query<{ id: string; court_type: number }>(
        `SELECT id, court_type FROM court_variants
         WHERE court_id = $1 AND active AND ($2::smallint IS NULL OR court_type = $2)
         ORDER BY price_per_hour, court_type LIMIT 1`,
        [id, courtType ?? null],
      )
    ).rows[0];
    if (!variant) throw new NotFoundException({ code: 'VARIANT_NOT_FOUND', message: 'Esa cancha no ofrece ese tipo' });

    // Mismas reservas que bloquean el índice EXCLUDE (incluye "rechazada").
    const b = await this.db.query<{ start_at: Date; end_at: Date }>(
      `SELECT start_at, end_at FROM bookings
       WHERE variant_id = $1 AND status IN ('pending_payment','pending_review','confirmed','rejected')
         AND start_at < $3 AND end_at > $2`,
      [variant.id, range.from, range.to],
    );
    return {
      date,
      courtType: variant.court_type,
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
    // Forma antigua sin tipos: Fútbol 5 con el precio indicado.
    const variants = resolveVariants(
      dto.variants == null && dto.courtTypes == null && dto.courtType == null && dto.pricePerHour != null
        ? { ...dto, courtTypes: [5] }
        : dto,
    );
    if (!variants) {
      throw new BadRequestException({ code: 'TYPES_REQUIRED', message: 'Elige al menos un tipo de cancha con su precio' });
    }
    const id = await this.db.tx(async (c) => {
      const { rows } = await c.query<{ id: string }>(
        `INSERT INTO courts (owner_id, name, description, city, address, location, covered, court_types,
                             price_per_hour, open_hour, close_hour, requires_deposit, deposit_percent)
         VALUES ($1,$2,$3,$4,$5, ST_SetSRID(ST_MakePoint($6::float8,$7::float8),4326)::geography,
                 $8,$9,$10,$11,$12,$13,$14) RETURNING id`,
        [ownerId, dto.name.trim(), dto.description ?? null, dto.city.trim(), dto.address.trim(), dto.lng, dto.lat,
         dto.covered, [5], 1000, dto.openHour, dto.closeHour, dto.requiresDeposit, dto.depositPercent ?? 30],
      );
      // Los tipos y el precio "desde" de la cancha se completan al guardar las modalidades.
      await saveVariants(c, rows[0]!.id, variants);
      return rows[0]!.id;
    });
    return this.ownerDetail(ownerId, id);
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
    if (dto.openHour !== undefined) set('open_hour', dto.openHour);
    if (dto.closeHour !== undefined) set('close_hour', dto.closeHour);
    if (dto.requiresDeposit !== undefined) set('requires_deposit', dto.requiresDeposit);
    if (dto.depositPercent !== undefined) set('deposit_percent', dto.depositPercent);
    if (dto.lat != null && dto.lng != null) {
      params.push(dto.lng, dto.lat);
      sets.push(`location = ST_SetSRID(ST_MakePoint($${params.length - 1}::float8, $${params.length}::float8), 4326)::geography`);
    }
    // Forma antigua: sin `variants`, un cambio de precio o de tipos se aplica a los tipos actuales.
    const legacy = dto.variants == null && (dto.pricePerHour != null || dto.courtTypes != null || dto.courtType != null);
    const active = legacy
      ? (await this.db.query<{ court_type: number; price_per_hour: number }>(
          'SELECT court_type, price_per_hour FROM court_variants WHERE court_id = $1 AND active', [id])).rows
      : [];
    const cheapest = active.length > 0 ? Math.min(...active.map((v) => v.price_per_hour)) : undefined;
    const variants = resolveVariants(
      dto.pricePerHour != null && dto.courtTypes == null && dto.courtType == null
        ? { ...dto, courtTypes: active.map((v) => v.court_type) }
        : dto,
      (t) => active.find((v) => v.court_type === t)?.price_per_hour ?? cheapest,
    );

    await this.db.tx(async (c) => {
      if (sets.length > 0) {
        params.push(id, ownerId);
        await c.query(
          `UPDATE courts SET ${sets.join(', ')} WHERE id = $${params.length - 1} AND owner_id = $${params.length}`,
          params,
        );
      }
      if (variants) await saveVariants(c, id, variants);
    });
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

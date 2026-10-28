import { ConflictException, Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { addDays } from '../common/dates.js';
import { dayRangeUtc } from '../bookings/availability.js';
import { colombiaHour, validateSlot } from '../bookings/booking-policy.js';
import { todayCo } from '../common/time.js';
import { Db, EXCLUSION_VIOLATION, pgCode } from '../db/db.service.js';

export interface OwnerBookingsQuery {
  courtId?: string;
  from?: string;
  to?: string;
  status?: string;
  limit?: number;
  offset?: number;
}

@Injectable()
export class OwnerBookingsService {
  constructor(private readonly db: Db) {}

  /**
   * Reservas de las canchas del dueño en un rango (YYYY-MM-DD, hora de Colombia, ambas incluidas).
   * Por defecto los próximos 7 días. Incluye los bloqueos manuales (`isBlock`); oculta las canceladas
   * salvo que se pida ese estado.
   */
  async list(ownerId: string, q: OwnerBookingsQuery) {
    const fromStr = q.from ?? todayCo();
    const toStr = q.to ?? addDays(fromStr, 6);
    const from = dayRangeUtc(fromStr);
    const to = dayRangeUtc(toStr);
    if (!from || !to || to.to <= from.from) {
      throw new UnprocessableEntityException({ code: 'BAD_DATE', message: 'Rango de fechas inválido' });
    }
    const { rows } = await this.db.query(
      `SELECT b.id, c.id AS "courtId", c.name AS "courtName", b.start_at AS "startAt", b.end_at AS "endAt",
              b.hours, b.total, b.deposit, b.status, b.owner_block AS "isBlock", b.note,
              (SELECT v.court_type FROM court_variants v WHERE v.id = b.variant_id) AS "courtType",
              CASE WHEN b.owner_block THEN NULL ELSE u.name END AS "playerName",
              CASE WHEN b.owner_block THEN NULL ELSE u.phone END AS "playerPhone"
       FROM bookings b
       JOIN courts c ON c.id = b.court_id
       JOIN users u ON u.id = b.player_id
       WHERE c.owner_id = $1 AND ($2::uuid IS NULL OR c.id = $2::uuid)
         AND b.start_at >= $3 AND b.start_at < $4
         -- Un bloqueo de todos los tipos son varias filas iguales: se muestra una sola.
         AND NOT EXISTS (SELECT 1 FROM bookings t WHERE b.owner_block AND t.owner_block AND t.court_id = b.court_id
                         AND t.start_at = b.start_at AND t.hours = b.hours AND t.created_at = b.created_at
                         AND t.status = b.status AND t.id < b.id)
         AND (($5::booking_status IS NULL AND b.status <> 'cancelled') OR b.status = $5::booking_status)
       ORDER BY b.start_at LIMIT $6 OFFSET $7`,
      [ownerId, q.courtId ?? null, from.from, to.to, q.status ?? null, q.limit ?? 100, q.offset ?? 0],
    );
    return rows;
  }

  /** Bloquea horas de su cancha (ocupa el mismo cupo que una reserva, sin cobrar ni notificar). */
  async block(ownerId: string, courtId: string, input: { startAt: string; hours: number; note?: string; courtType?: number }) {
    const court = (
      await this.db.query<{ open_hour: number; close_hour: number }>(
        'SELECT open_hour, close_hour FROM courts WHERE id = $1 AND owner_id = $2',
        [courtId, ownerId],
      )
    ).rows[0];
    if (!court) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });

    // Sin tipo, el bloqueo ocupa todos los tipos de la cancha (p. ej. el campo se cierra por lluvia).
    const variants = (
      await this.db.query<{ id: string; price_per_hour: number }>(
        `SELECT id, price_per_hour FROM court_variants
         WHERE court_id = $1 AND active AND ($2::smallint IS NULL OR court_type = $2) ORDER BY court_type`,
        [courtId, input.courtType ?? null],
      )
    ).rows;
    if (variants.length === 0) {
      throw new UnprocessableEntityException({ code: 'BAD_COURT_TYPE', message: 'Esa cancha no ofrece ese tipo de juego' });
    }

    const start = new Date(input.startAt);
    const invalid = validateSlot({
      start,
      hours: input.hours,
      now: new Date(),
      openHour: court.open_hour,
      closeHour: court.close_hour,
      startHourLocal: colombiaHour(start),
    });
    if (invalid) throw new UnprocessableEntityException({ code: 'BAD_SLOT', message: invalid });

    try {
      const ids = await this.db.tx(async (c) => {
        const out: string[] = [];
        for (const v of variants) {
          const { rows } = await c.query<{ id: string }>(
            `INSERT INTO bookings (court_id, variant_id, player_id, start_at, hours, end_at, total, deposit, last_minute, status, owner_block, note)
             VALUES ($1, $2, $3, $4, $5, $6, $7, 0, false, 'confirmed', true, $8) RETURNING id`,
            [courtId, v.id, ownerId, start, input.hours, new Date(start.getTime() + input.hours * 3600_000),
             v.price_per_hour * input.hours, input.note?.trim() || null],
          );
          out.push(rows[0]!.id);
        }
        return out;
      });
      return { id: ids[0]!, courtId, startAt: start, hours: input.hours, isBlock: true, note: input.note?.trim() || null };
    } catch (e) {
      if (pgCode(e) === EXCLUSION_VIOLATION) {
        throw new ConflictException({ code: 'SLOT_TAKEN', message: 'Ya hay una reserva en esa hora' });
      }
      throw e;
    }
  }

  async unblock(ownerId: string, blockId: string): Promise<void> {
    const r = await this.db.query(
      // Un bloqueo sin tipo son varias filas iguales (una por tipo): se liberan todas juntas.
      `UPDATE bookings b SET status = 'cancelled', cancelled_at = now()
       FROM courts c, bookings t
       WHERE t.id = $1 AND t.owner_block AND t.status = 'confirmed' AND c.id = t.court_id AND c.owner_id = $2
         AND b.court_id = t.court_id AND b.owner_block AND b.status = 'confirmed'
         AND b.start_at = t.start_at AND b.hours = t.hours AND b.created_at = t.created_at`,
      [blockId, ownerId],
    );
    if (r.rowCount === 0) throw new NotFoundException({ code: 'BLOCK_NOT_FOUND', message: 'Bloqueo no encontrado' });
  }
}

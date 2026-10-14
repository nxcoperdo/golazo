import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { dayRangeUtc } from '../bookings/availability.js';
import { Db } from '../db/db.service.js';

const DAY_MS = 24 * 3600_000;

/** Ocupación = horas reservadas confirmadas / horas disponibles en el rango (0-100). */
export function occupancyPercent(bookedHours: number, hoursPerDay: number, days: number): number {
  const available = hoursPerDay * days;
  return available <= 0 ? 0 : Math.min(100, Math.round((bookedHours / available) * 1000) / 10);
}

@Injectable()
export class StatsService {
  constructor(private readonly db: Db) {}

  /**
   * Métricas del dueño para un rango de fechas (YYYY-MM-DD, hora de Colombia,
   * ambas incluidas). Por defecto, los últimos 30 días. Opcionalmente de una sola cancha.
   */
  async forOwner(ownerId: string, q: { courtId?: string; from?: string; to?: string }) {
    const today = new Date(Date.now() - 5 * 3600_000).toISOString().slice(0, 10);
    const toStr = q.to ?? today;
    const fromStr = q.from ?? new Date(new Date(`${toStr}T00:00:00Z`).getTime() - 29 * DAY_MS).toISOString().slice(0, 10);
    const from = dayRangeUtc(fromStr);
    const to = dayRangeUtc(toStr);
    if (!from || !to || to.to <= from.from) {
      throw new BadRequestException({ code: 'BAD_DATE', message: 'Rango de fechas inválido' });
    }
    const days = Math.round((to.to.getTime() - from.from.getTime()) / DAY_MS);
    if (days > 366) throw new BadRequestException({ code: 'BAD_DATE', message: 'El rango máximo es de un año' });

    const courts = await this.db.query<{ hours: number }>(
      `SELECT COALESCE(SUM(close_hour - open_hour), 0)::int AS hours FROM courts
       WHERE owner_id = $1 AND status <> 'pending' AND ($2::uuid IS NULL OR id = $2)`,
      [ownerId, q.courtId ?? null],
    );
    if (q.courtId) {
      const own = await this.db.query('SELECT 1 FROM courts WHERE id = $1 AND owner_id = $2', [q.courtId, ownerId]);
      if (own.rowCount === 0) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });
    }

    const { rows } = await this.db.query<{
      total: number; confirmed: number; cancelled: number; pending: number; income: number; hours: number;
    }>(
      `SELECT COUNT(*)::int AS total,
              COUNT(*) FILTER (WHERE b.status = 'confirmed')::int AS confirmed,
              COUNT(*) FILTER (WHERE b.status = 'cancelled')::int AS cancelled,
              COUNT(*) FILTER (WHERE b.status IN ('pending_payment','pending_review'))::int AS pending,
              COALESCE(SUM(b.total) FILTER (WHERE b.status = 'confirmed'), 0)::float AS income,
              COALESCE(SUM(b.hours) FILTER (WHERE b.status = 'confirmed'), 0)::int AS hours
       FROM bookings b JOIN courts c ON c.id = b.court_id
       WHERE c.owner_id = $1 AND ($2::uuid IS NULL OR c.id = $2) AND b.start_at >= $3 AND b.start_at < $4
         AND NOT b.owner_block`,
      [ownerId, q.courtId ?? null, from.from, to.to],
    );
    const s = rows[0]!;
    return {
      from: fromStr,
      to: toStr,
      days,
      bookings: { total: s.total, confirmed: s.confirmed, cancelled: s.cancelled, awaitingPayment: s.pending },
      income: s.income,
      bookedHours: s.hours,
      occupancyPercent: occupancyPercent(s.hours, courts.rows[0]!.hours, days),
    };
  }
}

import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { COP, dateLabelCo } from '../common/time.js';
import { Db } from '../db/db.service.js';
import { NotificationsService } from '../notifications/notifications.service.js';

export interface RefundFilters {
  status?: 'pending' | 'done';
}

@Injectable()
export class RefundsService {
  constructor(
    private readonly db: Db,
    private readonly notifications: NotificationsService,
  ) {}

  /** Devoluciones de las canchas del dueño: primero las pendientes, luego las más recientes. */
  async listForOwner(ownerId: string, f: RefundFilters) {
    const { rows } = await this.db.query(
      `SELECT r.id, r.status, r.amount, r.note, r.created_at AS "createdAt", r.done_at AS "doneAt",
              c.id AS "courtId", c.name AS "courtName",
              u.name AS "playerName", u.phone AS "playerPhone", u.email AS "playerEmail",
              b.id AS "bookingId", b.start_at AS "startAt", b.hours
       FROM refunds r
       JOIN courts c ON c.id = r.court_id
       JOIN users u ON u.id = r.player_id
       JOIN bookings b ON b.id = r.booking_id
       WHERE c.owner_id = $1 AND ($2::refund_status IS NULL OR r.status = $2::refund_status)
       ORDER BY (r.status = 'done'), r.created_at DESC
       LIMIT 100`,
      [ownerId, f.status ?? null],
    );
    return rows;
  }

  /** El dueño confirma que ya devolvió el dinero. Avisa al jugador. */
  async markDone(ownerId: string, id: string, note?: string) {
    const r = (
      await this.db.query<{ player_id: string; amount: number; court_name: string; start_at: Date; status: string }>(
        `SELECT r.player_id, r.amount, r.status, c.name AS court_name, b.start_at
         FROM refunds r JOIN courts c ON c.id = r.court_id JOIN bookings b ON b.id = r.booking_id
         WHERE r.id = $1 AND c.owner_id = $2`,
        [id, ownerId],
      )
    ).rows[0];
    if (!r) throw new NotFoundException({ code: 'REFUND_NOT_FOUND', message: 'Devolución no encontrada' });
    if (r.status === 'done') {
      throw new ConflictException({ code: 'ALREADY_DONE', message: 'Esta devolución ya está registrada' });
    }
    // El estado va en el WHERE: si otro la marcó entre la lectura y ahora, no se pisa.
    const upd = await this.db.query(
      `UPDATE refunds SET status = 'done', done_at = now(), note = $2 WHERE id = $1 AND status = 'pending'`,
      [id, note?.trim() || null],
    );
    if (upd.rowCount === 0) {
      throw new ConflictException({ code: 'ALREADY_DONE', message: 'Esta devolución ya está registrada' });
    }
    void this.notifications
      .create({
        userId: r.player_id,
        title: 'Devolución enviada',
        body: `${r.court_name} te devolvió ${COP.format(r.amount)} de tu reserva del ${dateLabelCo(r.start_at)}.`,
        data: { type: 'refund_done' },
      })
      .catch(() => undefined);
    return { id, status: 'done' };
  }
}

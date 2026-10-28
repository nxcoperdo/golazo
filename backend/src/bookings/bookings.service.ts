import {
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AccountService } from '../auth/account.service.js';
import { COP, dateLabelCo, hourLabelCo } from '../common/time.js';
import { Db, EXCLUSION_VIOLATION, pgCode } from '../db/db.service.js';
import { NotificationsService } from '../notifications/notifications.service.js';
import { canCancelFree, colombiaHour, depositFor, isLastMinute, validateSlot } from './booking-policy.js';

/** Máximo de reservas esperando comprobante por jugador (evita acaparar horas). */
const MAX_UNPAID = 3;

const BOOKING_SELECT = `
  b.id, b.court_id AS "courtId", c.name AS "courtName", b.start_at AS "startAt", b.hours,
  b.end_at AS "endAt", b.total, b.deposit, b.last_minute AS "lastMinute", b.status,
  b.created_at AS "createdAt",
  EXISTS (SELECT 1 FROM reviews r WHERE r.booking_id = b.id) AS reviewed`;

export interface BookingRow {
  id: string;
  courtId: string;
  status: string;
  startAt: Date;
  createdAt: Date;
}

interface CourtRow {
  id: string;
  owner_id: string;
  name: string;
  price_per_hour: number;
  open_hour: number;
  close_hour: number;
  requires_deposit: boolean;
  deposit_percent: number;
}

@Injectable()
export class BookingsService {
  /** Minutos para subir el comprobante (el mismo valor que usa la tarea que libera las horas). */
  private readonly unpaidMinutes: number;

  constructor(
    private readonly db: Db,
    private readonly account: AccountService,
    private readonly notifications: NotificationsService,
    config: ConfigService,
  ) {
    this.unpaidMinutes = Number(config.get('UNPAID_MINUTES') ?? 30);
  }

  async create(playerId: string, input: { courtId: string; startAt: string; hours: number }) {
    const start = new Date(input.startAt);
    const now = new Date();

    await this.account.assertVerified(playerId);
    const user = await this.db.query<{ phone: string | null; name: string }>(
      'SELECT phone, name FROM users WHERE id = $1',
      [playerId],
    );
    if (!user.rows[0]?.phone) {
      throw new UnprocessableEntityException({
        code: 'PHONE_REQUIRED',
        message: 'Agrega tu celular de contacto para poder reservar',
      });
    }

    const court = (
      await this.db.query<CourtRow>(
        `SELECT id, owner_id, name, price_per_hour, open_hour, close_hour, requires_deposit, deposit_percent
         FROM courts WHERE id = $1 AND status = 'active'`,
        [input.courtId],
      )
    ).rows[0];
    if (!court) throw new NotFoundException({ code: 'COURT_NOT_FOUND', message: 'Cancha no encontrada' });

    const invalid = validateSlot({
      start,
      hours: input.hours,
      now,
      openHour: court.open_hour,
      closeHour: court.close_hour,
      startHourLocal: colombiaHour(start),
    });
    if (invalid) throw new UnprocessableEntityException({ code: 'BAD_SLOT', message: invalid });

    const unpaid = await this.db.query<{ n: number }>(
      `SELECT COUNT(*)::int AS n FROM bookings WHERE player_id = $1 AND status IN ('pending_payment','rejected')`,
      [playerId],
    );
    if (unpaid.rows[0]!.n >= MAX_UNPAID) {
      throw new ConflictException({
        code: 'TOO_MANY_UNPAID',
        message: 'Tienes varias reservas sin pagar. Paga o cancela alguna antes de reservar otra.',
      });
    }

    // Todo se calcula aquí: el servidor no confía en montos enviados por la app.
    const total = court.price_per_hour * input.hours;
    const deposit = depositFor({
      total,
      courtRequiresDeposit: court.requires_deposit,
      courtDepositPercent: court.deposit_percent,
      start,
      now,
    });
    const end = new Date(start.getTime() + input.hours * 3600_000);

    try {
      const { rows } = await this.db.query<{ id: string }>(
        `INSERT INTO bookings (court_id, player_id, start_at, hours, end_at, total, deposit, last_minute, status, reminded_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`,
        [court.id, playerId, start, input.hours, end, total, deposit, isLastMinute(start, now),
         deposit === 0 ? 'confirmed' : 'pending_payment',
         // Si empieza en menos de 2 h no tiene sentido recordarla de inmediato.
         start.getTime() - now.getTime() <= 2 * 3600_000 ? now : null],
      );
      if (deposit === 0) {
        // Sin anticipo la reserva queda confirmada al instante: el dueño debe enterarse.
        void this.notifications
          .create({
            userId: court.owner_id,
            title: 'Nueva reserva confirmada',
            body: `${user.rows[0]!.name} reservó ${court.name} el ${dateLabelCo(start)} a las ${hourLabelCo(start)} (${input.hours} h).`,
            data: { type: 'booking_new', bookingId: rows[0]!.id },
          })
          .catch(() => undefined);
      }
      return await this.detail(playerId, rows[0]!.id);
    } catch (e) {
      // La restricción EXCLUDE de la base es la defensa real contra dobles reservas.
      if (pgCode(e) === EXCLUSION_VIOLATION) {
        throw new ConflictException({ code: 'SLOT_TAKEN', message: 'Esa hora ya fue reservada' });
      }
      throw e;
    }
  }

  async listMine(playerId: string) {
    const { rows } = await this.db.query<BookingRow>(
      `SELECT ${BOOKING_SELECT} FROM bookings b JOIN courts c ON c.id = b.court_id
       WHERE b.player_id = $1 AND NOT b.owner_block ORDER BY b.start_at DESC LIMIT 100`,
      [playerId],
    );
    return rows.map((r) => this.withCancelFlag(r));
  }

  /** Detalle de una reserva propia. Incluye las cuentas de pago solo si falta pagar. */
  async detail(playerId: string, id: string) {
    const { rows } = await this.db.query<BookingRow>(
      `SELECT ${BOOKING_SELECT} FROM bookings b JOIN courts c ON c.id = b.court_id
       WHERE b.id = $1 AND b.player_id = $2 AND NOT b.owner_block`,
      [id, playerId],
    );
    const b = rows[0];
    if (!b) throw new NotFoundException({ code: 'BOOKING_NOT_FOUND', message: 'Reserva no encontrada' });

    let paymentMethods: unknown[] = [];
    if (b.status === 'pending_payment' || b.status === 'rejected') {
      paymentMethods = (
        await this.db.query(
          'SELECT label, account, holder FROM court_payment_methods WHERE court_id = $1 ORDER BY label',
          [b.courtId],
        )
      ).rows;
    }
    return { ...this.withCancelFlag(b), paymentMethods };
  }

  /**
   * Cancela una reserva propia. Sin pago hecho siempre se puede (no hay dinero
   * en juego); con comprobante enviado o confirmada solo con 24 h o más.
   */
  async cancel(playerId: string, id: string) {
    const { rows } = await this.db.query<{ status: string; start_at: Date; owner_id: string; court_name: string }>(
      `SELECT b.status, b.start_at, c.owner_id, c.name AS court_name
       FROM bookings b JOIN courts c ON c.id = b.court_id
       WHERE b.id = $1 AND b.player_id = $2 AND NOT b.owner_block`,
      [id, playerId],
    );
    const b = rows[0];
    if (!b) throw new NotFoundException({ code: 'BOOKING_NOT_FOUND', message: 'Reserva no encontrada' });
    if (b.status === 'cancelled') return this.detail(playerId, id);

    const unpaid = b.status === 'pending_payment';
    if (!unpaid && !canCancelFree(b.start_at, new Date())) {
      throw new ConflictException({
        code: 'NOT_CANCELLABLE',
        message: 'Solo se puede cancelar con 24 horas o más de anticipación',
      });
    }
    // El estado va en el WHERE: si cambió entre la lectura y ahora, no se pisa.
    const refundAmount = await this.db.tx(async (c) => {
      const upd = await c.query(
        `UPDATE bookings SET status = 'cancelled', cancelled_at = now()
         WHERE id = $1 AND player_id = $2 AND status = $3`,
        [id, playerId, b.status],
      );
      if (upd.rowCount === 0) {
        throw new ConflictException({ code: 'STATE_CHANGED', message: 'La reserva cambió, intenta de nuevo' });
      }
      // Si había un comprobante esperando revisión, deja de estarlo.
      await c.query(
        `UPDATE payments SET status = 'rejected', reject_reason = 'Reserva cancelada por el jugador', reviewed_at = now()
         WHERE booking_id = $1 AND status = 'pending'`,
        [id],
      );
      // Si el anticipo ya estaba aprobado, el dueño debe devolverlo (fuera de la app): queda el registro.
      const refund = await c.query<{ amount: number }>(
        `INSERT INTO refunds (booking_id, court_id, player_id, amount)
         SELECT b.id, b.court_id, b.player_id, SUM(p.amount)::int
         FROM bookings b JOIN payments p ON p.booking_id = b.id AND p.kind = 'booking' AND p.status = 'approved'
         WHERE b.id = $1 GROUP BY b.id HAVING SUM(p.amount) > 0
         ON CONFLICT (booking_id) DO NOTHING RETURNING amount`,
        [id],
      );
      return refund.rows[0]?.amount ?? 0;
    });
    if (b.status === 'pending_review' || b.status === 'confirmed') {
      void this.notifications
        .create({
          userId: b.owner_id,
          title: 'Reserva cancelada',
          body:
            `Un jugador canceló su reserva en ${b.court_name} del ${dateLabelCo(b.start_at)} a las ${hourLabelCo(b.start_at)}.` +
            (refundAmount > 0 ? ` Debes devolverle ${COP.format(refundAmount)} (queda en Pagos → Devoluciones).` : ''),
          data: refundAmount > 0 ? { type: 'refund_pending', bookingId: id } : { type: 'booking_cancelled', bookingId: id },
        })
        .catch(() => undefined);
    }
    return this.detail(playerId, id);
  }

  private withCancelFlag<T extends { status: string; startAt: Date; createdAt: Date }>(b: T) {
    const live = ['pending_payment', 'pending_review', 'confirmed', 'rejected'].includes(b.status);
    const cancellable = live && (b.status === 'pending_payment' || canCancelFree(b.startAt, new Date()));
    // Hasta cuándo se puede subir el comprobante antes de que la hora se libere (solo sin comprobante).
    const payBy =
      b.status === 'pending_payment' ? new Date(b.createdAt.getTime() + this.unpaidMinutes * 60_000) : null;
    return { ...b, cancellable, payBy };
  }
}

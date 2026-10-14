import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { PoolClient } from 'pg';
import { hourLabelCo } from '../common/time.js';
import { Db } from '../db/db.service.js';
import { type Notice, NotificationsService } from '../notifications/notifications.service.js';

export interface JobsResult {
  expiredUnpaid: number;
  suspendedCourts: number;
  subscriptionReminders: number;
  bookingReminders: number;
  cleaned: number;
}

const TODAY = `(now() AT TIME ZONE 'America/Bogota')::date`;
const LOCK_KEY = 7001;

/**
 * Tareas periódicas (cada minuto). Un candado de PostgreSQL asegura que, aunque
 * haya varias instancias de la API, solo una ejecute las tareas a la vez.
 */
@Injectable()
export class JobsService implements OnModuleInit, OnModuleDestroy {
  private readonly log = new Logger(JobsService.name);
  private timer: NodeJS.Timeout | null = null;
  private readonly unpaidMinutes: number;
  private readonly enabled: boolean;

  constructor(
    private readonly db: Db,
    private readonly notifications: NotificationsService,
    config: ConfigService,
  ) {
    this.unpaidMinutes = Number(config.get('UNPAID_MINUTES') ?? 30);
    this.enabled = config.get('DISABLE_JOBS') !== '1';
  }

  onModuleInit(): void {
    if (!this.enabled) return;
    this.timer = setInterval(() => {
      this.runAll().catch((e: Error) => this.log.error(`Tareas fallaron: ${e.message}`));
    }, 60_000);
    this.timer.unref();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  /** Ejecuta todas las tareas una vez (también disponible para el admin). */
  async runAll(): Promise<JobsResult> {
    const notices: Notice[] = [];
    const result = await this.db.tx<JobsResult>(async (c) => {
      const lock = await c.query<{ ok: boolean }>('SELECT pg_try_advisory_xact_lock($1) AS ok', [LOCK_KEY]);
      if (!lock.rows[0]!.ok) {
        return { expiredUnpaid: 0, suspendedCourts: 0, subscriptionReminders: 0, bookingReminders: 0, cleaned: 0 };
      }
      return {
        expiredUnpaid: await this.expireUnpaid(c, notices),
        suspendedCourts: await this.expireSubscriptions(c, notices),
        subscriptionReminders: await this.remindSubscriptions(c, notices),
        bookingReminders: await this.remindBookings(c, notices),
        cleaned: await this.cleanup(c),
      };
    });
    await this.notifications.deliver(notices);
    return result;
  }

  /**
   * Libera la hora de reservas que esperan comprobante desde hace más de N min
   * (nunca pagaron, o el pago fue rechazado y no subieron otro).
   */
  private async expireUnpaid(c: PoolClient, notices: Notice[]): Promise<number> {
    const { rows } = await c.query<{ id: string; player_id: string; court_name: string }>(
      `UPDATE bookings b SET status = 'cancelled', cancelled_at = now()
       FROM courts c
       WHERE c.id = b.court_id AND (
             (b.status = 'pending_payment' AND b.created_at < now() - make_interval(mins => $1))
          OR (b.status = 'rejected' AND COALESCE(
                (SELECT MAX(p.reviewed_at) FROM payments p WHERE p.booking_id = b.id), b.created_at)
                < now() - make_interval(mins => $1)))
       RETURNING b.id, b.player_id, c.name AS court_name`,
      [this.unpaidMinutes],
    );
    for (const r of rows) {
      const n: Notice = {
        userId: r.player_id,
        title: 'Reserva cancelada',
        body: `Tu reserva en ${r.court_name} se canceló porque no recibimos el comprobante a tiempo.`,
        data: { type: 'booking_expired', bookingId: r.id },
      };
      await this.notifications.record(c, n);
      notices.push(n);
    }
    return rows.length;
  }

  /** Suspende canchas activas cuyo periodo de mensualidad ya venció. */
  private async expireSubscriptions(c: PoolClient, notices: Notice[]): Promise<number> {
    const { rows } = await c.query<{ id: string; owner_id: string; name: string }>(
      `UPDATE courts c SET status = 'suspended', suspended_by_admin = false
       WHERE c.status = 'active' AND NOT EXISTS (
         SELECT 1 FROM subscription_periods sp
         WHERE sp.court_id = c.id AND sp.starts_on <= ${TODAY} AND ${TODAY} < sp.ends_on)
       RETURNING c.id, c.owner_id, c.name`,
    );
    for (const r of rows) {
      const n: Notice = {
        userId: r.owner_id,
        title: 'Tu cancha dejó de ser visible',
        body: `La mensualidad de ${r.name} venció. Sube tu pago para volver a aparecer en el buscador.`,
        data: { type: 'subscription_expired', courtId: r.id },
        email: true,
      };
      await this.notifications.record(c, n);
      notices.push(n);
    }
    return rows.length;
  }

  /** Avisa 3 días antes del vencimiento, una sola vez por periodo y solo si no hay renovación. */
  private async remindSubscriptions(c: PoolClient, notices: Notice[]): Promise<number> {
    const { rows } = await c.query<{ owner_id: string; name: string; ends_on: string; court_id: string }>(
      `UPDATE subscription_periods sp SET reminded_at = now()
       FROM courts c
       WHERE sp.court_id = c.id AND sp.reminded_at IS NULL
         AND sp.ends_on > ${TODAY} AND sp.ends_on - ${TODAY} <= 3
         AND NOT EXISTS (SELECT 1 FROM subscription_periods n WHERE n.court_id = sp.court_id AND n.ends_on > sp.ends_on)
       RETURNING c.owner_id, c.name, sp.ends_on::text AS ends_on, c.id AS court_id`,
    );
    for (const r of rows) {
      const n: Notice = {
        userId: r.owner_id,
        title: 'Tu mensualidad está por vencer',
        body: `La mensualidad de ${r.name} vence el ${r.ends_on}. Renueva para seguir visible.`,
        data: { type: 'subscription_expiring', courtId: r.court_id },
        email: true,
      };
      await this.notifications.record(c, n);
      notices.push(n);
    }
    return rows.length;
  }

  /** Recuerda a los jugadores su reserva confirmada cuando faltan 2 horas o menos (una sola vez). */
  private async remindBookings(c: PoolClient, notices: Notice[]): Promise<number> {
    const { rows } = await c.query<{ id: string; player_id: string; start_at: Date; name: string }>(
      `UPDATE bookings b SET reminded_at = now()
       FROM courts c
       WHERE c.id = b.court_id AND b.status = 'confirmed' AND NOT b.owner_block AND b.reminded_at IS NULL
         AND b.start_at > now() AND b.start_at <= now() + interval '2 hours'
       RETURNING b.id, b.player_id, b.start_at, c.name`,
    );
    for (const r of rows) {
      const n: Notice = {
        userId: r.player_id,
        title: 'Tu partido es pronto',
        body: `Tu reserva en ${r.name} empieza a las ${hourLabelCo(r.start_at)}. ¡Nos vemos en la cancha!`,
        data: { type: 'booking_reminder', bookingId: r.id },
      };
      await this.notifications.record(c, n);
      notices.push(n);
    }
    return rows.length;
  }

  /** Borra tokens de sesión y de recuperación que ya no sirven. */
  private async cleanup(c: PoolClient): Promise<number> {
    const a = await c.query(
      `DELETE FROM refresh_tokens WHERE expires_at < now() - interval '7 days' OR revoked_at < now() - interval '30 days'`,
    );
    const b = await c.query(`DELETE FROM password_resets WHERE expires_at < now() - interval '1 day'`);
    const d = await c.query(`DELETE FROM email_verifications WHERE expires_at < now() - interval '7 days'`);
    return (a.rowCount ?? 0) + (b.rowCount ?? 0) + (d.rowCount ?? 0);
  }
}

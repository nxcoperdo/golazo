import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { Db } from '../db/db.service.js';
import { MailerService } from './mailer.service.js';
import { PushService } from './push.service.js';

export interface Notice {
  userId: string;
  title: string;
  body: string;
  /** Para abrir la pantalla correcta al tocar la notificación. */
  data?: Record<string, string>;
  /** Además de la bandeja y el push, envía correo (avisos críticos como pagos). */
  email?: boolean;
}

const INSERT = 'INSERT INTO notifications (user_id, title, body, data) VALUES ($1, $2, $3, $4)';

/**
 * La bandeja (tabla notifications) es la fuente de verdad. `record` guarda la
 * fila dentro de la transacción del evento; `deliver` envía push y correo
 * después de confirmar, sin lanzar errores.
 */
@Injectable()
export class NotificationsService {
  private readonly log = new Logger(NotificationsService.name);

  constructor(
    private readonly db: Db,
    private readonly push: PushService,
    private readonly mailer: MailerService,
  ) {}

  async record(c: PoolClient, n: Notice): Promise<void> {
    await c.query(INSERT, [n.userId, n.title, n.body, n.data ? JSON.stringify(n.data) : null]);
  }

  /** Para eventos fuera de una transacción: guarda y entrega. */
  async create(n: Notice): Promise<void> {
    await this.db.query(INSERT, [n.userId, n.title, n.body, n.data ? JSON.stringify(n.data) : null]);
    await this.deliver([n]);
  }

  async deliver(list: Notice[]): Promise<void> {
    for (const n of list) {
      try {
        await this.push.send(n.userId, n.title, n.body, n.data);
      } catch (e) {
        this.log.warn(`Push falló para ${n.userId}: ${(e as Error).message}`);
      }
      if (n.email) {
        try {
          const { rows } = await this.db.query<{ email: string | null }>('SELECT email FROM users WHERE id = $1', [n.userId]);
          const to = rows[0]?.email;
          if (to) await this.mailer.send(to, n.title, n.body);
        } catch (e) {
          this.log.warn(`Correo falló para ${n.userId}: ${(e as Error).message}`);
        }
      }
    }
  }

  /** Todos los administradores activos (para avisarles de pagos por revisar). */
  async adminIds(): Promise<string[]> {
    const { rows } = await this.db.query<{ id: string }>(
      `SELECT id FROM users WHERE role = 'admin' AND deleted_at IS NULL AND suspended_at IS NULL`,
    );
    return rows.map((r) => r.id);
  }

  // ---- Bandeja del usuario ----

  async list(userId: string, limit: number, offset: number) {
    const [items, unread] = await Promise.all([
      this.db.query(
        `SELECT id, title, body, data, read_at AS "readAt", created_at AS "createdAt"
         FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
        [userId, limit, offset],
      ),
      this.db.query<{ n: number }>(
        'SELECT COUNT(*)::int AS n FROM notifications WHERE user_id = $1 AND read_at IS NULL',
        [userId],
      ),
    ]);
    return { unread: unread.rows[0]!.n, items: items.rows };
  }

  async markRead(userId: string, id: string): Promise<void> {
    const r = await this.db.query(
      'UPDATE notifications SET read_at = COALESCE(read_at, now()) WHERE id = $1 AND user_id = $2',
      [id, userId],
    );
    if (r.rowCount === 0) throw new NotFoundException({ code: 'NOT_FOUND', message: 'Notificación no encontrada' });
  }

  async markAllRead(userId: string): Promise<void> {
    await this.db.query('UPDATE notifications SET read_at = now() WHERE user_id = $1 AND read_at IS NULL', [userId]);
  }

  /** Un token pertenece a un solo usuario: si el dispositivo cambia de cuenta, se reasigna. */
  async registerDevice(userId: string, platform: 'android' | 'ios', token: string): Promise<void> {
    await this.db.query(
      `INSERT INTO device_tokens (user_id, platform, token) VALUES ($1, $2, $3)
       ON CONFLICT (token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform`,
      [userId, platform, token],
    );
  }

  async removeDevice(userId: string, token: string): Promise<void> {
    await this.db.query('DELETE FROM device_tokens WHERE user_id = $1 AND token = $2', [userId, token]);
  }
}

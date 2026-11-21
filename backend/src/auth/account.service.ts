import { ForbiddenException, Injectable, UnauthorizedException, UnprocessableEntityException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import argon2 from 'argon2';
import { createHash, randomBytes } from 'node:crypto';
import type { PoolClient } from 'pg';
import { Db } from '../db/db.service.js';
import { renderEmail } from '../notifications/email-template.js';
import { MailerService } from '../notifications/mailer.service.js';
import { StorageService } from '../storage/storage.service.js';
import { AuthService, type AuthResult, type UserRow } from './auth.service.js';

const RESET_TTL_MS = 3600_000;
const MAX_RESETS_PER_HOUR = 3;

const sha256 = (s: string): string => createHash('sha256').update(s).digest('hex');

@Injectable()
export class AccountService {
  private readonly publicUrl: string;
  private readonly requireVerified: boolean;

  constructor(
    private readonly db: Db,
    private readonly auth: AuthService,
    private readonly mailer: MailerService,
    private readonly storage: StorageService,
    config: ConfigService,
  ) {
    // Los correos llevan enlaces https (clicables en cualquier cliente) a /open/*, que abre la app.
    this.publicUrl = (config.get<string>('PUBLIC_BASE_URL') || 'http://localhost:3000').replace(/\/+$/, '');
    // Activar solo cuando el correo (SMTP) esté configurado; si no, nadie podría verificar.
    this.requireVerified = config.get('REQUIRE_EMAIL_VERIFICATION') === '1';
  }

  async updateProfile(userId: string, patch: { name?: string; phone?: string }) {
    const sets: string[] = [];
    const params: unknown[] = [];
    if (patch.name !== undefined) sets.push(`name = $${params.push(patch.name.trim())}`);
    if (patch.phone !== undefined) sets.push(`phone = $${params.push(patch.phone)}`);
    if (sets.length > 0) {
      params.push(userId);
      await this.db.query(`UPDATE users SET ${sets.join(', ')} WHERE id = $${params.length}`, params);
    }
    const { rows } = await this.db.query(
      'SELECT id, name, email, phone, role, (email_verified_at IS NOT NULL) AS "emailVerified" FROM users WHERE id = $1',
      [userId],
    );
    return rows[0];
  }

  // ---------- Verificación de correo ----------

  /** Si está activada la verificación, exige correo confirmado para reservar o publicar canchas. */
  async assertVerified(userId: string): Promise<void> {
    if (!this.requireVerified) return;
    const { rows } = await this.db.query<{ ok: boolean }>(
      'SELECT (email_verified_at IS NOT NULL) AS ok FROM users WHERE id = $1',
      [userId],
    );
    if (!rows[0]?.ok) {
      throw new ForbiddenException({ code: 'EMAIL_NOT_VERIFIED', message: 'Confirma tu correo para continuar' });
    }
  }

  /** Envía el enlace de confirmación (máx. 5 por hora). No hace nada si ya está verificado. */
  async sendVerification(userId: string): Promise<void> {
    const u = (
      await this.db.query<{ email: string | null; email_verified_at: Date | null }>(
        'SELECT email, email_verified_at FROM users WHERE id = $1 AND deleted_at IS NULL',
        [userId],
      )
    ).rows[0];
    if (!u?.email || u.email_verified_at) return;
    const recent = await this.db.query<{ n: number }>(
      `SELECT COUNT(*)::int AS n FROM email_verifications WHERE user_id = $1 AND created_at > now() - interval '1 hour'`,
      [userId],
    );
    if (recent.rows[0]!.n >= 5) return;

    const token = randomBytes(32).toString('base64url');
    await this.db.query('INSERT INTO email_verifications (user_id, token_hash, expires_at) VALUES ($1, $2, $3)', [
      userId,
      sha256(token),
      new Date(Date.now() + 24 * RESET_TTL_MS),
    ]);
    const mail = renderEmail({
      title: 'Confirma tu correo',
      preheader: 'Un toque y tu cuenta de Golazo queda lista.',
      paragraphs: ['¡Bienvenido a Golazo! Confirma tu correo para poder reservar canchas y publicar las tuyas.'],
      button: { label: 'Confirmar mi correo', url: `${this.publicUrl}/open/verify?token=${token}` },
      note: 'El enlace vale 24 horas. Si no creaste una cuenta, ignora este mensaje.',
    });
    await this.mailer.send(u.email, 'Confirma tu correo en Golazo', mail.text, mail.html);
  }

  async verifyEmail(token: string): Promise<void> {
    await this.db.tx(async (c) => {
      const r = (
        await c.query<{ id: string; user_id: string }>(
          `SELECT id, user_id FROM email_verifications
           WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now() FOR UPDATE`,
          [sha256(token)],
        )
      ).rows[0];
      if (!r) throw new UnprocessableEntityException({ code: 'BAD_VERIFY_TOKEN', message: 'El enlace no es válido o expiró' });
      await c.query('UPDATE email_verifications SET used_at = now() WHERE user_id = $1 AND used_at IS NULL', [r.user_id]);
      await c.query('UPDATE users SET email_verified_at = COALESCE(email_verified_at, now()) WHERE id = $1', [r.user_id]);
    });
  }

  /** Cambia la contraseña, cierra todas las sesiones y devuelve una sesión nueva. */
  async changePassword(userId: string, current: string, next: string): Promise<AuthResult> {
    const u = (await this.db.query<UserRow>('SELECT * FROM users WHERE id = $1', [userId])).rows[0];
    if (!u?.password_hash || !(await argon2.verify(u.password_hash, current))) {
      throw new UnauthorizedException({ code: 'BAD_CREDENTIALS', message: 'La contraseña actual es incorrecta' });
    }
    await this.setPassword(userId, next);
    return this.auth.issueForUser(userId);
  }

  /**
   * Envía un enlace de recuperación. Siempre responde igual exista o no el
   * correo, para no revelar qué correos están registrados.
   */
  async forgotPassword(emailRaw: string): Promise<void> {
    const email = emailRaw.trim().toLowerCase();
    const u = (
      await this.db.query<{ id: string }>(
        'SELECT id FROM users WHERE email = $1 AND deleted_at IS NULL AND suspended_at IS NULL',
        [email],
      )
    ).rows[0];
    if (!u) return;
    const recent = await this.db.query<{ n: number }>(
      `SELECT COUNT(*)::int AS n FROM password_resets WHERE user_id = $1 AND created_at > now() - interval '1 hour'`,
      [u.id],
    );
    if (recent.rows[0]!.n >= MAX_RESETS_PER_HOUR) return;

    const token = randomBytes(32).toString('base64url');
    await this.db.query('INSERT INTO password_resets (user_id, token_hash, expires_at) VALUES ($1, $2, $3)', [
      u.id,
      sha256(token),
      new Date(Date.now() + RESET_TTL_MS),
    ]);
    const mail = renderEmail({
      title: 'Crea una contraseña nueva',
      preheader: 'Recibimos una solicitud para recuperar tu contraseña.',
      paragraphs: ['Recibimos una solicitud para recuperar tu contraseña de Golazo. Toca el botón desde tu celular para crear una nueva.'],
      button: { label: 'Crear contraseña nueva', url: `${this.publicUrl}/open/reset?token=${token}` },
      note: 'El enlace vale 1 hora. Si no fuiste tú, ignora este mensaje: tu contraseña no cambiará.',
    });
    await this.mailer.send(email, 'Recupera tu contraseña de Golazo', mail.text, mail.html);
  }

  async resetPassword(token: string, next: string): Promise<void> {
    await this.db.tx(async (c) => {
      const r = (
        await c.query<{ id: string; user_id: string }>(
          `SELECT id, user_id FROM password_resets
           WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now() FOR UPDATE`,
          [sha256(token)],
        )
      ).rows[0];
      if (!r) throw new UnprocessableEntityException({ code: 'BAD_RESET_TOKEN', message: 'El enlace no es válido o expiró' });
      await c.query('UPDATE password_resets SET used_at = now() WHERE user_id = $1 AND used_at IS NULL', [r.user_id]);
      await c.query('UPDATE users SET password_hash = $2 WHERE id = $1', [r.user_id, await argon2.hash(next)]);
      await c.query('UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [r.user_id]);
    });
  }

  /** Borra la propia cuenta (se anonimiza). Con contraseña, se exige confirmarla. */
  async deleteOwnAccount(userId: string, password?: string): Promise<void> {
    const u = (await this.db.query<UserRow>('SELECT * FROM users WHERE id = $1', [userId])).rows[0];
    if (!u) return;
    if (u.role === 'admin') {
      throw new ForbiddenException({ code: 'ADMIN_PROTECTED', message: 'Las cuentas de administrador no se borran desde la app' });
    }
    if (u.password_hash && (!password || !(await argon2.verify(u.password_hash, password)))) {
      throw new UnauthorizedException({ code: 'BAD_CREDENTIALS', message: 'Confirma tu contraseña para borrar la cuenta' });
    }
    await this.anonymizeUser(userId);
  }

  async anonymizeUser(userId: string): Promise<void> {
    const files = await this.db.tx((c) => this.anonymize(c, userId));
    // Las fotos del chat se borran del disco solo cuando la transacción ya se confirmó.
    for (const f of files) await this.storage.remove('chat', f);
  }

  /**
   * Quita los datos personales pero conserva reservas, pagos y reseñas (historial
   * de transacciones). Cancela sus reservas futuras y suspende sus canchas.
   */
  private async anonymize(c: PoolClient, userId: string): Promise<string[]> {
    // Chat: sus fotos y las de su hilo de soporte se eliminan; sus textos pasan a «Mensaje eliminado».
    const imgs = await c.query<{ image_path: string }>(
      `SELECT image_path FROM chat_messages
       WHERE image_path IS NOT NULL
         AND (sender_id = $1 OR thread_id IN (SELECT id FROM chat_threads WHERE kind = 'support' AND participant_id = $1))`,
      [userId],
    );
    await c.query(
      `UPDATE chat_messages SET body = 'Mensaje eliminado', image_path = NULL, hidden_at = COALESCE(hidden_at, now())
       WHERE sender_id = $1`,
      [userId],
    );
    await c.query(`DELETE FROM chat_threads WHERE kind = 'support' AND participant_id = $1`, [userId]);
    await c.query('DELETE FROM chat_blocks WHERE blocker_id = $1 OR blocked_id = $1', [userId]);
    await c.query('DELETE FROM chat_reads WHERE user_id = $1', [userId]);
    await c.query(
      `UPDATE users SET name = 'Usuario eliminado', email = NULL, phone = NULL, google_sub = NULL,
                        password_hash = NULL, deleted_at = now(), suspended_at = NULL
       WHERE id = $1`,
      [userId],
    );
    await c.query('UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [userId]);
    await c.query('DELETE FROM device_tokens WHERE user_id = $1', [userId]);
    await c.query('DELETE FROM password_resets WHERE user_id = $1', [userId]);
    const cancelled = await c.query<{ id: string }>(
      `UPDATE bookings SET status = 'cancelled', cancelled_at = now()
       WHERE player_id = $1 AND end_at > now()
         AND status IN ('pending_payment','pending_review','confirmed','rejected') RETURNING id`,
      [userId],
    );
    if (cancelled.rows.length > 0) {
      await c.query(
        `UPDATE payments SET status = 'rejected', reject_reason = 'Cuenta eliminada', reviewed_at = now()
         WHERE booking_id = ANY($1::uuid[]) AND status = 'pending'`,
        [cancelled.rows.map((r) => r.id)],
      );
    }
    await c.query(`UPDATE courts SET status = 'suspended', suspended_by_admin = true WHERE owner_id = $1`, [userId]);
    return imgs.rows.map((r) => r.image_path);
  }

  private async setPassword(userId: string, next: string): Promise<void> {
    await this.db.tx(async (c) => {
      await c.query('UPDATE users SET password_hash = $2 WHERE id = $1', [userId, await argon2.hash(next)]);
      await c.query('UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [userId]);
    });
  }
}

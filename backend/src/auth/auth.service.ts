import {
  ConflictException,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import argon2 from 'argon2';
import { createHash, randomBytes } from 'node:crypto';
import { OAuth2Client } from 'google-auth-library';
import type { PoolClient } from 'pg';
import { Db, UNIQUE_VIOLATION, pgCode } from '../db/db.service.js';

export type Role = 'player' | 'owner' | 'admin';

export interface UserRow {
  id: string;
  role: Role;
  name: string;
  email: string | null;
  phone: string | null;
  password_hash: string | null;
  suspended_at: Date | null;
  deleted_at: Date | null;
  email_verified_at: Date | null;
}

export interface AuthResult {
  accessToken: string;
  refreshToken: string;
  user: { id: string; name: string; email: string | null; phone: string | null; role: Role; emailVerified: boolean };
}

const REFRESH_TTL_DAYS = 30;

const sha256 = (s: string): string => createHash('sha256').update(s).digest('hex');

@Injectable()
export class AuthService {
  private readonly google: OAuth2Client;
  private readonly googleClientId: string | undefined;

  constructor(
    private readonly db: Db,
    private readonly jwt: JwtService,
    config: ConfigService,
  ) {
    this.googleClientId = config.get<string>('GOOGLE_CLIENT_ID');
    this.google = new OAuth2Client(this.googleClientId);
  }

  async register(input: {
    name: string;
    email: string;
    password: string;
    phone: string;
    asOwner?: boolean;
  }): Promise<AuthResult> {
    const email = input.email.trim().toLowerCase();
    const hash = await argon2.hash(input.password);
    try {
      const { rows } = await this.db.query<UserRow>(
        `INSERT INTO users (name, email, phone, password_hash, role)
         VALUES ($1, $2, $3, $4, $5) RETURNING *`,
        [input.name.trim(), email, input.phone, hash, input.asOwner ? 'owner' : 'player'],
      );
      return this.issue(rows[0]!);
    } catch (e) {
      if (pgCode(e) === UNIQUE_VIOLATION) {
        throw new ConflictException({ code: 'EMAIL_TAKEN', message: 'Ese correo ya está registrado' });
      }
      throw e;
    }
  }

  async login(emailRaw: string, password: string): Promise<AuthResult> {
    const { rows } = await this.db.query<UserRow>('SELECT * FROM users WHERE email = $1', [
      emailRaw.trim().toLowerCase(),
    ]);
    const user = rows[0];
    // Mismo error para usuario inexistente y contraseña incorrecta.
    const ok = user?.password_hash ? await argon2.verify(user.password_hash, password) : false;
    if (!user || !ok) {
      throw new UnauthorizedException({ code: 'BAD_CREDENTIALS', message: 'Correo o contraseña incorrectos' });
    }
    this.assertActive(user);
    return this.issue(user);
  }

  async loginWithGoogle(idToken: string, phone?: string): Promise<AuthResult> {
    if (!this.googleClientId) {
      throw new UnauthorizedException({ code: 'GOOGLE_DISABLED', message: 'Google no está configurado' });
    }
    let payload;
    try {
      const ticket = await this.google.verifyIdToken({ idToken, audience: this.googleClientId });
      payload = ticket.getPayload();
    } catch {
      throw new UnauthorizedException({ code: 'BAD_GOOGLE_TOKEN', message: 'Token de Google inválido' });
    }
    if (!payload?.sub || !payload.email || !payload.email_verified) {
      throw new UnauthorizedException({ code: 'BAD_GOOGLE_TOKEN', message: 'Cuenta de Google sin correo verificado' });
    }
    const email = payload.email.toLowerCase();

    const user = await this.db.tx(async (c) => {
      const found = await c.query<UserRow>('SELECT * FROM users WHERE google_sub = $1 OR email = $2', [
        payload.sub,
        email,
      ]);
      const existing = found.rows[0];
      if (existing) {
        // Vincula la cuenta de Google a un registro previo por correo.
        const upd = await c.query<UserRow>(
          `UPDATE users SET google_sub = COALESCE(google_sub, $1), phone = COALESCE(phone, $2),
                            email_verified_at = COALESCE(email_verified_at, now())
           WHERE id = $3 RETURNING *`,
          [payload.sub, phone ?? null, existing.id],
        );
        return upd.rows[0]!;
      }
      const ins = await c.query<UserRow>(
        `INSERT INTO users (name, email, phone, google_sub, email_verified_at) VALUES ($1, $2, $3, $4, now()) RETURNING *`,
        [payload.name ?? email, email, phone ?? null, payload.sub],
      );
      return ins.rows[0]!;
    });
    this.assertActive(user);
    return this.issue(user);
  }

  /** Rota el refresh token. Si llega uno ya usado, se cierran todas las sesiones del usuario. */
  async refresh(token: string): Promise<AuthResult> {
    const hash = sha256(token);
    const result = await this.db.tx<AuthResult | 'reused'>(async (c) => {
      const { rows } = await c.query<{ id: string; user_id: string; revoked_at: Date | null; expires_at: Date }>(
        'SELECT id, user_id, revoked_at, expires_at FROM refresh_tokens WHERE token_hash = $1 FOR UPDATE',
        [hash],
      );
      const rt = rows[0];
      if (!rt || rt.expires_at < new Date()) {
        throw new UnauthorizedException({ code: 'BAD_REFRESH', message: 'Sesión expirada' });
      }
      if (rt.revoked_at) {
        await c.query('UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [
          rt.user_id,
        ]);
        // No se lanza aquí: eso haría ROLLBACK y desharía la revocación.
        return 'reused';
      }
      await c.query('UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1', [rt.id]);
      const u = await c.query<UserRow>('SELECT * FROM users WHERE id = $1', [rt.user_id]);
      const user = u.rows[0]!;
      this.assertActive(user);
      return this.issue(user, c);
    });
    if (result === 'reused') {
      throw new UnauthorizedException({ code: 'REUSED_REFRESH', message: 'Sesión inválida' });
    }
    return result;
  }

  async logout(token: string): Promise<void> {
    await this.db.query('UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1 AND revoked_at IS NULL', [
      sha256(token),
    ]);
  }

  /** Emite una sesión nueva para un usuario existente (p. ej. tras cambiar la contraseña). */
  async issueForUser(userId: string): Promise<AuthResult> {
    const { rows } = await this.db.query<UserRow>('SELECT * FROM users WHERE id = $1', [userId]);
    return this.issue(rows[0]!);
  }

  private assertActive(user: UserRow): void {
    if (user.deleted_at) {
      throw new UnauthorizedException({ code: 'BAD_CREDENTIALS', message: 'Correo o contraseña incorrectos' });
    }
    if (user.suspended_at) {
      throw new ForbiddenException({ code: 'SUSPENDED', message: 'Tu cuenta está suspendida' });
    }
  }

  private async issue(user: UserRow, client?: PoolClient): Promise<AuthResult> {
    const accessToken = await this.jwt.signAsync({ sub: user.id, role: user.role });
    const refreshToken = randomBytes(48).toString('base64url');
    const expires = new Date(Date.now() + REFRESH_TTL_DAYS * 24 * 3600 * 1000);
    const sql = 'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)';
    const params = [user.id, sha256(refreshToken), expires];
    if (client) await client.query(sql, params);
    else await this.db.query(sql, params);
    return {
      accessToken,
      refreshToken,
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        role: user.role,
        emailVerified: user.email_verified_at != null,
      },
    };
  }
}

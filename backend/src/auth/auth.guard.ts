import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  SetMetadata,
  UnauthorizedException,
  createParamDecorator,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import type { Request } from 'express';
import { Db } from '../db/db.service.js';
import type { Role } from './auth.service.js';

export interface AuthUser {
  id: string;
  role: Role;
}

type AuthedRequest = Request & { user?: AuthUser };

export const ROLES_KEY = 'roles';
/** Restringe una ruta a ciertos roles. Sin este decorador basta con estar autenticado. */
export const Roles = (...roles: Role[]) => SetMetadata(ROLES_KEY, roles);

export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AuthUser => ctx.switchToHttp().getRequest<AuthedRequest>().user!,
);

/**
 * Valida el JWT y consulta la base en cada petición para que suspender o borrar
 * a un usuario tenga efecto inmediato (no solo cuando expire su token).
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly db: Db,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    const header = req.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7) : undefined;
    if (!token) throw new UnauthorizedException({ code: 'NO_TOKEN', message: 'Falta iniciar sesión' });

    let sub: string;
    try {
      ({ sub } = await this.jwt.verifyAsync<{ sub: string }>(token));
    } catch {
      throw new UnauthorizedException({ code: 'BAD_TOKEN', message: 'Sesión inválida o expirada' });
    }

    const { rows } = await this.db.query<{ id: string; role: Role; suspended_at: Date | null; deleted_at: Date | null }>(
      'SELECT id, role, suspended_at, deleted_at FROM users WHERE id = $1',
      [sub],
    );
    const user = rows[0];
    if (!user || user.deleted_at) {
      throw new UnauthorizedException({ code: 'BAD_TOKEN', message: 'Sesión inválida o expirada' });
    }
    if (user.suspended_at) {
      throw new ForbiddenException({ code: 'SUSPENDED', message: 'Tu cuenta está suspendida' });
    }

    const roles = this.reflector.getAllAndOverride<Role[] | undefined>(ROLES_KEY, [ctx.getHandler(), ctx.getClass()]);
    // El rol se toma de la base, no del token: un cambio de rol aplica de inmediato.
    if (roles && !roles.includes(user.role)) {
      throw new ForbiddenException({ code: 'FORBIDDEN', message: 'No tienes permiso para esto' });
    }
    req.user = { id: user.id, role: user.role };
    return true;
  }
}

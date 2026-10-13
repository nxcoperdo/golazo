import { Body, Controller, Get, HttpCode, Post, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Db } from '../db/db.service.js';
import { GoogleDto, LoginDto, RefreshDto, RegisterDto } from './auth.dto.js';
import { AuthGuard, CurrentUser, type AuthUser } from './auth.guard.js';
import { AuthService } from './auth.service.js';

// 10 intentos por minuto y por IP en las rutas de entrada (frena fuerza bruta).
const AUTH_LIMIT = { default: { limit: 10, ttl: 60_000 } };

@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly db: Db,
  ) {}

  @Throttle(AUTH_LIMIT)
  @Post('register')
  register(@Body() dto: RegisterDto) {
    return this.auth.register(dto);
  }

  @Throttle(AUTH_LIMIT)
  @HttpCode(200)
  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.auth.login(dto.email, dto.password);
  }

  @Throttle(AUTH_LIMIT)
  @HttpCode(200)
  @Post('google')
  google(@Body() dto: GoogleDto) {
    return this.auth.loginWithGoogle(dto.idToken, dto.phone);
  }

  @Throttle(AUTH_LIMIT)
  @HttpCode(200)
  @Post('refresh')
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @HttpCode(204)
  @Post('logout')
  async logout(@Body() dto: RefreshDto): Promise<void> {
    await this.auth.logout(dto.refreshToken);
  }

  @UseGuards(AuthGuard)
  @Get('me')
  async me(@CurrentUser() user: AuthUser) {
    const { rows } = await this.db.query(
      'SELECT id, name, email, phone, role FROM users WHERE id = $1',
      [user.id],
    );
    return rows[0];
  }
}

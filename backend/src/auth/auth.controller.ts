import { Body, Controller, Delete, Get, HttpCode, Patch, Post, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Db } from '../db/db.service.js';
import {
  ChangePasswordDto,
  ConsentDto,
  DeleteAccountDto,
  ForgotPasswordDto,
  GoogleDto,
  LoginDto,
  RefreshDto,
  RegisterDto,
  ResetPasswordDto,
  UpdateProfileDto,
  VerifyEmailDto,
} from './auth.dto.js';
import { AccountService } from './account.service.js';
import { AuthGuard, CurrentUser, type AuthUser } from './auth.guard.js';
import { AuthService, consentRequired } from './auth.service.js';

// 10 intentos por minuto y por IP en las rutas de entrada (frena fuerza bruta).
const AUTH_LIMIT = { default: { limit: 10, ttl: 60_000 } };

@Controller('auth')
export class AuthController {
  constructor(
    private readonly auth: AuthService,
    private readonly account: AccountService,
    private readonly db: Db,
  ) {}

  @Throttle(AUTH_LIMIT)
  @Post('register')
  async register(@Body() dto: RegisterDto) {
    const result = await this.auth.register(dto);
    // El correo de confirmación no debe frenar ni romper el registro.
    void this.account.sendVerification(result.user.id).catch(() => undefined);
    return result;
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
      `SELECT id, name, email, phone, role, (email_verified_at IS NOT NULL) AS "emailVerified",
              terms_accepted_at, terms_version FROM users WHERE id = $1`,
      [user.id],
    );
    const { terms_accepted_at, terms_version, ...rest } = rows[0] as {
      terms_accepted_at: Date | null;
      terms_version: string | null;
    } & Record<string, unknown>;
    return { ...rest, consentRequired: consentRequired({ terms_accepted_at, terms_version }) };
  }

  @UseGuards(AuthGuard)
  @HttpCode(200)
  @Post('consent')
  consent(@CurrentUser() user: AuthUser, @Body() _dto: ConsentDto) {
    return this.auth.acceptTerms(user.id);
  }

  @UseGuards(AuthGuard)
  @Patch('me')
  updateMe(@CurrentUser() user: AuthUser, @Body() dto: UpdateProfileDto) {
    return this.account.updateProfile(user.id, dto);
  }

  @UseGuards(AuthGuard)
  @HttpCode(204)
  @Delete('me')
  async deleteMe(@CurrentUser() user: AuthUser, @Body() dto: DeleteAccountDto): Promise<void> {
    await this.account.deleteOwnAccount(user.id, dto.password);
  }

  @Throttle(AUTH_LIMIT)
  @UseGuards(AuthGuard)
  @HttpCode(200)
  @Post('change-password')
  changePassword(@CurrentUser() user: AuthUser, @Body() dto: ChangePasswordDto) {
    return this.account.changePassword(user.id, dto.current, dto.next);
  }

  @Throttle(AUTH_LIMIT)
  @HttpCode(204)
  @Post('forgot-password')
  async forgot(@Body() dto: ForgotPasswordDto): Promise<void> {
    await this.account.forgotPassword(dto.email);
  }

  @Throttle(AUTH_LIMIT)
  @HttpCode(204)
  @Post('reset-password')
  async reset(@Body() dto: ResetPasswordDto): Promise<void> {
    await this.account.resetPassword(dto.token, dto.next);
  }

  @Throttle(AUTH_LIMIT)
  @HttpCode(204)
  @Post('verify-email')
  async verifyEmail(@Body() dto: VerifyEmailDto): Promise<void> {
    await this.account.verifyEmail(dto.token);
  }

  @Throttle(AUTH_LIMIT)
  @UseGuards(AuthGuard)
  @HttpCode(204)
  @Post('resend-verification')
  async resendVerification(@CurrentUser() user: AuthUser): Promise<void> {
    await this.account.sendVerification(user.id);
  }
}

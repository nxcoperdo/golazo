import { Controller, Get, Logger, UseGuards } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AuthGuard, Roles } from '../auth/auth.guard.js';
import { parseAccounts, type Account } from './accounts.js';

/**
 * Datos de la plataforma que la app necesita mostrar. Las cuentas donde los dueños
 * pagan la mensualidad vienen de PLATFORM_PAYMENT_ACCOUNTS (JSON), no del código.
 * Ejemplo: PLATFORM_PAYMENT_ACCOUNTS='[{"label":"Nequi","account":"300 000 0000","holder":"Golazo S.A.S."}]'
 */
@Controller('config')
export class PlatformController {
  private readonly log = new Logger(PlatformController.name);
  private readonly accounts: Account[];
  private readonly price: number;

  constructor(config: ConfigService) {
    this.price = Number(config.get('SUBSCRIPTION_PRICE') ?? 100_000);
    const raw = config.get<string>('PLATFORM_PAYMENT_ACCOUNTS');
    if (!raw) this.log.warn('PLATFORM_PAYMENT_ACCOUNTS no está definido: los dueños no verán dónde pagar la mensualidad');
    this.accounts = parseAccounts(raw, (why) => this.log.error(`PLATFORM_PAYMENT_ACCOUNTS inválido: ${why}`));
  }

  @UseGuards(AuthGuard)
  @Roles('owner', 'admin')
  @Get('subscription')
  subscription() {
    return { price: this.price, periodDays: 30, accounts: this.accounts };
  }
}

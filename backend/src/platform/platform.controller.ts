import { Controller, Get, Logger, UseGuards } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AuthGuard, Roles } from '../auth/auth.guard.js';

interface Account {
  label: string;
  account: string;
  holder: string;
}

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
    this.accounts = this.parse(config.get<string>('PLATFORM_PAYMENT_ACCOUNTS'));
  }

  private parse(raw: string | undefined): Account[] {
    if (!raw) {
      this.log.warn('PLATFORM_PAYMENT_ACCOUNTS no está definido: los dueños no verán dónde pagar la mensualidad');
      return [];
    }
    try {
      const v = JSON.parse(raw) as unknown;
      if (!Array.isArray(v)) throw new Error('no es una lista');
      return v
        .filter((a): a is Account => !!a && typeof a.label === 'string' && typeof a.account === 'string' && typeof a.holder === 'string')
        .slice(0, 5);
    } catch (e) {
      this.log.error(`PLATFORM_PAYMENT_ACCOUNTS inválido: ${(e as Error).message}`);
      return [];
    }
  }

  @UseGuards(AuthGuard)
  @Roles('owner', 'admin')
  @Get('subscription')
  subscription() {
    return { price: this.price, periodDays: 30, accounts: this.accounts };
  }
}

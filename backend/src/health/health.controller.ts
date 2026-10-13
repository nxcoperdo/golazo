import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import { Db } from '../db/db.service.js';

@Controller('health')
export class HealthController {
  constructor(private readonly db: Db) {}

  /** Para el monitor del VPS y el healthcheck de Docker. */
  @SkipThrottle()
  @Get()
  async check(): Promise<{ status: 'ok' }> {
    try {
      await this.db.query('SELECT 1');
    } catch {
      throw new ServiceUnavailableException({ code: 'DB_DOWN', message: 'Base de datos no disponible' });
    }
    return { status: 'ok' };
  }
}

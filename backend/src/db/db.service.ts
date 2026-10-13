import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import pg from 'pg';

/** Acceso a PostgreSQL con SQL directo (el esquema usa PostGIS y restricciones EXCLUDE). */
@Injectable()
export class Db implements OnModuleDestroy {
  private readonly pool: pg.Pool;

  constructor(config: ConfigService) {
    this.pool = new pg.Pool({
      connectionString: config.getOrThrow<string>('DATABASE_URL'),
      max: 10,
    });
  }

  query<T extends pg.QueryResultRow = pg.QueryResultRow>(
    text: string,
    params: unknown[] = [],
  ): Promise<pg.QueryResult<T>> {
    return this.pool.query<T>(text, params);
  }

  /** Ejecuta [fn] en una transacción; revierte si lanza. */
  async tx<T>(fn: (client: pg.PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await fn(client);
      await client.query('COMMIT');
      return result;
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  }

  onModuleDestroy(): Promise<void> {
    return this.pool.end();
  }
}

/** Código de PostgreSQL para violación de unicidad. */
export const UNIQUE_VIOLATION = '23505';
/** Código de PostgreSQL para violación de restricción EXCLUDE (hora ya ocupada). */
export const EXCLUSION_VIOLATION = '23P01';

export function pgCode(e: unknown): string | undefined {
  return typeof e === 'object' && e !== null && 'code' in e
    ? String((e as { code: unknown }).code)
    : undefined;
}

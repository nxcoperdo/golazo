import { Type } from 'class-transformer';
import { IsDateString, IsIn, IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';
import { COURT_TYPES } from '../courts/courts.dto.js';
import { MAX_HOURS } from './booking-policy.js';

export class CreateBookingDto {
  @IsUUID() courtId!: string;
  /** Inicio del bloque, ISO 8601 con zona (p. ej. 2026-10-20T15:00:00Z). */
  @IsDateString({ strict: true }) startAt!: string;
  @IsInt() @Min(1) @Max(MAX_HOURS) hours!: number;
  /** Tipo de cancha (5, 7, 11...). Si falta se usa el más barato (apps antiguas). */
  @IsOptional() @Type(() => Number) @IsIn(COURT_TYPES) courtType?: number;
}

import { IsDateString, IsInt, IsUUID, Max, Min } from 'class-validator';
import { MAX_HOURS } from './booking-policy.js';

export class CreateBookingDto {
  @IsUUID() courtId!: string;
  /** Inicio del bloque, ISO 8601 con zona (p. ej. 2026-10-20T15:00:00Z). */
  @IsDateString({ strict: true }) startAt!: string;
  @IsInt() @Min(1) @Max(MAX_HOURS) hours!: number;
}

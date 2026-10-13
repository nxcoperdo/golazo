/**
 * Reglas de reserva (fuente de verdad en el servidor; la app Flutter tiene una
 * copia solo para mostrar avisos). Funciones puras: reciben la hora actual.
 *
 * - Última hora: menos de 8 h para el inicio -> anticipo obligatorio del 30 %
 *   y sin cancelación.
 * - Cancelación gratis: solo con 24 h o más de anticipación.
 * - Las reglas se miden desde el inicio del bloque.
 */
export const LAST_MINUTE_MS = 8 * 3600_000;
export const FREE_CANCEL_MS = 24 * 3600_000;
export const LAST_MINUTE_DEPOSIT_PERCENT = 30;
export const MAX_HOURS = 4;

export function isLastMinute(start: Date, now: Date): boolean {
  return start.getTime() - now.getTime() < LAST_MINUTE_MS;
}

export function canCancelFree(start: Date, now: Date): boolean {
  return !isLastMinute(start, now) && start.getTime() - now.getTime() >= FREE_CANCEL_MS;
}

export interface DepositInput {
  total: number;
  courtRequiresDeposit: boolean;
  courtDepositPercent: number;
  start: Date;
  now: Date;
}

/** Anticipo en COP (0 si no se exige). */
export function depositFor(i: DepositInput): number {
  if (isLastMinute(i.start, i.now)) {
    return Math.round((i.total * LAST_MINUTE_DEPOSIT_PERCENT) / 100);
  }
  return i.courtRequiresDeposit ? Math.round((i.total * i.courtDepositPercent) / 100) : 0;
}

export interface SlotCheck {
  start: Date;
  hours: number;
  now: Date;
  openHour: number;
  closeHour: number;
  /** Hora local de Colombia (0-23) de [start]. */
  startHourLocal: number;
}

/** Devuelve el motivo si el bloque no es válido, o null si lo es. */
export function validateSlot(s: SlotCheck): string | null {
  if (!Number.isInteger(s.hours) || s.hours < 1 || s.hours > MAX_HOURS) {
    return `Puedes reservar entre 1 y ${MAX_HOURS} horas seguidas`;
  }
  if (s.start.getUTCMinutes() !== 0 || s.start.getUTCSeconds() !== 0 || s.start.getUTCMilliseconds() !== 0) {
    return 'La reserva debe empezar en punto';
  }
  if (s.start.getTime() <= s.now.getTime()) return 'La hora ya pasó';
  if (s.startHourLocal < s.openHour || s.startHourLocal + s.hours > s.closeHour) {
    return 'El bloque queda fuera del horario de la cancha';
  }
  return null;
}

/** Hora local de Colombia (UTC-5, sin horario de verano) de una fecha. */
export function colombiaHour(d: Date): number {
  return (d.getUTCHours() + 24 - 5) % 24;
}

import { colombiaHour } from '../bookings/booking-policy.js';

/** Hora de Colombia en formato 12 h con AM/PM, p. ej. "3:00 PM" o "12:30 AM". */
export function hourLabelCo(d: Date): string {
  const h = colombiaHour(d);
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(d.getUTCMinutes()).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

/** Fecha de hoy en Colombia como YYYY-MM-DD. */
export function todayCo(now: Date = new Date()): string {
  return new Date(now.getTime() - 5 * 3600_000).toISOString().slice(0, 10);
}

/** Fecha corta de Colombia "DD/MM" de un instante. */
export function dateLabelCo(d: Date): string {
  const iso = new Date(d.getTime() - 5 * 3600_000).toISOString();
  return `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;
}

/** Pesos colombianos para textos de avisos: $ 50.000. */
export const COP = new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 });

/** Colombia es UTC-5 todo el año (sin horario de verano). */
const HOUR_MS = 3600_000;

/**
 * Rango UTC del día calendario [date] (YYYY-MM-DD) en hora de Colombia.
 * Devuelve null si la fecha no existe (p. ej. 2026-02-30).
 */
export function dayRangeUtc(date: string): { from: Date; to: Date } | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const probe = new Date(Date.UTC(y, mo - 1, d));
  if (probe.getUTCFullYear() !== y || probe.getUTCMonth() !== mo - 1 || probe.getUTCDate() !== d) return null;
  const from = new Date(`${date}T00:00:00-05:00`);
  return { from, to: new Date(from.getTime() + 24 * HOUR_MS) };
}

export interface Interval {
  startAt: Date;
  endAt: Date;
}

export interface HourSlot {
  hour: number;
  free: boolean;
}

/**
 * Horas de la cancha en ese día, libres u ocupadas. Una hora no está libre si
 * se cruza con una reserva viva o si ya empezó.
 */
export function hourSlots(opts: {
  openHour: number;
  closeHour: number;
  dayStart: Date;
  bookings: Interval[];
  now: Date;
}): HourSlot[] {
  const slots: HourSlot[] = [];
  for (let hour = opts.openHour; hour < opts.closeHour; hour++) {
    const start = opts.dayStart.getTime() + hour * HOUR_MS;
    const end = start + HOUR_MS;
    const taken = opts.bookings.some((b) => b.startAt.getTime() < end && b.endAt.getTime() > start);
    slots.push({ hour, free: !taken && start > opts.now.getTime() });
  }
  return slots;
}

import { describe, expect, it } from 'vitest';
import { dayRangeUtc, hourSlots } from './availability.js';

describe('dayRangeUtc', () => {
  it('el día de Colombia empieza a las 05:00 UTC', () => {
    const r = dayRangeUtc('2026-10-14')!;
    expect(r.from.toISOString()).toBe('2026-10-14T05:00:00.000Z');
    expect(r.to.toISOString()).toBe('2026-10-15T05:00:00.000Z');
  });
  it('rechaza fechas inválidas', () => {
    expect(dayRangeUtc('2026-02-30')).toBeNull();
    expect(dayRangeUtc('14/10/2026')).toBeNull();
    expect(dayRangeUtc('hoy')).toBeNull();
  });
});

describe('hourSlots', () => {
  const dayStart = new Date('2026-10-14T05:00:00Z'); // 00:00 en Colombia
  const farBefore = new Date('2026-10-01T00:00:00Z');
  const at = (h: number) => new Date(dayStart.getTime() + h * 3600_000);
  const free = (s: { hour: number; free: boolean }[]) => s.filter((x) => x.free).map((x) => x.hour);

  it('sin reservas todo el horario está libre', () => {
    expect(free(hourSlots({ openHour: 8, closeHour: 12, dayStart, bookings: [], now: farBefore }))).toEqual([8, 9, 10, 11]);
  });

  it('una reserva de varias horas bloquea todas sus horas', () => {
    const s = hourSlots({ openHour: 8, closeHour: 14, dayStart, bookings: [{ startAt: at(10), endAt: at(12) }], now: farBefore });
    expect(free(s)).toEqual([8, 9, 12, 13]);
  });

  it('una reserva contigua no bloquea la hora siguiente', () => {
    const s = hourSlots({ openHour: 8, closeHour: 12, dayStart, bookings: [{ startAt: at(8), endAt: at(9) }], now: farBefore });
    expect(free(s)).toEqual([9, 10, 11]);
  });

  it('las horas que ya empezaron no están libres', () => {
    // Ahora son las 10:30 en Colombia: la hora de las 10 ya empezó.
    const s = hourSlots({ openHour: 8, closeHour: 13, dayStart, bookings: [], now: new Date(at(10).getTime() + 30 * 60_000) });
    expect(free(s)).toEqual([11, 12]);
  });
});

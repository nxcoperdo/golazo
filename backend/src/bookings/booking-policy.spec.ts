import { describe, expect, it } from 'vitest';
import { canCancelFree, colombiaHour, depositFor, isLastMinute, validateSlot } from './booking-policy.js';

const now = new Date('2026-10-13T17:00:00Z'); // 12:00 p. m. en Colombia
const plus = (h: number) => new Date(now.getTime() + h * 3600_000);

describe('BookingPolicy', () => {
  it('última hora: menos de 8 h exige 30 % y no es cancelable', () => {
    const start = plus(5);
    expect(isLastMinute(start, now)).toBe(true);
    expect(canCancelFree(start, now)).toBe(false);
    expect(depositFor({ total: 100000, courtRequiresDeposit: false, courtDepositPercent: 50, start, now })).toBe(30000);
  });

  it('exactamente 8 h ya no es última hora', () => {
    expect(isLastMinute(plus(8), now)).toBe(false);
  });

  it('cancelación gratis desde 24 h', () => {
    expect(canCancelFree(plus(24), now)).toBe(true);
    expect(canCancelFree(plus(23.99), now)).toBe(false);
    expect(canCancelFree(plus(12), now)).toBe(false);
  });

  it('anticipo configurable por cancha', () => {
    const start = plus(48);
    expect(depositFor({ total: 100000, courtRequiresDeposit: true, courtDepositPercent: 40, start, now })).toBe(40000);
    expect(depositFor({ total: 100000, courtRequiresDeposit: false, courtDepositPercent: 40, start, now })).toBe(0);
  });

  it('el anticipo se calcula sobre el total del bloque', () => {
    expect(depositFor({ total: 270000, courtRequiresDeposit: true, courtDepositPercent: 30, start: plus(48), now })).toBe(81000);
  });
});

describe('validateSlot', () => {
  const base = { hours: 2, now, openHour: 8, closeHour: 23, startHourLocal: 18, start: new Date('2026-10-14T23:00:00Z') };

  it('acepta un bloque válido', () => {
    expect(validateSlot(base)).toBeNull();
  });
  it('rechaza más de 4 horas o menos de 1', () => {
    expect(validateSlot({ ...base, hours: 5 })).not.toBeNull();
    expect(validateSlot({ ...base, hours: 0 })).not.toBeNull();
    expect(validateSlot({ ...base, hours: 1.5 })).not.toBeNull();
  });
  it('rechaza horas pasadas', () => {
    expect(validateSlot({ ...base, start: plus(-1) })).not.toBeNull();
  });
  it('rechaza bloques que se pasan del cierre', () => {
    expect(validateSlot({ ...base, startHourLocal: 22, hours: 2 })).not.toBeNull();
    expect(validateSlot({ ...base, startHourLocal: 21, hours: 2 })).toBeNull();
  });
  it('rechaza horas que no empiezan en punto', () => {
    expect(validateSlot({ ...base, start: new Date('2026-10-14T23:30:00Z') })).not.toBeNull();
  });
});

describe('colombiaHour', () => {
  it('convierte UTC a hora de Colombia', () => {
    expect(colombiaHour(new Date('2026-10-13T17:00:00Z'))).toBe(12);
    expect(colombiaHour(new Date('2026-10-13T03:00:00Z'))).toBe(22);
  });
});

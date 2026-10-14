import { describe, expect, it } from 'vitest';
import { hourLabelCo, todayCo } from './time.js';

describe('hourLabelCo', () => {
  it('formato 12 h con AM/PM en hora de Colombia', () => {
    expect(hourLabelCo(new Date('2026-10-13T20:00:00Z'))).toBe('3:00 PM');
    expect(hourLabelCo(new Date('2026-10-13T13:00:00Z'))).toBe('8:00 AM');
  });
  it('medianoche y mediodía', () => {
    expect(hourLabelCo(new Date('2026-10-13T05:00:00Z'))).toBe('12:00 AM');
    expect(hourLabelCo(new Date('2026-10-13T17:00:00Z'))).toBe('12:00 PM');
  });
  it('conserva los minutos', () => {
    expect(hourLabelCo(new Date('2026-10-13T20:30:00Z'))).toBe('3:30 PM');
  });
});

describe('todayCo', () => {
  it('a las 03:00 UTC todavía es el día anterior en Colombia', () => {
    expect(todayCo(new Date('2026-10-14T03:00:00Z'))).toBe('2026-10-13');
    expect(todayCo(new Date('2026-10-14T06:00:00Z'))).toBe('2026-10-14');
  });
});

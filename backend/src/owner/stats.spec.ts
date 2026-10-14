import { describe, expect, it } from 'vitest';
import { occupancyPercent } from './stats.service.js';

describe('occupancyPercent', () => {
  it('calcula el porcentaje sobre las horas disponibles', () => {
    // Cancha abierta 15 h/día, 30 días = 450 h disponibles; 90 h reservadas = 20 %
    expect(occupancyPercent(90, 15, 30)).toBe(20);
  });
  it('redondea a un decimal', () => {
    expect(occupancyPercent(1, 15, 30)).toBe(0.2);
  });
  it('sin canchas o sin días devuelve 0', () => {
    expect(occupancyPercent(10, 0, 30)).toBe(0);
    expect(occupancyPercent(10, 15, 0)).toBe(0);
  });
  it('nunca pasa de 100', () => {
    expect(occupancyPercent(999, 10, 1)).toBe(100);
  });
});

import { describe, expect, it } from 'vitest';
import { cleanBody, isChatOpen, preview } from './chat.rules.js';

describe('isChatOpen', () => {
  it('soporte siempre está abierto', () => {
    expect(isChatOpen({ kind: 'support', hasLiveBooking: false, blocked: false })).toBe(true);
  });

  it('cancha: abierto con reserva vigente', () => {
    expect(isChatOpen({ kind: 'court', hasLiveBooking: true, blocked: false })).toBe(true);
  });

  it('cancha: cerrado cuando no hay reserva vigente (terminó, se canceló o expiró)', () => {
    expect(isChatOpen({ kind: 'court', hasLiveBooking: false, blocked: false })).toBe(false);
  });

  it('cancha: un bloqueo lo cierra aunque haya reserva', () => {
    expect(isChatOpen({ kind: 'court', hasLiveBooking: true, blocked: true })).toBe(false);
  });

  it('el bloqueo no afecta a soporte', () => {
    expect(isChatOpen({ kind: 'support', hasLiveBooking: false, blocked: true })).toBe(true);
  });
});

describe('cleanBody', () => {
  it('recorta espacios y normaliza saltos de línea', () => {
    expect(cleanBody('  hola\r\nqué tal  ')).toBe('hola\nqué tal');
  });

  it('texto vacío o solo espacios -> null', () => {
    expect(cleanBody('   ')).toBeNull();
    expect(cleanBody('')).toBeNull();
    expect(cleanBody(undefined)).toBeNull();
  });
});

describe('preview', () => {
  it('texto corto tal cual', () => {
    expect(preview('Hola', false)).toBe('Hola');
  });

  it('recorta los largos con puntos suspensivos', () => {
    const p = preview('a'.repeat(300), false, 50);
    expect(p).toHaveLength(50);
    expect(p.endsWith('…')).toBe(true);
  });

  it('solo foto', () => {
    expect(preview(null, true)).toBe('📷 Foto');
  });
});

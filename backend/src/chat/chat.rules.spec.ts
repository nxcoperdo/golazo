import { describe, expect, it } from 'vitest';
import { MAX_BODY, cleanBody, isChatOpen, preview, subscriptionReplyBody, subscriptionRequestBody } from './chat.rules.js';

describe('mensajes de mensualidad', () => {
  const acc = { label: 'Nequi', account: '300 123 4567', holder: 'Ana Pérez' };

  it('el mensaje del dueño distingue activar de renovar y puede llevar el correo', () => {
    expect(subscriptionRequestBody('Wembley', true, 'a@b.co')).toBe('Hola, quiero activar mi cancha «Wembley» en Golazo. Mi correo: a@b.co');
    expect(subscriptionRequestBody('Wembley', false)).toBe('Hola, quiero renovar la mensualidad de mi cancha «Wembley» en Golazo.');
  });

  it('la respuesta incluye el valor, las cuentas y pide el comprobante', () => {
    const r = subscriptionReplyBody(100_000, [acc], true);
    expect(r).toContain('activar tu cancha');
    expect(r).toContain('Nequi: 300 123 4567 (Ana Pérez)');
    expect(r).toContain('comprobante');
  });

  it('sin cuentas configuradas avisa que soporte enviará los datos', () => {
    const r = subscriptionReplyBody(100_000, [], false);
    expect(r).toContain('Renovar');
    expect(r).toContain('En un momento te enviamos');
  });

  it('con 5 cuentas largas no pasa del máximo del chat', () => {
    const long = { label: 'Banco'.repeat(6), account: '1'.repeat(40), holder: 'N'.repeat(60) };
    expect(subscriptionReplyBody(100_000, Array(5).fill(long), true).length).toBeLessThanOrEqual(MAX_BODY);
  });
});

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

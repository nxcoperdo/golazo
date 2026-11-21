import { NotFoundException } from '@nestjs/common';
import { describe, expect, it } from 'vitest';
import { LinksController } from './links.controller.js';

const TOKEN = 'abcdefghijklmnopqrstuvwxyz0123456789_-ABCDE';
const ctrl = new LinksController();

describe('LinksController', () => {
  it('reset: muestra el formulario y apunta al login de la app', () => {
    const html = ctrl.open('reset', TOKEN);
    expect(html).toContain('id="p1"');
    expect(html).toContain('id="p2"');
    expect(html).toContain('/v1/auth/reset-password');
    expect(html).toContain('golazo://login');
    expect(html).toContain(JSON.stringify(TOKEN));
  });

  it('verify: confirma el correo al cargar', () => {
    const html = ctrl.open('verify', TOKEN);
    expect(html).toContain('/v1/auth/verify-email');
    expect(html).toContain('Correo confirmado');
  });

  it('rechaza tokens mal formados, vacíos o con intento de inyección', () => {
    for (const t of [undefined, '', 'corto', `${TOKEN}"</script><script>alert(1)</script>`]) {
      expect(() => ctrl.open('reset', t)).toThrow(NotFoundException);
    }
  });

  it('rechaza destinos desconocidos', () => {
    expect(() => ctrl.open('otro', TOKEN)).toThrow(NotFoundException);
  });
});

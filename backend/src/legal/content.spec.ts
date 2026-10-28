import { describe, expect, it } from 'vitest';
import { type LegalData, renderLegal, whatsappLink } from './content.js';

const data: LegalData = {
  name: 'Nicolas Perdomo Rodriguez',
  id: 'C.C. 1141116665',
  email: 'coderepairtech@gmail.com',
  phone: '321 942 9385',
  address: 'Calle 18A # 41B-22',
  city: 'Gigante, Huila',
};

describe('whatsappLink', () => {
  it('arma el enlace con el indicativo 57 a partir de un celular de 10 dígitos', () => {
    expect(whatsappLink('3219429385')).toBe('https://wa.me/573219429385');
  });

  it('ignora espacios, guiones y paréntesis', () => {
    expect(whatsappLink('321 942-9385')).toBe('https://wa.me/573219429385');
    expect(whatsappLink('(321) 942 9385')).toBe('https://wa.me/573219429385');
  });

  it('no duplica el indicativo si ya viene con 57 o +57', () => {
    expect(whatsappLink('573219429385')).toBe('https://wa.me/573219429385');
    expect(whatsappLink('+57 321 942 9385')).toBe('https://wa.me/573219429385');
  });

  it('devuelve null si no parece un celular (marcador sin configurar, fijo, vacío)', () => {
    expect(whatsappLink('[TELÉFONO]')).toBeNull();
    expect(whatsappLink('')).toBeNull();
    expect(whatsappLink('6012345678')).toBeNull();
    expect(whatsappLink('12345')).toBeNull();
  });
});

describe('página de soporte', () => {
  it('muestra el teléfono como enlace a WhatsApp', () => {
    const html = renderLegal('soporte', data);
    expect(html).toContain('href="https://wa.me/573219429385"');
    expect(html).toContain('321 942 9385');
    expect(html).toContain('coderepairtech@gmail.com');
  });

  it('si el teléfono no es válido lo muestra como texto, sin enlace', () => {
    const html = renderLegal('soporte', { ...data, phone: '[TELÉFONO]' });
    expect(html).not.toContain('wa.me');
    expect(html).toContain('[TELÉFONO]');
  });
});

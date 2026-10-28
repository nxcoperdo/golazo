import { Controller, Get, Header, Logger, NotFoundException, Param } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { LEGAL_PAGES, LEGAL_VERSION, type LegalData, type LegalPage, renderLegal } from './content.js';

/**
 * Páginas públicas (sin /v1, sin sesión) que piden las tiendas: términos, privacidad,
 * cómo eliminar la cuenta y soporte. Los datos del responsable vienen de LEGAL_*.
 */
@Controller('legal')
export class LegalController {
  private readonly log = new Logger(LegalController.name);
  private readonly data: LegalData;

  constructor(config: ConfigService) {
    const get = (k: string, fallback: string): string => config.get<string>(k)?.trim() || fallback;
    this.data = {
      name: get('LEGAL_RESPONSIBLE_NAME', '[NOMBRE DEL RESPONSABLE]'),
      id: get('LEGAL_RESPONSIBLE_ID', '[DOCUMENTO]'),
      email: get('LEGAL_CONTACT_EMAIL', '[CORREO DE CONTACTO]'),
      phone: get('LEGAL_PHONE', '[TELÉFONO]'),
      address: get('LEGAL_ADDRESS', '[DIRECCIÓN]'),
      city: get('LEGAL_CITY', '[CIUDAD]'),
    };
    if (!config.get('LEGAL_RESPONSIBLE_NAME') || !config.get('LEGAL_CONTACT_EMAIL')) {
      this.log.warn('LEGAL_* sin definir: las páginas /legal muestran marcadores [ENTRE CORCHETES]');
    }
  }

  @Get('version')
  version() {
    return { version: LEGAL_VERSION, contactEmail: this.data.email };
  }

  @Header('Content-Type', 'text/html; charset=utf-8')
  @Header('Cache-Control', 'public, max-age=300')
  @Get(':page')
  page(@Param('page') page: string): string {
    if (!(LEGAL_PAGES as string[]).includes(page)) {
      throw new NotFoundException({ code: 'NOT_FOUND', message: 'Página no encontrada' });
    }
    return renderLegal(page as LegalPage, this.data);
  }
}

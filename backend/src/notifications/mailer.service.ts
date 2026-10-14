import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import nodemailer, { type Transporter } from 'nodemailer';

/**
 * Envío de correo por SMTP. Si SMTP_URL no está definido (desarrollo), el
 * mensaje solo se escribe en el log del servidor.
 * Ejemplo: SMTP_URL=smtps://usuario:clave@smtp.proveedor.com:465  MAIL_FROM="Golazo <no-reply@tudominio.com>"
 */
@Injectable()
export class MailerService {
  private readonly log = new Logger(MailerService.name);
  private readonly transport: Transporter | null;
  private readonly from: string;

  constructor(config: ConfigService) {
    const url = config.get<string>('SMTP_URL');
    this.transport = url ? nodemailer.createTransport(url) : null;
    this.from = config.get<string>('MAIL_FROM') ?? 'Golazo <no-reply@golazo.local>';
  }

  get enabled(): boolean {
    return this.transport !== null;
  }

  /** Nunca lanza: un fallo de correo no debe romper la operación que lo originó. */
  async send(to: string, subject: string, text: string): Promise<void> {
    if (!this.transport) {
      this.log.log(`[correo no configurado] Para: ${to} | Asunto: ${subject}\n${text}`);
      return;
    }
    try {
      await this.transport.sendMail({ from: this.from, to, subject, text });
    } catch (e) {
      this.log.error(`No se pudo enviar correo a ${to}: ${(e as Error).message}`);
    }
  }
}

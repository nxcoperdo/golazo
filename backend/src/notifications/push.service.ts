import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { GoogleAuth } from 'google-auth-library';
import { Db } from '../db/db.service.js';

/**
 * Push por FCM (HTTP v1) usando solo una cuenta de servicio: no se usa ningún
 * otro servicio de Firebase. Se activa con FCM_SERVICE_ACCOUNT_FILE=/ruta/cuenta.json
 * (el JSON contiene el project_id). Sin esa variable, el push se omite y la
 * notificación queda igual en la bandeja de la app.
 *
 * Pendiente: APNs directo para iOS (hoy los tokens iOS también pasarían por FCM).
 */
@Injectable()
export class PushService {
  private readonly log = new Logger(PushService.name);
  private readonly auth: GoogleAuth | null;
  private projectId: string | null = null;

  constructor(
    config: ConfigService,
    private readonly db: Db,
  ) {
    const file = config.get<string>('FCM_SERVICE_ACCOUNT_FILE');
    this.auth = file
      ? new GoogleAuth({ keyFile: file, scopes: ['https://www.googleapis.com/auth/firebase.messaging'] })
      : null;
  }

  async send(userId: string, title: string, body: string, data: Record<string, string> = {}): Promise<void> {
    if (!this.auth) return;
    const { rows } = await this.db.query<{ token: string }>('SELECT token FROM device_tokens WHERE user_id = $1', [userId]);
    if (rows.length === 0) return;

    this.projectId ??= await this.auth.getProjectId();
    const accessToken = await this.auth.getAccessToken();
    for (const { token } of rows) {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${this.projectId}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: { token, notification: { title, body }, data } }),
      });
      if (res.status === 404 || res.status === 400) {
        // Token inválido o app desinstalada: se descarta para no reintentar.
        const err = await res.text();
        if (err.includes('UNREGISTERED') || err.includes('INVALID_ARGUMENT')) {
          await this.db.query('DELETE FROM device_tokens WHERE token = $1', [token]);
        }
      } else if (!res.ok) {
        this.log.warn(`FCM respondió ${res.status} para un token de ${userId}`);
      }
    }
  }
}

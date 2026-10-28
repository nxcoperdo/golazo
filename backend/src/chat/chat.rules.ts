/** Estados de reserva que mantienen abierto el chat con el dueño (la hora sigue retenida). */
export const LIVE_BOOKING_STATUSES = ['pending_payment', 'pending_review', 'confirmed', 'rejected'] as const;

/** Meses que se conservan los mensajes antes de purgarlos. */
export const CHAT_RETENTION_MONTHS = 12;

export const MAX_BODY = 1000;

export interface OpenInput {
  kind: 'court' | 'support';
  /** El jugador tiene en esa cancha una reserva viva (no cancelada) que aún no termina. */
  hasLiveBooking: boolean;
  /** Alguno de los dos bloqueó al otro. */
  blocked: boolean;
}

/**
 * ¿Se puede escribir en el hilo? Soporte siempre. Cancha: solo mientras haya una reserva vigente y
 * nadie haya bloqueado a nadie. Al terminar la reserva el hilo queda en solo lectura y vuelve a
 * abrirse cuando el jugador reserve otra vez en esa cancha.
 */
export function isChatOpen({ kind, hasLiveBooking, blocked }: OpenInput): boolean {
  if (kind === 'support') return true;
  return hasLiveBooking && !blocked;
}

/** Texto limpio o null si queda vacío. */
export function cleanBody(raw: string | undefined | null): string | null {
  const t = (raw ?? '').replace(/\r\n/g, '\n').trim();
  return t.length === 0 ? null : t;
}

/** Vista previa para notificaciones push y listas. */
export function preview(body: string | null, hasImage: boolean, max = 120): string {
  if (body) return body.length > max ? `${body.slice(0, max - 1)}…` : body;
  return hasImage ? '📷 Foto' : '';
}

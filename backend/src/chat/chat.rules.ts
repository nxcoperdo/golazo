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

/** Mensaje que "escribe" el dueño al tocar «Chatear con soporte» en su cancha. */
export function subscriptionRequestBody(courtName: string, pending: boolean, email?: string | null): string {
  const action = pending ? 'activar mi cancha' : 'renovar la mensualidad de mi cancha';
  return `Hola, quiero ${action} «${courtName}» en Golazo.${email ? ` Mi correo: ${email}` : ''}`;
}

const money = (n: number) => `$${Math.round(n).toLocaleString('es-CO')}`;

/** Respuesta automática de soporte: valor, cuentas y cómo mandar el comprobante. */
export function subscriptionReplyBody(
  price: number,
  accounts: { label: string; account: string; holder: string }[],
  pending: boolean,
): string {
  const head = pending
    ? `¡Hola! Para activar tu cancha la mensualidad cuesta ${money(price)} por 30 días.`
    : `¡Hola! Renovar la mensualidad cuesta ${money(price)} por 30 días.`;
  if (accounts.length === 0) {
    return `${head}\n\nEn un momento te enviamos por aquí los datos para pagar. Cuando pagues, adjunta la foto del comprobante en este chat.`;
  }
  const lines = accounts.map((a) => `• ${a.label}: ${a.account} (${a.holder})`).join('\n');
  const tail = '\n\nCuando pagues, adjunta aquí la foto del comprobante. Lo revisamos y activamos tu cancha.';
  const body = `${head}\n\nPuedes pagar a:\n${lines}${tail}`;
  return body.length <= MAX_BODY ? body : `${head}\n\nPuedes pagar a:\n${lines}`.slice(0, MAX_BODY);
}

/** Vista previa para notificaciones push y listas. */
export function preview(body: string | null, hasImage: boolean, max = 120): string {
  if (body) return body.length > max ? `${body.slice(0, max - 1)}…` : body;
  return hasImage ? '📷 Foto' : '';
}

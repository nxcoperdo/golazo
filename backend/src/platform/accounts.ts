export interface Account {
  label: string;
  account: string;
  holder: string;
}

/**
 * Cuentas donde los dueños pagan la mensualidad: PLATFORM_PAYMENT_ACCOUNTS (JSON en una línea).
 * Ejemplo: PLATFORM_PAYMENT_ACCOUNTS='[{"label":"Nequi","account":"300 000 0000","holder":"Golazo S.A.S."}]'
 * Devuelve [] si falta o es inválido; `onError` recibe el motivo cuando es inválido.
 */
export function parseAccounts(raw: string | undefined, onError?: (reason: string) => void): Account[] {
  if (!raw) return [];
  try {
    const v = JSON.parse(raw) as unknown;
    if (!Array.isArray(v)) throw new Error('no es una lista');
    return v
      .filter((a): a is Account => !!a && typeof a.label === 'string' && typeof a.account === 'string' && typeof a.holder === 'string')
      .slice(0, 5);
  } catch (e) {
    onError?.((e as Error).message);
    return [];
  }
}

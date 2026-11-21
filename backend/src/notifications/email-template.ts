/**
 * Plantilla HTML de los correos de Golazo. Usa tablas y estilos en línea porque
 * Gmail/Outlook ignoran casi todo el CSS moderno. Paleta de la app: crema, verde, lima.
 */

const C = { bg: '#F4F5EC', card: '#FFFFFF', green: '#174E32', lime: '#D9FF5B', text: '#1F2A24', muted: '#6B746E', line: '#E3E6DA' };
const FONT = "'Manrope','Segoe UI',Helvetica,Arial,sans-serif";

export const escapeHtml = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

export interface EmailContent {
  /** Título grande dentro de la tarjeta. */
  title: string;
  /** Párrafos de texto plano (se escapan). Una línea en blanco = nuevo párrafo. */
  paragraphs: string[];
  /** Botón principal con enlace https. */
  button?: { label: string; url: string };
  /** Texto pequeño bajo el botón (por ejemplo, vigencia). */
  note?: string;
  /** Texto oculto que algunos clientes muestran junto al asunto. */
  preheader?: string;
}

export interface RenderedEmail {
  html: string;
  text: string;
}

export function renderEmail(c: EmailContent): RenderedEmail {
  const paragraphs = c.paragraphs
    .map((p) => `<p style="margin:0 0 14px;font-size:16px;line-height:1.6;color:${C.text};">${escapeHtml(p).replace(/\n/g, '<br>')}</p>`)
    .join('');

  const button = c.button
    ? `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:22px 0 8px;"><tr><td style="border-radius:999px;background:${C.lime};">
         <a href="${escapeHtml(c.button.url)}" target="_blank" style="display:inline-block;padding:14px 30px;font-family:${FONT};font-size:16px;font-weight:800;color:${C.green};text-decoration:none;border-radius:999px;">${escapeHtml(c.button.label)}</a>
       </td></tr></table>
       <p style="margin:14px 0 0;font-size:12px;line-height:1.5;color:${C.muted};">Si el botón no funciona, copia y pega este enlace en tu navegador:<br>
         <a href="${escapeHtml(c.button.url)}" style="color:${C.green};word-break:break-all;">${escapeHtml(c.button.url)}</a></p>`
    : '';

  const note = c.note ? `<p style="margin:18px 0 0;font-size:13px;line-height:1.5;color:${C.muted};">${escapeHtml(c.note)}</p>` : '';
  const pre = c.preheader
    ? `<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${escapeHtml(c.preheader)}</div>`
    : '';

  const html = `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light"><title>${escapeHtml(c.title)}</title></head>
<body style="margin:0;padding:0;background:${C.bg};font-family:${FONT};">
${pre}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${C.bg};"><tr><td align="center" style="padding:28px 14px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;">
    <tr><td align="center" style="padding:0 0 18px;">
      <span style="display:inline-block;background:${C.green};border-radius:14px;padding:10px 22px;font-family:${FONT};font-size:24px;font-weight:800;letter-spacing:.5px;color:${C.lime};">&#9917; Golazo</span>
    </td></tr>
    <tr><td style="background:${C.card};border:1px solid ${C.line};border-radius:20px;padding:30px 28px;font-family:${FONT};">
      <h1 style="margin:0 0 16px;font-size:24px;line-height:1.25;font-weight:800;color:${C.green};">${escapeHtml(c.title)}</h1>
      ${paragraphs}
      ${button}
      ${note}
    </td></tr>
    <tr><td align="center" style="padding:20px 10px 0;font-family:${FONT};font-size:12px;line-height:1.6;color:${C.muted};">
      Reserva tu cancha sint&eacute;tica en pocos toques.<br>
      Recibes este correo porque tienes una cuenta en Golazo. Si no fuiste t&uacute;, puedes ignorarlo.
    </td></tr>
  </table>
</td></tr></table>
</body></html>`;

  const text = [
    c.title,
    '',
    ...c.paragraphs,
    ...(c.button ? ['', `${c.button.label}: ${c.button.url}`] : []),
    ...(c.note ? ['', c.note] : []),
    '',
    '— Golazo',
  ].join('\n');

  return { html, text };
}

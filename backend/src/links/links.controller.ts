import { Controller, Get, Header, NotFoundException, Param, Query } from '@nestjs/common';
import { escapeHtml } from '../notifications/email-template.js';

const TARGETS = {
  reset: {
    scheme: 'golazo://reset-password',
    title: 'Crea tu contraseña nueva',
    help: 'Toca el botón para abrir Golazo. Si la app no se abre, pega este código en la pantalla "Recuperar contraseña".',
    button: 'Abrir Golazo',
  },
  verify: {
    scheme: 'golazo://verify-email',
    title: 'Confirma tu correo',
    help: 'Toca el botón para abrir Golazo y terminar la confirmación.',
    button: 'Abrir Golazo',
  },
} as const;

type Target = keyof typeof TARGETS;
const TOKEN_RE = /^[A-Za-z0-9_-]{20,100}$/;

/**
 * Puente https → app. Los clientes de correo no hacen clicables los enlaces golazo://,
 * así que el correo apunta aquí y esta página redirige a la app (y muestra el código
 * por si el teléfono no tiene la app instalada o el navegador bloquea el salto).
 */
@Controller('open')
export class LinksController {
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Header('Cache-Control', 'no-store')
  @Header('Referrer-Policy', 'no-referrer')
  @Get(':target')
  open(@Param('target') target: string, @Query('token') token?: string): string {
    if (!(target in TARGETS)) throw new NotFoundException({ code: 'NOT_FOUND', message: 'Página no encontrada' });
    if (!token || !TOKEN_RE.test(token)) {
      throw new NotFoundException({ code: 'NOT_FOUND', message: 'Enlace no válido' });
    }
    const t = TARGETS[target as Target];
    const deep = `${t.scheme}?token=${token}`;
    const showCode = target === 'reset';
    return `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Golazo</title>
<style>
body{margin:0;background:#F4F5EC;font-family:'Manrope','Segoe UI',Helvetica,Arial,sans-serif;color:#1F2A24}
main{max-width:440px;margin:0 auto;padding:36px 18px;text-align:center}
.logo{display:inline-block;background:#174E32;color:#D9FF5B;font-weight:800;font-size:24px;padding:10px 22px;border-radius:14px}
.card{background:#fff;border:1px solid #E3E6DA;border-radius:20px;padding:28px 22px;margin-top:20px}
h1{color:#174E32;font-size:22px;margin:0 0 12px}p{line-height:1.6;margin:0 0 16px}
a.btn{display:inline-block;background:#D9FF5B;color:#174E32;font-weight:800;text-decoration:none;padding:14px 30px;border-radius:999px}
code{display:block;word-break:break-all;background:#F4F5EC;border-radius:10px;padding:12px;font-size:13px;user-select:all}
small{color:#6B746E}
</style></head><body><main>
<span class="logo">&#9917; Golazo</span>
<div class="card">
<h1>${escapeHtml(t.title)}</h1>
<p>${escapeHtml(t.help)}</p>
<p><a class="btn" href="${escapeHtml(deep)}">${escapeHtml(t.button)}</a></p>
${showCode ? `<p><small>Tu código:</small></p><code>${escapeHtml(token)}</code>` : ''}
</div>
</main>
<script>setTimeout(function(){location.href=${JSON.stringify(deep)}},300)</script>
</body></html>`;
  }
}

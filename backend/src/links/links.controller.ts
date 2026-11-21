import { Controller, Get, Header, NotFoundException, Param, Query } from '@nestjs/common';

const TOKEN_RE = /^[A-Za-z0-9_-]{20,100}$/;
const APP_LOGIN = 'golazo://login';

const STYLE = `
body{margin:0;background:#F4F5EC;font-family:'Manrope','Segoe UI',Helvetica,Arial,sans-serif;color:#1F2A24}
main{max-width:440px;margin:0 auto;padding:32px 18px;text-align:center}
.logo{display:inline-block;background:#174E32;color:#D9FF5B;font-weight:800;font-size:24px;padding:10px 22px;border-radius:14px}
.card{background:#fff;border:1px solid #E3E6DA;border-radius:20px;padding:28px 22px;margin-top:20px;text-align:left}
h1{color:#174E32;font-size:22px;margin:0 0 12px;text-align:center}
p{line-height:1.6;margin:0 0 16px}
.center{text-align:center}
label{display:block;font-size:14px;font-weight:700;margin:0 0 6px}
.field{position:relative;margin:0 0 16px}
input{width:100%;box-sizing:border-box;padding:13px 14px;border:1.5px solid #D5D9CB;border-radius:12px;font:inherit;font-size:16px;background:#FBFBF7}
input:focus{outline:none;border-color:#174E32}
button,a.btn{display:block;width:100%;box-sizing:border-box;text-align:center;background:#D9FF5B;color:#174E32;font:inherit;font-weight:800;font-size:16px;text-decoration:none;padding:14px 20px;border:0;border-radius:999px;cursor:pointer}
button[disabled]{opacity:.6;cursor:default}
.link{display:block;text-align:center;margin-top:14px;font-size:13px;color:#174E32}
.err{color:#B3261E;font-size:14px;min-height:20px;margin:0 0 12px}
.ok{font-size:44px;text-align:center;margin:0 0 6px}
.show{background:none;border:0;width:auto;position:absolute;right:6px;top:6px;padding:8px 10px;font-size:13px;color:#174E32;font-weight:700}
small{color:#6B746E}
`;

const page = (body: string, script = ''): string => `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Golazo</title><style>${STYLE}</style></head>
<body><main><span class="logo">&#9917; Golazo</span>${body}</main>${script ? `<script>${script}</script>` : ''}</body></html>`;

const invalid = `<div class="card center"><div class="ok">&#9888;&#65039;</div><h1>Enlace no v&aacute;lido</h1>
<p>El enlace venci&oacute; o ya se us&oacute;. Pide uno nuevo desde la app, en &laquo;Olvid&eacute; mi contrase&ntilde;a&raquo;.</p>
<a class="btn" href="${APP_LOGIN}">Abrir Golazo</a></div>`;

/**
 * Páginas públicas que abren los enlaces de los correos (https, clicables en cualquier cliente).
 * /open/reset: formulario para crear la contraseña nueva. /open/verify: confirma el correo.
 * Ambas llaman a los endpoints existentes del mismo origen y terminan llevando a la app (login).
 */
@Controller('open')
export class LinksController {
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Header('Cache-Control', 'no-store')
  @Header('Referrer-Policy', 'no-referrer')
  @Get(':target')
  open(@Param('target') target: string, @Query('token') token?: string): string {
    if (target !== 'reset' && target !== 'verify') {
      throw new NotFoundException({ code: 'NOT_FOUND', message: 'Página no encontrada' });
    }
    if (!token || !TOKEN_RE.test(token)) {
      throw new NotFoundException({ code: 'NOT_FOUND', message: 'Enlace no válido' });
    }
    return target === 'reset' ? resetPage(token) : verifyPage(token);
  }
}

function resetPage(token: string): string {
  const body = `
<div class="card" id="form-card">
  <h1>Crea tu contrase&ntilde;a nueva</h1>
  <form id="f" novalidate>
    <label for="p1">Nueva contrase&ntilde;a</label>
    <div class="field"><input id="p1" type="password" autocomplete="new-password" maxlength="128" placeholder="M&iacute;nimo 8 caracteres">
      <button type="button" class="show" id="s1">Ver</button></div>
    <label for="p2">Repite la contrase&ntilde;a</label>
    <div class="field"><input id="p2" type="password" autocomplete="new-password" maxlength="128"></div>
    <p class="err" id="err" role="alert"></p>
    <button type="submit" id="go">Cambiar contrase&ntilde;a</button>
  </form>
</div>
<div class="card center" id="done" hidden>
  <div class="ok">&#9989;</div><h1>&iexcl;Contrase&ntilde;a cambiada!</h1>
  <p>Ya puedes iniciar sesi&oacute;n en Golazo con tu contrase&ntilde;a nueva.</p>
  <a class="btn" href="${APP_LOGIN}">Ir a iniciar sesi&oacute;n</a>
  <small class="link">Si no tienes la app instalada, abre Golazo desde tu celular.</small>
</div>
<div id="bad" hidden>${invalid}</div>`;
  const script = `
var TOKEN=${JSON.stringify(token)},LOGIN=${JSON.stringify(APP_LOGIN)};
var $=function(i){return document.getElementById(i)};
$('s1').onclick=function(){var t=$('p1').type==='password';$('p1').type=$('p2').type=t?'text':'password';this.textContent=t?'Ocultar':'Ver'};
$('f').onsubmit=function(e){
  e.preventDefault();
  var a=$('p1').value,b=$('p2').value,err=$('err');err.textContent='';
  if(a.length<8){err.textContent='La contraseña debe tener al menos 8 caracteres.';return}
  if(a!==b){err.textContent='Las contraseñas no coinciden.';return}
  $('go').disabled=true;$('go').textContent='Guardando...';
  fetch('/v1/auth/reset-password',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:TOKEN,next:a})})
  .then(function(r){
    if(r.ok){$('form-card').hidden=true;$('done').hidden=false;setTimeout(function(){location.href=LOGIN},1500);return}
    return r.json().catch(function(){return {}}).then(function(j){
      if(j.code==='BAD_RESET_TOKEN'){$('form-card').hidden=true;$('bad').hidden=false;return}
      err.textContent=r.status===429?'Demasiados intentos. Espera un minuto e inténtalo de nuevo.':'No se pudo cambiar la contraseña. Inténtalo de nuevo.';
      $('go').disabled=false;$('go').textContent='Cambiar contraseña';
    });
  }).catch(function(){err.textContent='Sin conexión. Revisa tu internet e inténtalo de nuevo.';$('go').disabled=false;$('go').textContent='Cambiar contraseña'});
};`;
  return page(body, script);
}

function verifyPage(token: string): string {
  const body = `
<div class="card center" id="wait"><h1>Confirmando tu correo...</h1><p>Un momento.</p></div>
<div class="card center" id="done" hidden>
  <div class="ok">&#9989;</div><h1>&iexcl;Correo confirmado!</h1>
  <p>Tu cuenta de Golazo ya est&aacute; lista para reservar canchas.</p>
  <a class="btn" href="${APP_LOGIN}">Abrir Golazo</a>
</div>
<div id="bad" hidden>${invalid}</div>`;
  const script = `
var $=function(i){return document.getElementById(i)};
fetch('/v1/auth/verify-email',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token:${JSON.stringify(token)}})})
.then(function(r){$('wait').hidden=true;(r.ok?$('done'):$('bad')).hidden=false})
.catch(function(){$('wait').innerHTML='<h1>Sin conexión</h1><p>Revisa tu internet y vuelve a abrir el enlace.</p>'});`;
  return page(body, script);
}

/**
 * Textos legales públicos. Son borradores razonables para Colombia (Ley 1581 de 2012,
 * Decreto 1377 de 2013 hoy compilado en el Decreto 1074 de 2015, Ley 1480 de 2011):
 * conviene que un abogado los revise antes de publicar. Los datos del responsable
 * vienen de variables de entorno (LEGAL_*), nunca del repositorio.
 */

/** Sube esta versión cuando cambie el fondo de los textos: la app vuelve a pedir la aceptación. */
export const LEGAL_VERSION = '2026-10-25';

export interface LegalData {
  name: string;
  id: string;
  email: string;
  phone: string;
  address: string;
  city: string;
}

export type LegalPage = 'terminos' | 'privacidad' | 'eliminar-cuenta' | 'soporte';

const esc = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const PAGES: Record<LegalPage, string> = {
  terminos: 'Términos y Condiciones',
  privacidad: 'Política de Tratamiento de Datos Personales',
  'eliminar-cuenta': 'Eliminar mi cuenta',
  soporte: 'Soporte',
};

export const LEGAL_PAGES = Object.keys(PAGES) as LegalPage[];

function responsible(d: LegalData): string {
  const lines = [
    `<strong>${esc(d.name)}</strong>, identificado(a) con documento ${esc(d.id)}, persona natural`,
    `domicilio: ${esc(d.address)}, ${esc(d.city)}, Colombia`,
    `correo: <a href="mailto:${esc(d.email)}">${esc(d.email)}</a>`,
    `teléfono: ${esc(d.phone)}`,
  ];
  return lines.join('; ') + '.';
}

function terms(d: LegalData): string {
  return `
<p>Estos Términos y Condiciones regulan el uso de la aplicación Golazo (la «App»), una plataforma para encontrar y reservar canchas sintéticas de fútbol en Colombia. Al crear una cuenta o usar la App declaras que los leíste y los aceptas.</p>

<h2>1. Quién ofrece la App</h2>
<p>La App es ofrecida por ${responsible(d)}</p>

<h2>2. Qué es Golazo y qué no es</h2>
<p>Golazo es un intermediario tecnológico: conecta a jugadores con dueños de canchas. Golazo <strong>no es dueño ni administra las canchas, no presta el servicio deportivo y no recibe ni procesa tus pagos</strong>. Las transferencias del anticipo o del valor de la reserva se hacen directamente entre el jugador y el dueño de la cancha, fuera de la App, y el dueño confirma el pago al revisar el comprobante.</p>

<h2>3. Requisitos y cuenta</h2>
<ul>
<li>Debes ser mayor de 18 años y capaz de contratar según la ley colombiana.</li>
<li>La información que entregas (nombre, correo, celular) debe ser veraz. El celular es solo un dato de contacto.</li>
<li>Eres responsable de la confidencialidad de tu contraseña y de lo que se haga con tu cuenta.</li>
<li>Puedes ser jugador o dueño de cancha. Los administradores de Golazo no se crean desde la App.</li>
</ul>

<h2>4. Reservas</h2>
<ul>
<li>Una reserva es un bloque continuo de 1 a 4 horas el mismo día, en una cancha disponible.</li>
<li>Algunas reservas exigen un <strong>anticipo</strong> (por ejemplo, las que se hacen con menos de 8 horas de anticipación o las que la cancha configure). Tras reservar con anticipo tienes <strong>30 minutos</strong> para subir el comprobante; si no lo haces, la hora se libera.</li>
<li>La reserva queda confirmada cuando el dueño aprueba el comprobante o, si no hay anticipo, de inmediato. Si el dueño rechaza el comprobante, podrás subir uno nuevo.</li>
<li>Los horarios se muestran en hora de Colombia.</li>
</ul>

<h2>5. Cancelaciones y devoluciones</h2>
<ul>
<li>Puedes cancelar sin costo hasta 24 horas antes de la hora de inicio.</li>
<li>Con menos de 24 horas puede aplicar la política de la cancha. Las reservas hechas con menos de 8 horas de anticipación exigen anticipo del 30 % y no se pueden cancelar.</li>
<li>Las devoluciones de dinero las coordinan directamente el jugador y el dueño, porque Golazo no maneja los pagos.</li>
</ul>

<h2>6. Reseñas y contenido de los usuarios</h2>
<p>Los jugadores pueden calificar y comentar las canchas en las que reservaron. Eres responsable de lo que publicas: no puede ser ofensivo, falso, discriminatorio ni infringir derechos de terceros. Cualquier usuario puede reportar una reseña y Golazo puede ocultarla o eliminarla. Para reportar contenido o conductas escribe al correo de soporte.</p>

<h2>7. Dueños de cancha</h2>
<ul>
<li>Declaras que tienes derecho a ofrecer la cancha y que la información (precio, horarios, fotos, ubicación) es correcta.</li>
<li>Una cancha nueva solo se muestra a los jugadores cuando Golazo la activa. El uso de la plataforma por parte de los dueños tiene una mensualidad cuyo valor y forma de pago se acuerdan <strong>fuera de la App</strong> con Golazo.</li>
<li>Debes honrar las reservas confirmadas y responder por la prestación del servicio al jugador.</li>
</ul>

<h2>8. Conducta y suspensión</h2>
<p>Está prohibido suplantar a otras personas, usar la App con fines ilícitos, intentar vulnerar su seguridad, hacer reservas falsas o subir comprobantes alterados. Golazo puede suspender o eliminar cuentas, canchas o contenido que incumplan estos términos.</p>

<h2>9. Retracto</h2>
<p>De acuerdo con la Ley 1480 de 2011, el derecho de retracto no aplica a los servicios de esparcimiento prestados en una fecha determinada, como el alquiler de una cancha para una hora específica. Aun así, aplican las reglas de cancelación de la sección 5.</p>

<h2>10. Responsabilidad</h2>
<p>Golazo se esfuerza por mantener la App disponible, pero no garantiza que funcione sin interrupciones ni errores. Golazo no responde por la calidad, seguridad o disponibilidad de las canchas, por lesiones o daños ocurridos durante el juego, ni por acuerdos de pago entre usuarios. Nada de lo anterior limita derechos que la ley colombiana te reconoce como consumidor.</p>

<h2>11. Propiedad intelectual</h2>
<p>El nombre, el logo y el diseño de Golazo pertenecen a su responsable. Tú conservas los derechos sobre las fotos y textos que subes y nos autorizas a mostrarlos dentro de la App para prestar el servicio.</p>

<h2>12. Datos personales</h2>
<p>El tratamiento de tus datos se rige por la <a href="/legal/privacidad">Política de Tratamiento de Datos Personales</a>.</p>

<h2>13. Cambios</h2>
<p>Podemos actualizar estos términos. Si el cambio es importante, la App te pedirá aceptarlos de nuevo. Seguir usando la App después de un cambio implica que lo aceptas.</p>

<h2>14. Ley aplicable y contacto</h2>
<p>Estos términos se rigen por las leyes de Colombia y cualquier controversia se someterá a los jueces competentes en ${esc(d.city)}, sin perjuicio de las acciones ante la Superintendencia de Industria y Comercio. Escríbenos a <a href="mailto:${esc(d.email)}">${esc(d.email)}</a>.</p>`;
}

function privacy(d: LegalData): string {
  return `
<p>Esta política explica cómo se tratan tus datos personales en Golazo, en cumplimiento de la Ley 1581 de 2012, el Decreto 1377 de 2013 (compilado en el Decreto 1074 de 2015) y demás normas sobre protección de datos en Colombia.</p>

<h2>1. Responsable del tratamiento</h2>
<p>${responsible(d)}</p>

<h2>2. Datos que recolectamos</h2>
<ul>
<li><strong>Cuenta:</strong> nombre, correo electrónico, celular (como dato de contacto), rol (jugador o dueño) y contraseña (guardada cifrada, nunca en texto plano). Si entras con Google, el nombre y el correo que Google nos comparte.</li>
<li><strong>Uso del servicio:</strong> reservas, pagos reportados, reseñas y reportes, avisos que te enviamos.</li>
<li><strong>Imágenes:</strong> fotos de canchas y comprobantes de pago que subes. Los comprobantes solo los ven quien los subió, el dueño de la cancha y los administradores.</li>
<li><strong>Ubicación aproximada:</strong> solo si lo permites y usas «Cerca de mí», para ordenar canchas por distancia. No la guardamos de forma permanente.</li>
<li><strong>Dispositivo:</strong> un identificador de notificaciones push (token) y datos técnicos básicos como la dirección IP en los registros del servidor.</li>
<li><strong>Consentimiento:</strong> la fecha y la versión de los textos que aceptaste.</li>
</ul>
<p>No recolectamos datos sensibles ni de menores de edad. Golazo no está dirigido a menores de 18 años.</p>

<h2>3. Finalidades</h2>
<ul>
<li>Crear y administrar tu cuenta y autenticarte.</li>
<li>Permitir buscar canchas, reservar y compartir con el dueño tus datos de contacto y el comprobante cuando sea necesario para la reserva.</li>
<li>Enviarte avisos de tus reservas y pagos, por la App, notificaciones push y, cuando esté habilitado, por correo.</li>
<li>Mostrar reseñas, moderar contenido y atender reportes.</li>
<li>Seguridad, prevención de fraude y cumplimiento de obligaciones legales.</li>
<li>Soporte y mejora del servicio.</li>
</ul>

<h2>4. Autorización</h2>
<p>Tratamos tus datos con tu autorización previa, expresa e informada, que otorgas al aceptar esta política al registrarte o la primera vez que la App te lo solicita. Guardamos la fecha y la versión de tu aceptación como prueba.</p>

<h2>5. Tus derechos</h2>
<p>Como titular puedes: conocer, actualizar y rectificar tus datos; solicitar prueba de la autorización; ser informado del uso que se les da; presentar quejas ante la Superintendencia de Industria y Comercio (SIC); revocar la autorización y solicitar la supresión de tus datos cuando no exista un deber legal o contractual de conservarlos; y acceder gratuitamente a tus datos.</p>

<h2>6. Cómo ejercer tus derechos</h2>
<p>Puedes corregir tu nombre y celular desde Perfil y <a href="/legal/eliminar-cuenta">eliminar tu cuenta</a> desde la App. Para cualquier otra consulta o reclamo escribe a <a href="mailto:${esc(d.email)}">${esc(d.email)}</a> indicando tu nombre y el correo de tu cuenta. Responderemos las consultas en máximo 10 días hábiles y los reclamos en máximo 15 días hábiles, prorrogables según la ley.</p>

<h2>7. Terceros que intervienen</h2>
<ul>
<li><strong>Proveedor de hosting (servidor):</strong> donde se almacena la información.</li>
<li><strong>Google Firebase Cloud Messaging:</strong> para entregar notificaciones push a tu celular.</li>
<li><strong>Google (inicio de sesión):</strong> solo si eliges entrar con tu cuenta de Google.</li>
<li><strong>Proveedor de correo electrónico:</strong> para enviar avisos y recuperar tu contraseña, cuando esté habilitado.</li>
</ul>
<p>Algunos de estos proveedores pueden procesar datos fuera de Colombia. No vendemos tus datos ni los usamos para publicidad de terceros. Los dueños de cancha ven tu nombre, celular y comprobante únicamente de tus reservas en sus canchas.</p>

<h2>8. Seguridad</h2>
<p>Usamos conexión cifrada (HTTPS), contraseñas protegidas con algoritmos de hash, control de acceso por rol y copias de seguridad. Ningún sistema es infalible; si ocurre un incidente que afecte tus datos lo gestionaremos conforme a la ley.</p>

<h2>9. Conservación</h2>
<p>Conservamos tus datos mientras tengas cuenta. Si la eliminas, borramos tus datos personales (nombre, correo, celular, tokens y sesiones) y conservamos de forma anónima el historial de reservas, pagos y reseñas que necesitamos por obligaciones contables y de seguridad.</p>

<h2>10. Vigencia y cambios</h2>
<p>Esta política rige desde ${LEGAL_VERSION}. Si cambia de forma importante, te lo informaremos en la App y te pediremos aceptarla de nuevo.</p>`;
}

function deleteAccount(d: LegalData): string {
  return `
<p>Puedes eliminar tu cuenta de Golazo y tus datos personales en cualquier momento.</p>

<h2>Desde la app</h2>
<ol>
<li>Abre Golazo e inicia sesión.</li>
<li>Entra a <strong>Perfil</strong>.</li>
<li>Toca <strong>Borrar mi cuenta</strong> y confirma (si tu cuenta tiene contraseña, te la pediremos).</li>
</ol>

<h2>Por correo</h2>
<p>Si ya no puedes entrar a la app, escribe a <a href="mailto:${esc(d.email)}">${esc(d.email)}</a> desde el correo de tu cuenta pidiendo la eliminación. La atendemos en máximo 15 días hábiles.</p>

<h2>Qué se borra y qué se conserva</h2>
<ul>
<li><strong>Se borra:</strong> tu nombre, correo, celular, contraseña, vínculo con Google, sesiones abiertas y tokens de notificaciones.</li>
<li><strong>Se cancela:</strong> tus reservas futuras y, si eres dueño, tus canchas quedan suspendidas.</li>
<li><strong>Se conserva de forma anónima</strong> (sin que se pueda identificarte): el historial de reservas, pagos y reseñas, por obligaciones contables y para proteger a otros usuarios.</li>
</ul>
<p>La eliminación no se puede deshacer. Consulta también la <a href="/legal/privacidad">Política de Tratamiento de Datos Personales</a>.</p>`;
}

function support(d: LegalData): string {
  return `
<p>¿Tienes una pregunta, un problema con una reserva o quieres reportar una reseña o conducta indebida?</p>
<ul>
<li>Correo: <a href="mailto:${esc(d.email)}">${esc(d.email)}</a></li>
<li>Teléfono / WhatsApp: ${esc(d.phone)}</li>
</ul>
<p>Si eres dueño de cancha y necesitas activar o renovar tu cancha, escríbenos por el mismo medio indicando el nombre de la cancha y el correo de tu cuenta.</p>
<p>Consulta también los <a href="/legal/terminos">Términos y Condiciones</a>, la <a href="/legal/privacidad">Política de privacidad</a> y cómo <a href="/legal/eliminar-cuenta">eliminar tu cuenta</a>.</p>`;
}

const BODIES: Record<LegalPage, (d: LegalData) => string> = {
  terminos: terms,
  privacidad: privacy,
  'eliminar-cuenta': deleteAccount,
  soporte: support,
};

export function renderLegal(page: LegalPage, d: LegalData): string {
  const title = PAGES[page];
  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} · Golazo</title>
<style>
  :root { color-scheme: light; }
  body { margin: 0; background: #F4F5EC; color: #1c2b22; font: 16px/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 760px; margin: 0 auto; padding: 24px 16px 64px; }
  header { border-bottom: 1px solid #d8dccb; margin-bottom: 8px; }
  .brand { color: #174E32; font-weight: 800; font-size: 20px; }
  h1 { font-size: 26px; line-height: 1.25; margin: 8px 0 4px; color: #174E32; }
  h2 { font-size: 18px; margin: 28px 0 6px; color: #174E32; }
  a { color: #174E32; }
  .meta { color: #5d6b61; font-size: 14px; margin: 0 0 16px; }
  nav { margin-top: 40px; font-size: 14px; display: flex; gap: 16px; flex-wrap: wrap; }
</style>
</head>
<body>
<main>
<header><div class="brand">Golazo</div></header>
<h1>${esc(title)}</h1>
<p class="meta">Versión ${LEGAL_VERSION}</p>
${BODIES[page](d)}
<nav>
<a href="/legal/terminos">Términos</a>
<a href="/legal/privacidad">Privacidad</a>
<a href="/legal/eliminar-cuenta">Eliminar cuenta</a>
<a href="/legal/soporte">Soporte</a>
</nav>
</main>
</body>
</html>`;
}

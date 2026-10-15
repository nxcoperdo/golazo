# Golazo — pantallas para los mockups

App móvil (Android / iOS) para reservar canchas sintéticas en Colombia. Un solo app con **tres roles** que ven paneles distintos: **Jugador**, **Dueño de cancha** y **Administrador**. Todo en español, precios en pesos colombianos (`$90.000`), horas en formato 12 h con AM/PM y hora de Colombia.

## Guía visual
- **Marca:** fondo negro (`#040806`), verde neón (logo), blanco. Verde de la app `#1B8A3A`. Logo: arco con balón entrando, cancha y la palabra GOLAZO.
- **Barra inferior "liquid glass":** píldora flotante de cristal esmerilado con una burbuja sobre la pestaña activa. Al mantener presionado, la burbuja crece y se arrastra con el dedo entre pestañas; al soltar se acomoda. El contenido pasa por detrás del cristal.
- Estados que conviene diseñar en cada lista: **cargando**, **vacío**, **error con botón Reintentar** y **tirar para recargar**.
- Banner arriba de los paneles cuando el correo no está confirmado: "Confirma tu correo con el enlace que te enviamos." con botones **Reenviar** y **Ya lo confirmé**.

## Navegación por rol

| Rol | Barra inferior (pestañas) | Atajos |
|---|---|---|
| Jugador | Canchas · Reservas · Avisos · Perfil | — |
| Dueño | Reservas · Pagos · Canchas · Avisos · Perfil | — |
| Admin | Pagos · Canchas · Usuarios · Reseñas · Resumen | Barra superior: campana de avisos (con contador) y perfil |

"Avisos" muestra un contador rojo de no leídos.

---

## 1. Antes de entrar (sin sesión)

### 1.1 Splash
Logo centrado sobre negro y un indicador de carga mientras se recupera la sesión guardada. Si el servidor no responde: mensaje de error con botón **Reintentar**.

### 1.2 Login
- Logo, frase "Reserva tu cancha en segundos".
- Campos: **Correo**, **Contraseña** (con ver/ocultar).
- Botones: **Ingresar**, **Continuar con Google**, **Crear cuenta nueva**; enlace **¿Olvidaste tu contraseña?**
- Errores bajo cada campo (vacío, correo inválido) y mensaje del servidor (credenciales incorrectas, cuenta suspendida, demasiados intentos).

### 1.3 Crear cuenta
- Campos: **Nombre completo**, **Correo**, **Celular de contacto** (10 dígitos, empieza por 3), **Contraseña** (mínimo 8 caracteres).
- Interruptor **Soy dueño de una cancha** (define el rol).
- Botón **Crear cuenta** → entra directo al panel de su rol.

### 1.4 Recuperar contraseña
- Pide el correo y envía un enlace: **Enviar enlace**; confirmación "te enviamos un enlace".
- Opción **Ya tengo el código** (por si el enlace no abre la app) → pantalla de **Nueva contraseña**: campo "Código del enlace", "Contraseña nueva" y **Guardar contraseña**.
- Llega también por enlace profundo `golazo://reset-password?token=…`.

### 1.5 Confirmar correo
Se abre desde el enlace del correo (`golazo://verify-email?token=…`). Muestra **¡Correo confirmado!** y botón **Continuar**; o estado de error si el enlace venció.

---

## 2. Jugador

### 2.1 Canchas (pestaña 1)
Buscador de canchas.
- **Búsqueda** por texto (cancha, barrio o ciudad) y contador "N canchas disponibles".
- **Filtros** (chips deslizables): **Cerca de mí** (GPS), **Todas** y ciudades (vienen del servidor), **Techada**, **Tipo** (Fútbol 5/6/7/8/11), **Hasta $60/80/100 mil**, **Limpiar**.
- **Tarjeta de cancha:** foto con insignias (tipo **Fútbol N**, **Anticipo N %**, **Techada**, distancia si hay GPS), nombre, dirección · ciudad, ★ calificación (reseñas), "Desde $X / hora" y botón **Reservar**.
- Vacío: "No hay canchas con esos filtros".

### 2.2 Detalle de cancha
- **Galería** de fotos deslizable (sin fotos: imagen de relleno), nombre, ★ calificación · N reseñas, dirección y ciudad, descripción, horario (abre/cierra), techada, política de anticipo.
- **Elige el día:** tira de 14 días.
- **Elige la hora:** cuadrícula de horas; se pueden tocar **horas seguidas hasta 4**. Cada hora es un chip que está **libre** (se puede tocar) u **ocupada** (deshabilitada).
- **Resumen:** "N h · Total $X" y "Anticipo a pagar: $Y" (si aplica).
- Si no tiene celular guardado, pide **Tu celular de contacto**.
- Botón **Reservar**.
- Sección **Reseñas** (ver 2.5).

### 2.3 Aviso "Esta reserva requiere anticipo"
Hoja inferior al tocar **Reservar** cuando la cancha exige anticipo o la reserva es de último momento (menos de 8 h: anticipo 30 % y **sin cancelación**). Ícono "!" ámbar, el monto a transferir y su porcentaje, resumen (Reserva N h · Total $X) y la nota "Tendrás 30 minutos para subir el comprobante o las horas se liberarán automáticamente". Botones **Pagar anticipo** y **Cancelar** (no se crea la reserva).

### 2.4 Pagar anticipo
- Encabezado "Paso final · Pagar anticipo" con botón volver.
- **Tarjeta verde oscuro:** Total de la reserva, Anticipo a pagar (en lima), cancha y fecha/hora.
- **Aviso ámbar** con cuenta regresiva real ("Tiempo restante: 29:42"); al acabarse dice "Tu horario fue liberado". Si el comprobante fue **rechazado**, en su lugar sale un aviso rojizo y no hay cuenta regresiva.
- **1. Transfiere el anticipo → Cuenta del dueño:** una tarjeta por cuenta con medio (Nequi, etc.), número grande con botón **Copiar** (pasa a "Copiado"), y titular.
- **2. Sube la captura → Comprobante de pago:** zona punteada para elegir la imagen (cámara o galería); al elegirla muestra el nombre y "Toca para cambiar la imagen".
- **Barra inferior:** **Enviar comprobante** (deshabilitado hasta elegir la imagen) y **Pagar más tarde**.
- **Estado final** (círculo lima con ✓): "Pago en revisión · Comprobante enviado" con tarjeta de la reserva y "Anticipo enviado $X"; también **¡Reserva confirmada!** y **Esta reserva fue cancelada**. Botón **Ver mis reservas**.

### 2.5 Reseñas (dentro del detalle)
- Lista de reseñas con estrellas, autor, comentario y fecha; botón **Reportar**, que abre la hoja inferior "Reportar reseña" con los motivos Lenguaje ofensivo, Información falsa, Contenido no relacionado y Otro motivo (+ Cancelar).
- Diálogo **Califica la cancha:** 5 estrellas + **Comentario (opcional)** + **Publicar** (solo tras una reserva confirmada ya jugada, una vez por reserva).

### 2.6 Mis reservas (pestaña 2)
Dos grupos: **Próximas** y **Anteriores**.
- **Tarjeta de reserva:** cancha, fecha y rango de horas, "Total $X" y anticipo, **estado** con color (pendiente de pago, comprobante en revisión, confirmada, rechazada, cancelada, expirada), insignia "Reserva de último momento (sin cancelación)".
- Acciones: **Pagar anticipo** (si falta), **Cancelar** (confirma con diálogo; gratis con 24 h o más), **Calificar** (si ya se jugó y no se calificó).

### 2.7 Avisos (pestaña 3)
Bandeja de notificaciones: título, texto, día y hora, punto de no leído. Botón **Marcar leídas**. Tipos: reserva confirmada, pago rechazado, recordatorio de reserva (2 h antes), reserva expirada, etc. También llegan como notificación push.

### 2.8 Perfil (pestaña 4) — igual para los tres roles
- Nombre, correo con insignia **Correo confirmado / Correo sin confirmar** (+ **Reenviar**), celular ("Contacto para las reservas").
- **Cambiar nombre**, **Cambiar contraseña** (actual + nueva), **Cerrar sesión**, **Borrar mi cuenta** (pide contraseña y confirma).

---

## 3. Dueño de cancha

### 3.1 Reservas (pestaña 1)
Agenda de las reservas de sus canchas, los próximos 14 días (vacío: "No tienes reservas en los próximos 14 días."). Tocar el celular del jugador lo copia.
- Filtro **Todas las canchas / por cancha**.
- Lista agrupada por día (14 días), cada fila: hora · cancha, nombre y celular del jugador, estado.
- Botón flotante **Bloquear horas**: diálogo con **Cancha**, **Día**, **Desde**, **Cuántas horas**, **Nota (opcional)** — "para reservas que te llegan por fuera de la app". Las horas bloqueadas muestran **Quitar bloqueo**.

### 3.2 Pagos (pestaña 2)
Comprobantes de anticipos de los jugadores. Dos pestañas: **Por revisar** e **Historial**.
- **Tarjeta de pago:** jugador, cancha, fecha de la reserva, monto, miniatura del comprobante (toca para verlo grande).
- Botones **Aprobar** ("¿Aprobar este pago?") y **Rechazar** (pide el motivo; el jugador puede subir otro).

### 3.3 Mis canchas (pestaña 3)
- Lista de sus canchas: foto, nombre, "Ciudad · $X/h", estado (activa, pausada, **suspendida por el admin**, **mensualidad pendiente**: "Paga la mensualidad para que aparezca en el buscador").
- Botón **Estadísticas** (arriba) y botón flotante **Nueva cancha**.

### 3.4 Nueva cancha
Formulario: **Nombre**, **Ciudad**, **Dirección**, **Descripción (opcional)**, **Ubicación** (botón **Usar mi ubicación actual** o **Latitud/Longitud** a mano), **Precio por hora (COP)**, **Abre / Cierra**, interruptor **Cancha techada**, interruptor **Exigir anticipo** con selector de porcentaje. Botón **Crear cancha**.

### 3.5 Administrar cancha
Pantalla con secciones:
- **Fotos:** cuadrícula, agregar y borrar (confirma "¿Borrar esta foto?").
- **Datos de la cancha:** editar los campos del formulario → **Guardar cambios**.
- **Estado:** pausar / reanudar ("¿Ocultar la cancha?"). Si el admin la suspendió, no puede reanudarla.
- **Cuentas para recibir pagos:** lista (medio · número) y **Agregar cuenta** → diálogo "Nueva cuenta de cobro" con **Medio (Nequi, Daviplata, banco…)**, **Número de cuenta o celular**, **Titular**. Es lo que ven los jugadores al pagar el anticipo.
- **Mensualidad:** "$100.000 por 30 días", cuentas de la plataforma donde transferir, instrucciones y **Subir comprobante**; estado (pendiente de revisión, aprobada con fecha de vencimiento, rechazada, vencida).

### 3.6 Estadísticas
Selector **7 días / 30 días / 90 días** y seis tarjetas (etiqueta + valor grande): **Ingresos confirmados**, **Reservas confirmadas**, **Esperando pago**, **Canceladas**, **Horas reservadas**, **Ocupación** (%). No hay gráficos; si quieres uno, es un añadido de diseño nuevo.

### 3.7 Avisos y Perfil
Iguales a 2.7 y 2.8. Avisos del dueño: reserva nueva, pago por revisar, cancelaciones, mensualidad por vencer (3 días antes), mensualidad aprobada / rechazada / vencida.

---

## 4. Administrador

### 4.1 Pagos
Comprobantes de **mensualidad** de los dueños. **Por revisar** / **Historial**. Misma tarjeta de pago; **Aprobar** ("¿Aprobar la mensualidad?") o **Rechazar** con motivo.

### 4.2 Canchas
Todas las canchas: nombre, "Dueño: nombre · celular", estado. Insignias "Tiene un pago de mensualidad por revisar" / "Suspendida por el administrador". Acciones **Suspender** ("¿Suspender la cancha?") y **Reactivar**.

### 4.3 Usuarios
Buscador "Buscar por nombre o correo"; lista con nombre, correo, rol y estado. Acción **Eliminar** (confirma "¿Eliminar a …?").

### 4.4 Reseñas reportadas
Tarjeta: cancha · estrellas, "Por [autor] · N reportes", texto de la reseña, "Motivos: …". Botones **Conservar** y **Ocultar** ("¿Ocultar la reseña?").

### 4.5 Resumen
Métricas del negocio (usuarios, canchas activas, reservas, ingresos aprobados) y lista **Transacciones aprobadas**: "N transacciones · $total", cada fila con pagador, día y monto (anticipos y mensualidades).

### 4.6 Avisos y Perfil
Desde los íconos de la barra superior; mismas pantallas que 2.7 y 2.8.

---

## Resumen del conteo
- **Compartidas / sin sesión (5):** splash, login, crear cuenta, recuperar contraseña (+ nueva contraseña), confirmar correo.
- **Compartidas con sesión (2):** avisos, perfil.
- **Jugador (6):** canchas, detalle, aviso de anticipo (diálogo), pagar anticipo, reseñas (sección + diálogo), mis reservas.
- **Dueño (6):** reservas (+ diálogo bloquear), pagos, mis canchas, nueva cancha, administrar cancha, estadísticas.
- **Admin (5):** pagos, canchas, usuarios, reseñas reportadas, resumen.

---

## Actualización: pantallas con sesión (diseño nuevo)
Todas comparten el encabezado con sobretítulo verde en mayúsculas + título grande (botón ‹ en las que no son pestaña) y usan **hojas inferiores** en lugar de diálogos. La barra inferior es la de cristal con burbuja (contador rojo en Avisos). El admin trae campana (con contador) y perfil en el encabezado.

**Jugador**
- *Mis reservas:* selector Próximas / Anteriores; tarjeta con cancha, fecha y píldora de estado (Confirmada, Falta comprobante, En revisión, Pago rechazado, Completada, Cancelada), caja Total · Anticipo, aviso "Reserva de último momento · Sin cancelación", botones Cancelar (hoja de confirmación) y Pagar anticipo / Subir otro comprobante / Calificar (hoja con 5 estrellas y comentario).
- *Avisos:* tarjeta única con filas (título, texto, hora), punto rojo en las no leídas, "Marcar leídas".
- *Perfil:* tarjeta verde con iniciales y rol; filas Nombre, Correo (Confirmado / Sin confirmar + Reenviar) y Celular que abren hojas de edición; Cambiar contraseña, Cerrar sesión y Borrar mi cuenta (hoja roja).

**Dueño**
- *Reservas:* selector de cancha (hoja), tira de 14 días y la lista del día elegido; filas con hora, cancha, jugador y celular (toca = copiar), píldoras Confirmada / En revisión / Bloqueada y "Quitar bloqueo". Botón lima "+ Bloquear horas" → hoja con Cancha, Día, Desde, Duración y nota.
- *Pagos:* Por revisar / Historial; tarjeta con miniatura del comprobante (toca = ampliar), jugador, cancha, monto y Rechazar (hoja con motivo) / Aprobar (hoja de confirmación).
- *Mis canchas:* tarjeta "Ver estadísticas"; tarjetas con foto, tipo, precio y estado (Activa / Mensualidad pendiente / Oculta) + "Administrar cancha"; botón "+ Nueva cancha".
- *Nueva cancha:* campos con icono, "Usar mi ubicación actual" (coordenadas a mano plegables), precio, Abre/Cierra, tipo Fútbol 5–11, interruptores Techada y Exigir anticipo con porcentaje.
- *Administrar cancha:* cuadrícula de fotos con "+", Datos (Editar datos en hoja), Estado (interruptor), Cuentas para pagos (Agregar en hoja) y tarjeta ámbar de Mensualidad ("Vence en N días") con hoja para pagar y subir el comprobante.
- *Estadísticas:* 7 / 30 / 90 días; tarjeta verde de ingresos y cinco tarjetas de cifras.

**Admin**
- *Pagos:* mensualidades por revisar / historial con Aprobar / Rechazar. *Canchas:* dueño, avisos y Suspender / Reactivar. *Usuarios:* buscador y acciones Suspender / Restaurar / Eliminar. *Reseñas:* reporte con motivos y Conservar / Ocultar. *Resumen:* tarjetas de métricas (ingresos en verde) y transacciones aprobadas.

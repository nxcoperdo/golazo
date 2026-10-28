# Publicar Golazo en Google Play y App Store

Lista de pasos y respuestas listas para copiar. Lo legal (términos, privacidad, borrado de cuenta y soporte) lo sirve el propio servidor en `https://golazo-app.duckdns.org/legal/...`.

> No soy abogado: los textos de `backend/src/legal/content.ts` son borradores razonables para Colombia (Ley 1581 de 2012, Decreto 1377 de 2013, Ley 1480 de 2011). Conviene que un abogado los revise antes de publicar.

## 0. Antes de enviar nada

1. **Datos del responsable en el servidor** (VPS, `backend/.env`): `LEGAL_RESPONSIBLE_NAME`, `LEGAL_RESPONSIBLE_ID`, `LEGAL_CONTACT_EMAIL`, `LEGAL_PHONE`, `LEGAL_ADDRESS`, `LEGAL_CITY`. Sin ellos las páginas muestran marcadores `[ENTRE CORCHETES]`. Después: `docker compose up -d --force-recreate api`.
2. Abrir en el navegador y revisar las cuatro páginas:
   - `https://golazo-app.duckdns.org/legal/terminos`
   - `https://golazo-app.duckdns.org/legal/privacidad`
   - `https://golazo-app.duckdns.org/legal/eliminar-cuenta`
   - `https://golazo-app.duckdns.org/legal/soporte`
3. Aplicar la migración 006 y actualizar el API (paso 4 de "Despliegue en el VPS" en `backend/README.md`).
4. Crear **cuentas demo** en producción (jugador, dueño y una cancha activa) para los revisores: registrarlas desde la app y activar la cancha con el admin (Canchas → «Registrar mensualidad»).
5. Si cambias el fondo de los textos, sube `LEGAL_VERSION` en `backend/src/legal/content.ts`: la app volverá a pedir la aceptación a todos.
6. Consultar con un abogado si, como persona natural, debes inscribir las bases de datos en el RNBD de la SIC.

## 1. Google Play

### Firma del bundle
1. Crear la llave de subida (una sola vez; **guárdala y su clave fuera del repositorio, si se pierde no podrás actualizar la app**):
   ```
   keytool -genkey -v -keystore %USERPROFILE%\golazo-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Crear `android/key.properties` (ya está ignorado por git):
   ```
   storeFile=C:/Users/ASUS/golazo-upload.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```
   `storeFile` es relativo a `android/` o absoluto. Sin este archivo el release se firma con la llave de debug (sirve para probar, no para subir).
3. Compilar el bundle contra producción:
   ```
   flutter build appbundle --release --dart-define=API_URL=https://golazo-app.duckdns.org/v1
   ```
   Sale en `build/app/outputs/bundle/release/app-release.aab`. Activa «Play App Signing» al subirlo la primera vez.
4. Subir el número de versión en `pubspec.yaml` (`version: 1.0.0+2`) en cada envío.

### Ficha de la tienda
- **Nombre:** Golazo — Reserva de canchas
- **Descripción corta (80):** Encuentra y reserva canchas sintéticas de fútbol cerca de ti, en segundos.
- **Descripción larga:** Golazo te ayuda a encontrar canchas sintéticas de fútbol en Colombia, ver horarios en vivo y reservar en pocos toques. Filtra por ciudad, tipo de cancha (fútbol 5, 6, 7, 8 u 11), precio y distancia; paga el anticipo por transferencia directa al dueño y recibe la confirmación en la app. Si tienes una cancha, administra reservas, pagos, bloqueos de horario y estadísticas desde el mismo celular.
- **Categoría:** Deportes. **Contacto:** el correo de soporte. **Sitio web / política de privacidad:** `https://golazo-app.duckdns.org/legal/privacidad`
- Recursos: ícono 512×512, gráfico de funciones 1024×500, mínimo 2 capturas de teléfono (jugador: lista y detalle; dueño: reservas).

### Contenido de la app
- **Eliminar cuenta (URL obligatoria):** `https://golazo-app.duckdns.org/legal/eliminar-cuenta` (también hay «Borrar mi cuenta» dentro de la app).
- **Público objetivo:** 18+ (no es para niños).
- **Anuncios:** no. **Acceso de revisor:** dar las cuentas demo (jugador y dueño).
- **Compras dentro de la app:** ninguna. Las reservas son servicios físicos pagados por transferencia directa entre usuarios; la mensualidad de los dueños se gestiona fuera de la app.
- **Clasificación de contenido:** cuestionario IARC. Hay reseñas de usuarios (contenido generado por usuarios con reporte y moderación).

### Seguridad de los datos (Data safety)
| Dato | ¿Se recopila? | Uso | Compartido |
|---|---|---|---|
| Nombre, correo, celular | Sí | Funciones de la app, cuenta | No (el dueño ve nombre y celular de sus reservas) |
| Ubicación aproximada | Sí, solo si el usuario lo permite | Ordenar canchas por distancia | No |
| Fotos | Sí (canchas y comprobantes) | Funciones de la app | No |
| Identificadores de dispositivo (token push) | Sí | Notificaciones | Con Google (FCM) |
| Historial de reservas/pagos | Sí | Funciones de la app | No |
- Datos cifrados en tránsito: **Sí** (HTTPS). El usuario puede pedir que se borren sus datos: **Sí**.
- No se venden datos ni se usan para publicidad.

### Permisos y su justificación
- **Ubicación (mientras se usa):** «Cerca de mí» y autocompletar la ubicación de una cancha.
- **Cámara / fotos:** fotos de canchas y comprobantes de pago.
- **Notificaciones:** avisos de reservas y pagos.

### Pruebas obligatorias para cuentas personales nuevas
Las cuentas personales creadas después de nov. 2023 deben hacer una **prueba cerrada** (mín. 12 testers durante 14 días) antes de pasar a producción. Verifica en Play Console si aplica a tu cuenta; si ya tenías una app publicada, normalmente ya cumpliste el requisito.

## 2. App Store

### Cuenta y firma
1. Apple Developer Program (99 USD/año). Sin él no hay App Store ni push en iOS (el flujo actual de Codemagic es «sin firmar» para Sideloadly).
2. En App Store Connect: crear la app con el bundle `co.golazo.app`.
3. En Codemagic, para firmar: integración «App Store Connect API key» + certificado de distribución y perfil de aprovisionamiento; cambiar el flujo del `codemagic.yaml` a firmado y subir a TestFlight.
4. Push iOS: crear la clave APNs en Apple y cargarla en Firebase (Cloud Messaging → iOS).

### Reglas que ya cumple el diseño
- **4.8 Inicio de sesión con Apple:** en iOS no se muestra «Continuar con Google» (solo correo y contraseña), así que no se exige Apple. Si se quiere Google en iOS hay que añadir antes «Iniciar sesión con Apple».
- **5.1.1(v) Borrar la cuenta:** existe dentro de la app (Perfil → Borrar mi cuenta).
- **3.1.1 Compras:** la app no cobra nada; los pagos son transferencias entre usuarios por servicios físicos y la mensualidad se cobra fuera de la app.
- **1.2 Contenido de usuarios:** reseñas con reporte, moderación del administrador y contacto de soporte visible en Perfil.
- **Privacidad:** URL `https://golazo-app.duckdns.org/legal/privacidad`.

### Etiquetas de privacidad (App Privacy)
Datos vinculados a la identidad del usuario, **no** usados para seguimiento: información de contacto (nombre, correo, teléfono), ubicación aproximada, fotos, identificadores (token de notificaciones) e historial de compras/reservas. Finalidad: funcionalidad de la app.

### Notas para el revisor (copiar tal cual)
> Golazo es una plataforma para reservar canchas sintéticas de fútbol en Colombia. No vende bienes digitales ni cobra dentro de la app: el jugador transfiere el anticipo directamente al dueño y sube el comprobante. Cuentas de prueba — Jugador: `...@...` / `...`; Dueño de cancha: `...@...` / `...`. Reservar: Canchas → elegir una cancha → elegir horario → Reservar. Borrar cuenta: Perfil → Borrar mi cuenta. Soporte: Perfil → Soporte.

- **Cumplimiento de exportación:** solo usa HTTPS estándar (responder que usa cifrado exento).
- Capturas: 6,9" y 6,5" (iPhone) como mínimo.

## 3. Después de publicar
- Mantener `LEGAL_VERSION` al día y el correo de soporte atendido (consultas en máx. 10 días hábiles, reclamos 15).
- Cobro de mensualidades: el dueño paga fuera de la app; el admin registra el pago en Canchas → «Registrar mensualidad» (activa 30 días y avisa al dueño).

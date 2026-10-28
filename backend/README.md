# Golazo — Backend

NestJS 12 + PostgreSQL 16/PostGIS. Diseño y decisiones en [`../docs/backend-design.md`](../docs/backend-design.md).

## Estado

El backend cubre todo el alcance del diseño. Probado contra Postgres real con dos scripts de integración
(`scripts/integration-test.ps1` y `scripts/integration-test-2.ps1`) y tests unitarios (`npm test`).

**Sin probar con servicios externos reales** (el código existe y rechaza entradas inválidas, pero necesita credenciales):
login con un token real de Google, envío SMTP, push FCM. **No implementado:** APNs directo para iOS
(los tokens iOS se registran, pero hoy solo se envía por FCM).

## Desarrollo

```bash
cp .env.example .env          # rellena JWT_SECRET y POSTGRES_PASSWORD
npm install
npm run build
npm test                      # tests unitarios (no necesitan base de datos)
```

Con la base arriba (`docker compose up -d db`):

```bash
docker compose run --rm migrate                 # aplica /migrations (reconstruye con: docker compose build migrate)
docker compose up -d --build api
curl http://127.0.0.1:3000/v1/health
```

> Si agregas una migración nueva, reconstruye la imagen (`docker compose build migrate`) antes de correr `migrate`,
> o no verá el archivo.

### Crear el primer administrador

Los administradores no se pueden crear por la API:

```bash
docker compose run --rm migrate node dist/scripts/create-admin.js correo@dominio.com "Nombre Apellido" "contraseña-de-10+-caracteres"
```

### Pruebas de integración (PowerShell, Windows)

```powershell
./scripts/integration-test.ps1      # canchas, disponibilidad y reservas
./scripts/integration-test-2.ps1    # pagos, mensualidades, devoluciones, admin, reseñas, tareas y cuenta
./scripts/integration-test-3.ps1    # panel del dueño, avisos, recordatorios y verificación de correo
./scripts/integration-test-4.ps1    # chat jugador–dueño, soporte, bloqueos, reportes y moderación
```

Esperan ~1 minuto entre corridas por el límite de intentos de `/auth` (si reciben 429 esperan y repiten solas). Borran sus propios datos (`@itest.co`).

## Despliegue en el VPS (Docker + Caddy con HTTPS automático)

1. Un dominio apuntando a la IP del VPS (puede ser gratis en DuckDNS: `algo.duckdns.org`). Puertos 22, 80 y 443 abiertos.
2. En el servidor: `cp .env.example .env` y cambia **todos** los secretos (distintos a los de desarrollo) y pon `DOMAIN=algo.duckdns.org`.
3. Primera vez: `docker compose up -d db && docker compose run --rm migrate && docker compose --profile prod up -d --build`.
   Caddy pide solo el certificado de Let's Encrypt la primera vez (tarda unos segundos).
4. Actualizar: `git pull` (o copiar los archivos) y `docker compose build && docker compose run --rm migrate && docker compose --profile prod up -d`.
5. Crear el administrador: `docker compose run --rm migrate node dist/scripts/create-admin.js correo "Nombre" "clave-larga"`.
6. **Respaldos:** `pg_dump` diario **y** el volumen `uploads` (fotos y comprobantes), copiados fuera del VPS.
7. Opcionales en `.env`: `SMTP_URL`/`MAIL_FROM` (correos), `FCM_SERVICE_ACCOUNT_FILE` (push: JSON de la cuenta de servicio de Firebase guardado en `backend/secrets/fcm.json`, montado como volumen en `docker-compose.yml`, y `FCM_SERVICE_ACCOUNT_FILE=/run/secrets/fcm.json`), `GOOGLE_CLIENT_ID`, `PLATFORM_PAYMENT_ACCOUNTS`.
8. Legal (tiendas y Ley 1581): `LEGAL_RESPONSIBLE_NAME`, `LEGAL_RESPONSIBLE_ID`, `LEGAL_CONTACT_EMAIL`, `LEGAL_PHONE`, `LEGAL_ADDRESS`, `LEGAL_CITY`. Se muestran en `https://TU-DOMINIO/legal/terminos|privacidad|eliminar-cuenta|soporte` (páginas públicas fuera de `/v1`; sin las variables salen marcadores `[ENTRE CORCHETES]`). Los textos viven en `src/legal/content.ts`; al cambiar el fondo sube `LEGAL_VERSION` y la app vuelve a pedir la aceptación. Ver `docs/tiendas.md`.

La app apunta a `https://TU_DOMINIO/v1` (variable `API_URL` al compilar).

## Documentación OpenAPI

`docs/openapi.json` es la especificación completa (79 rutas, chat incluido; las canchas llevan `variants`: tipo y precio propios). Para verla en Swagger UI: `ENABLE_DOCS=1 docker compose up -d --build api` y abrir `http://127.0.0.1:3000/docs` (JSON en `/docs-json`). En producción déjala apagada. Para regenerar el archivo: con `ENABLE_DOCS=1` activo, `curl -s http://127.0.0.1:3000/docs-json -o ../docs/openapi.json`.

## Respaldos (VPS)

`scripts/backup.sh` guarda la base (`pg_dump` comprimido) y el volumen `uploads` (fotos y comprobantes) en `/opt/golazo-backups/AAAA-MM-DD_HHMM` y borra los de más de 7 días. Si algo falla no deja un respaldo a medias.

- Probar a mano: `bash /opt/golazo/backend/scripts/backup.sh`
- Diario con cron (`crontab -e`): `15 3 * * * bash /opt/golazo/backend/scripts/backup.sh >> /var/log/golazo-backup.log 2>&1`
- Copia FUERA del servidor (recomendado; solo en el VPS no protege si se pierde): `BACKUP_REMOTE=usuario@otro-servidor:/respaldos/golazo` en el cron (usa `rsync` por SSH). Variables: `BACKUP_DIR`, `KEEP_DAYS`.
- Restaurar la base (en una base nueva para probar, o sobre la real con la API detenida): `zcat db.sql.gz | docker compose exec -T db psql -U golazo -d golazo_prueba -v ON_ERROR_STOP=1`.
- Restaurar archivos: `docker compose exec -T api tar -C /app/storage -xz < uploads.tgz` (el contenedor `api` debe estar corriendo).

## Tareas programadas (cada minuto, con candado en la base)

- Cancela reservas sin comprobante tras `UNPAID_MINUTES` (30) y libera la hora.
- Suspende canchas con mensualidad vencida y avisa 3 días antes del vencimiento.
- Limpia tokens de sesión y de recuperación vencidos.
- Borra los mensajes del chat (y sus fotos) de más de 12 meses.
- El admin puede forzarlas: `POST /v1/admin/jobs/run`.

> Una cancha activa **sin** periodo de mensualidad vigente se suspende sola en el siguiente minuto.

## API (prefijo `/v1`)

Errores: `{ "code": "...", "message": "..." }` (validación: `{ message: [...] }`).

**Páginas legales** (sin `/v1`) — `GET /legal/terminos` · `/legal/privacidad` · `/legal/eliminar-cuenta` · `/legal/soporte` · `/legal/version`

**Público**
`GET /health` · `GET /courts?city&maxPrice&covered&lat&lng&radiusKm&limit&offset` · `GET /courts/:id` ·
`GET /courts/:id/availability?date=YYYY-MM-DD` · `GET /courts/:id/reviews` · `GET /files/courts/:archivo`

**Cuenta** — `POST /auth/register` (`acceptTerms: true` obligatorio, `asOwner` opcional) · `POST /auth/consent` (`{accept:true}`; `GET /auth/me` trae `consentRequired`) · `/auth/login` · `/auth/google` · `/auth/refresh` · `/auth/logout` ·
`GET|PATCH|DELETE /auth/me` · `POST /auth/change-password` · `/auth/forgot-password` · `/auth/reset-password`

**Jugador** — `POST /bookings` · `GET /bookings/mine` · `GET /bookings/:id` · `POST /bookings/:id/cancel` ·
`POST /bookings/:id/payment` (multipart `proof`) · `POST /bookings/:id/review` · `POST /reviews/:id/report` ·
`GET /payments/:id/proof` · `GET /notifications` · `POST /notifications/:id/read` · `/notifications/read-all` · `POST|DELETE /devices`

**Dueño** (`role=owner`) — `GET|POST /owner/courts` · `GET|PATCH /owner/courts/:id` · `PUT /owner/courts/:id/payment-methods` ·
`POST /owner/courts/:id/photos` (multipart `photo`) · `DELETE /owner/courts/:id/photos/:photoId` ·
`POST /owner/courts/:id/subscription-payment` (multipart `proof`) · `GET /owner/payments?status` ·
`POST /owner/payments/:id/approve|reject` · `GET /owner/refunds?status=pending|done` · `POST /owner/refunds/:id/done` (`{note?}`: anticipo devuelto por fuera de la app tras una cancelación) · `GET /owner/stats?from&to&courtId`

**Admin** (`role=admin`) — `GET /admin/users` · `POST /admin/users/:id/suspend|restore` · `DELETE /admin/users/:id` ·
`GET /admin/courts` · `POST /admin/courts/:id/suspend|reactivate` · `POST /admin/courts/:id/subscription-payment` (`{amount?, note?}`: mensualidad cobrada fuera de la app, abre 30 días y activa) · `GET /admin/payments?kind&status` ·
`POST /admin/payments/:id/approve|reject` · `GET /admin/review-reports` · `POST /admin/reviews/:id/hide|dismiss` ·
`GET /admin/transactions` · `GET /admin/metrics` · `POST /admin/jobs/run` ·
`GET /admin/chat/support` (bandeja de soporte, sin responder primero) · `GET /admin/chat/threads?search&courtId` (cualquier chat, solo lectura) ·
`GET|POST /admin/chat/threads/:id/messages` (solo puede escribir en soporte) · `GET /admin/chat/reports?all` · `POST /admin/chat/reports/:id/resolve` · `POST /admin/chat/messages/:id/hide`

**Chat** (cualquier usuario con sesión) — `GET /chat/threads` · `POST /chat/bookings/:bookingId` (hilo jugador–dueño de esa cancha) · `POST /chat/support` ·
`GET /chat/threads/:id/messages?after=<seq>&limit` (la app consulta cada ~4 s y marca leído) · `POST /chat/threads/:id/messages` (JSON `{body}` o multipart `image` + `body`; 30/min) ·
`GET /chat/images/:messageId` · `POST /chat/messages/:id/report` · `POST|DELETE /chat/blocks/:userId`.
Un hilo por jugador y cancha: se puede escribir mientras el jugador tenga ahí una reserva vigente (pendiente, en revisión, confirmada o rechazada y sin terminar); si no, queda de solo lectura (`409 CHAT_CLOSED`) hasta la siguiente reserva. El soporte siempre está abierto. Cada mensaje nuevo envía push `{type:'chat_message', threadId}` (no va a la bandeja de avisos).

## Decisiones de seguridad a tener presentes

- Montos, anticipos y reglas de horario se calculan en el servidor; el cliente nunca los define.
- Imágenes: se validan por contenido (jpg/png/webp), ≤ 5 MB, se re-codifican y pierden EXIF/GPS. Los comprobantes solo los ven
  quien los subió, el dueño de esa cancha y los admins.
- Un administrador no se puede suspender ni borrar desde la API; el rol `admin` nunca se asigna por la API.
- Una cancha suspendida por el admin no se reactiva sola al pagar la mensualidad.

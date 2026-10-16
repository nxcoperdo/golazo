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
./scripts/integration-test-2.ps1    # pagos, mensualidades, admin, reseñas, tareas y cuenta
```

Esperan ~1 minuto entre corridas por el límite de intentos de `/auth`. Borran sus propios datos (`@itest.co`).

## Despliegue en el VPS (Docker + Caddy con HTTPS automático)

1. Un dominio apuntando a la IP del VPS (puede ser gratis en DuckDNS: `algo.duckdns.org`). Puertos 22, 80 y 443 abiertos.
2. En el servidor: `cp .env.example .env` y cambia **todos** los secretos (distintos a los de desarrollo) y pon `DOMAIN=algo.duckdns.org`.
3. Primera vez: `docker compose up -d db && docker compose run --rm migrate && docker compose --profile prod up -d --build`.
   Caddy pide solo el certificado de Let's Encrypt la primera vez (tarda unos segundos).
4. Actualizar: `git pull` (o copiar los archivos) y `docker compose build && docker compose run --rm migrate && docker compose --profile prod up -d`.
5. Crear el administrador: `docker compose run --rm migrate node dist/scripts/create-admin.js correo "Nombre" "clave-larga"`.
6. **Respaldos:** `pg_dump` diario **y** el volumen `uploads` (fotos y comprobantes), copiados fuera del VPS.
7. Opcionales en `.env`: `SMTP_URL`/`MAIL_FROM` (correos), `FCM_SERVICE_ACCOUNT_FILE` (push: JSON de la cuenta de servicio de Firebase guardado en `backend/secrets/fcm.json`, montado como volumen en `docker-compose.yml`, y `FCM_SERVICE_ACCOUNT_FILE=/run/secrets/fcm.json`), `GOOGLE_CLIENT_ID`, `PLATFORM_PAYMENT_ACCOUNTS`.

La app apunta a `https://TU_DOMINIO/v1` (variable `API_URL` al compilar).

## Tareas programadas (cada minuto, con candado en la base)

- Cancela reservas sin comprobante tras `UNPAID_MINUTES` (30) y libera la hora.
- Suspende canchas con mensualidad vencida y avisa 3 días antes del vencimiento.
- Limpia tokens de sesión y de recuperación vencidos.
- El admin puede forzarlas: `POST /v1/admin/jobs/run`.

> Una cancha activa **sin** periodo de mensualidad vigente se suspende sola en el siguiente minuto.

## API (prefijo `/v1`)

Errores: `{ "code": "...", "message": "..." }` (validación: `{ message: [...] }`).

**Público**
`GET /health` · `GET /courts?city&maxPrice&covered&lat&lng&radiusKm&limit&offset` · `GET /courts/:id` ·
`GET /courts/:id/availability?date=YYYY-MM-DD` · `GET /courts/:id/reviews` · `GET /files/courts/:archivo`

**Cuenta** — `POST /auth/register` (`asOwner` opcional) · `/auth/login` · `/auth/google` · `/auth/refresh` · `/auth/logout` ·
`GET|PATCH|DELETE /auth/me` · `POST /auth/change-password` · `/auth/forgot-password` · `/auth/reset-password`

**Jugador** — `POST /bookings` · `GET /bookings/mine` · `GET /bookings/:id` · `POST /bookings/:id/cancel` ·
`POST /bookings/:id/payment` (multipart `proof`) · `POST /bookings/:id/review` · `POST /reviews/:id/report` ·
`GET /payments/:id/proof` · `GET /notifications` · `POST /notifications/:id/read` · `/notifications/read-all` · `POST|DELETE /devices`

**Dueño** (`role=owner`) — `GET|POST /owner/courts` · `GET|PATCH /owner/courts/:id` · `PUT /owner/courts/:id/payment-methods` ·
`POST /owner/courts/:id/photos` (multipart `photo`) · `DELETE /owner/courts/:id/photos/:photoId` ·
`POST /owner/courts/:id/subscription-payment` (multipart `proof`) · `GET /owner/payments?status` ·
`POST /owner/payments/:id/approve|reject` · `GET /owner/stats?from&to&courtId`

**Admin** (`role=admin`) — `GET /admin/users` · `POST /admin/users/:id/suspend|restore` · `DELETE /admin/users/:id` ·
`GET /admin/courts` · `POST /admin/courts/:id/suspend|reactivate` · `GET /admin/payments?kind&status` ·
`POST /admin/payments/:id/approve|reject` · `GET /admin/review-reports` · `POST /admin/reviews/:id/hide|dismiss` ·
`GET /admin/transactions` · `GET /admin/metrics` · `POST /admin/jobs/run`

## Decisiones de seguridad a tener presentes

- Montos, anticipos y reglas de horario se calculan en el servidor; el cliente nunca los define.
- Imágenes: se validan por contenido (jpg/png/webp), ≤ 5 MB, se re-codifican y pierden EXIF/GPS. Los comprobantes solo los ven
  quien los subió, el dueño de esa cancha y los admins.
- Un administrador no se puede suspender ni borrar desde la API; el rol `admin` nunca se asigna por la API.
- Una cancha suspendida por el admin no se reactiva sola al pagar la mensualidad.

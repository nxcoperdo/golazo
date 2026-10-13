# Golazo — Backend

NestJS 12 + PostgreSQL 16/PostGIS. Diseño completo en [`../docs/backend-design.md`](../docs/backend-design.md).

## Estado

| Hecho | Pendiente |
|---|---|
| Esquema SQL completo (`migrations/001_init.sql`) | Canchas y disponibilidad |
| Auth: registro, login, Google, refresh rotativo, logout, `/auth/me` | Reservas (usa `bookings/booking-policy.ts`) |
| Guard con roles y suspensión inmediata | Pagos y comprobantes |
| Límite de tasa, validación estricta, `/v1/health` | Mensualidades, reseñas, notificaciones, panel admin |
| Política de reservas (24 h / 8 h / 30 %) con tests | Subida de archivos |

## Desarrollo

```bash
cp .env.example .env          # y rellena JWT_SECRET y POSTGRES_PASSWORD
npm install
npm run build
npm test                      # tests unitarios (no necesitan base de datos)
```

Con una base PostgreSQL+PostGIS disponible:

```bash
export DATABASE_URL=postgres://golazo:...@localhost:5432/golazo
npm run migrate               # aplica /migrations en orden
npm run start:dev
```

## Despliegue en el VPS

```bash
docker compose up -d db
docker compose run --rm migrate      # aplica migraciones
docker compose up -d --build api
curl http://127.0.0.1:3000/v1/health
```

Nginx debe terminar TLS y reenviar a `127.0.0.1:3000` con `X-Forwarded-For`.

## Endpoints disponibles (prefijo `/v1`)

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/health` | Estado de la API y la base |
| POST | `/auth/register` | `{name, email, password, phone}` |
| POST | `/auth/login` | `{email, password}` |
| POST | `/auth/google` | `{idToken, phone?}` |
| POST | `/auth/refresh` | `{refreshToken}` (rota el token) |
| POST | `/auth/logout` | `{refreshToken}` |
| GET | `/auth/me` | Usuario actual (Bearer) |

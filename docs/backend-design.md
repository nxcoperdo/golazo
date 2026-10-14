# Golazo — Diseño del backend

Estado: borrador para revisión. Aún no hay código del backend.

## 1. Stack y despliegue

- **API:** NestJS (TypeScript) + TypeORM o Prisma, REST con JSON, documentada con OpenAPI.
- **Base de datos:** PostgreSQL 16 + PostGIS (búsqueda por cercanía) + extensión `btree_gist` (evitar reservas dobles).
- **Archivos:** fotos de canchas y comprobantes en disco del VPS (volumen Docker), servidos por Nginx con URLs firmadas para los comprobantes (son privados).
- **VPS:** Docker Compose con `nginx` (TLS con Let's Encrypt), `api`, `postgres`, `redis` (colas de notificaciones y límites de tasa). Backups diarios de `pg_dump` y de la carpeta de archivos, copiados fuera del VPS.
- **Zona horaria:** todo se guarda en UTC (`timestamptz`). Las reglas de 24 h y 8 h se evalúan con la hora del servidor, nunca la del teléfono.

## 2. Modelo de datos

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TYPE user_role AS ENUM ('player','owner','admin');

CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role          user_role NOT NULL DEFAULT 'player',
  name          text NOT NULL,
  email         text UNIQUE,
  phone         text,                 -- 3XXXXXXXXX, solo contacto (sin verificar); obligatorio antes de reservar
  google_sub    text UNIQUE,
  password_hash text,                 -- null si entra solo con Google/celular
  suspended_at  timestamptz,
  deleted_at    timestamptz,          -- borrado lógico
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (email IS NOT NULL OR google_sub IS NOT NULL)
);

CREATE TYPE court_status AS ENUM ('pending','active','suspended');

CREATE TABLE courts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id         uuid NOT NULL REFERENCES users(id),
  name             text NOT NULL,
  description      text,
  city             text NOT NULL,
  address          text NOT NULL,
  location         geography(Point,4326) NOT NULL,
  covered          boolean NOT NULL,
  price_per_hour   integer NOT NULL CHECK (price_per_hour > 0),   -- COP
  open_hour        smallint NOT NULL CHECK (open_hour BETWEEN 0 AND 23),
  close_hour       smallint NOT NULL CHECK (close_hour BETWEEN 1 AND 24),
  requires_deposit boolean NOT NULL DEFAULT false,
  deposit_percent  smallint NOT NULL DEFAULT 30 CHECK (deposit_percent BETWEEN 10 AND 100),
  status           court_status NOT NULL DEFAULT 'pending',
  created_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (close_hour > open_hour)
);
CREATE INDEX courts_location_gix ON courts USING gist (location);
CREATE INDEX courts_city_status_idx ON courts (city, status);

CREATE TABLE court_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id uuid NOT NULL REFERENCES courts(id) ON DELETE CASCADE,
  path text NOT NULL, position smallint NOT NULL DEFAULT 0
);

-- Cuentas donde el dueño recibe transferencias (Nequi, Daviplata, banco...)
CREATE TABLE court_payment_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id uuid NOT NULL REFERENCES courts(id) ON DELETE CASCADE,
  label text NOT NULL, account text NOT NULL, holder text NOT NULL
);

CREATE TYPE booking_status AS ENUM
  ('pending_payment','pending_review','confirmed','rejected','cancelled');

CREATE TABLE bookings (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id     uuid NOT NULL REFERENCES courts(id),
  player_id    uuid NOT NULL REFERENCES users(id),
  start_at     timestamptz NOT NULL,
  hours        smallint NOT NULL CHECK (hours BETWEEN 1 AND 4),
  end_at       timestamptz NOT NULL,          -- start_at + hours
  total        integer NOT NULL,                -- price_per_hour × hours
  deposit      integer NOT NULL DEFAULT 0,    -- calculado por el servidor
  last_minute  boolean NOT NULL DEFAULT false,-- <8 h: no cancelable
  status       booking_status NOT NULL,
  cancelled_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  -- Imposible reservar la misma cancha y hora dos veces mientras esté viva.
  EXCLUDE USING gist (court_id WITH =, tstzrange(start_at, end_at) WITH &&)
    WHERE (status IN ('pending_payment','pending_review','confirmed','rejected'))
);

CREATE TYPE payment_kind   AS ENUM ('booking','subscription');
CREATE TYPE payment_status AS ENUM ('pending','approved','rejected');

CREATE TABLE payments (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind         payment_kind NOT NULL,
  booking_id   uuid REFERENCES bookings(id),
  court_id     uuid NOT NULL REFERENCES courts(id),   -- para filtrar rápido
  payer_id     uuid NOT NULL REFERENCES users(id),
  amount       integer NOT NULL,
  proof_path   text NOT NULL,
  status       payment_status NOT NULL DEFAULT 'pending',
  reviewed_by  uuid REFERENCES users(id),
  reviewed_at  timestamptz,
  reject_reason text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK ((kind = 'booking') = (booking_id IS NOT NULL))
);

-- Mensualidad: una fila por periodo pagado. La cancha está activa mientras
-- exista un periodo vigente.
CREATE TABLE subscription_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id uuid NOT NULL REFERENCES courts(id),
  payment_id uuid NOT NULL UNIQUE REFERENCES payments(id),
  starts_on date NOT NULL, ends_on date NOT NULL
);

CREATE TABLE reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id uuid NOT NULL REFERENCES courts(id),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id), -- 1 reseña por reserva jugada
  author_id uuid NOT NULL REFERENCES users(id),
  stars smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
  body text, hidden_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE review_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id uuid NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  reporter_id uuid NOT NULL REFERENCES users(id),
  reason text, resolved_at timestamptz,
  UNIQUE (review_id, reporter_id)
);

CREATE TABLE device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform text NOT NULL, token text NOT NULL UNIQUE
);

CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title text NOT NULL, body text NOT NULL,
  read_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE refresh_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE, expires_at timestamptz NOT NULL, revoked_at timestamptz
);
```

La calificación promedio de una cancha se calcula con `AVG(stars)` sobre reseñas no ocultas (con caché en `courts` si hace falta más adelante).

## 3. Reglas de negocio (fuente de verdad en el servidor)

La app mantiene `BookingPolicy` solo para mostrar avisos; el servidor recalcula todo al crear la reserva.

| Regla | Implementación |
|---|---|
| Última hora | `start_at - now() < 8 h` → `last_minute = true`, `deposit = round(total × 0.30)`, no cancelable |
| Anticipo de la cancha | si no es última hora y `requires_deposit` → `deposit = round(total × deposit_percent / 100)`; si no, `0` |
| Estado inicial | `deposit = 0` → `confirmed`; `deposit > 0` → `pending_payment` |
| Cancelación gratis | permitida si `last_minute = false` y `start_at - now() >= 24 h` |
| Cancha visible | `status = 'active'` y existe `subscription_periods` vigente |
| Hora válida | dentro de `open_hour..close_hour`, en punto, futura |
| Varias horas | `hours` entre 1 y 4, **bloque contiguo del mismo día**; el bloque entero debe caber en el horario de la cancha y estar libre. Un solo pago y una sola reserva |
| Reglas de 24 h y 8 h | se miden desde `start_at` (la primera hora del bloque) |
| Cancelación | siempre de la reserva completa; no hay cancelación parcial de horas |
| Anticipo | porcentaje sobre el `total` del bloque (el 30 % de última hora también) |

Máquina de estados de una reserva:
`pending_payment → pending_review` (sube comprobante) `→ confirmed | rejected`; `rejected → pending_review` (sube otro); cualquier estado vivo `→ cancelled` si la regla lo permite.

Una reserva en `pending_payment` o `rejected` sin comprobante nuevo **vence a los 30 min** (job programado) y pasa a `cancelled` para liberar la hora. Mientras tanto una reserva `rejected` conserva la hora, porque el jugador puede volver a subir el comprobante. *(Plazo propuesto; hay que confirmarlo.)*

La mensualidad: al aprobar el pago `subscription`, se crea un periodo de 30 días y la cancha pasa a `active`. Un job diario pasa a `suspended` las canchas sin periodo vigente y avisa 3 días antes del vencimiento.

## 4. API (prefijo `/v1`)

**Auth**
- `POST /auth/register` (correo+contraseña o celular), `POST /auth/login`, `POST /auth/google`, `POST /auth/refresh`, `POST /auth/logout`
- El celular **no es método de login**: se pide al registrarse como dato de contacto (el dueño lo ve en la reserva) y se valida solo el formato `3XXXXXXXXX`. Quien entra con Google lo completa en un paso posterior antes de reservar.

**Jugador**
- `GET /courts?city=&lat=&lng=&radius=&maxPrice=&covered=` — solo activas; ordena por cercanía si hay `lat/lng`.
- `GET /courts/:id` — detalle, fotos, medios de pago, rating.
- `GET /courts/:id/availability?date=YYYY-MM-DD` — horas libres/ocupadas.
- `POST /bookings` `{courtId, startAt, hours}` (`hours` 1–4) → devuelve reserva con `deposit` y estado.
- `GET /bookings/mine`, `POST /bookings/:id/cancel`
- `POST /bookings/:id/payment` (multipart: comprobante)
- `POST /bookings/:id/review`, `POST /reviews/:id/report`
- `GET /notifications`, `POST /notifications/:id/read`, `POST /devices` (registrar token push)

**Dueño** (`/owner/...`, solo sus canchas)
- `POST /owner/courts` (crea en `pending`), `PATCH /owner/courts/:id`, `POST /owner/courts/:id/photos`
- `GET /owner/payments?status=pending`, `POST /owner/payments/:id/approve|reject` (solo pagos de reservas de sus canchas)
- `POST /owner/courts/:id/subscription-payment` (comprobante de mensualidad)
- `GET /owner/stats?from=&to=` — reservas, ingresos, ocupación.

**Admin** (`/admin/...`)
- `GET /admin/courts?status=`, `POST /admin/courts/:id/approve|suspend`
- `GET /admin/payments?kind=subscription&status=pending`, `POST /admin/payments/:id/approve|reject`
- `GET /admin/users`, `POST /admin/users/:id/suspend|restore`, `DELETE /admin/users/:id`
- `GET /admin/review-reports`, `POST /admin/reviews/:id/hide`, `POST /admin/review-reports/:id/dismiss`
- `GET /admin/transactions`, `GET /admin/metrics`

Errores con formato uniforme `{code, message}`. Respuestas paginadas con cursor en los listados.

## 5. Seguridad

- Contraseñas con argon2id. JWT de acceso corto (15 min) + refresh token rotativo guardado como hash.
- Guards por rol y por propiedad: un dueño solo toca sus canchas y los pagos de ellas.
- Comprobantes: solo visibles para el jugador que los subió, el dueño de esa cancha y los administradores, mediante una descarga autenticada (`GET /payments/:id/proof`, sin caché) en vez de URLs firmadas: más simple y se revoca al instante. Validar tipo real (JPEG/PNG/WebP/PDF) y tamaño (≤ 5 MB), re-codificar imágenes y quitar metadatos EXIF.
- Límites de tasa en login y subida de archivos. Validación de DTO en todas las entradas.
- Eliminar usuario = anonimizar (`deleted_at`, borrar correo/celular/nombre) para conservar el historial de transacciones.
- Datos personales: la Ley 1581 de 2012 (Colombia) exige política de tratamiento de datos y autorización del titular; incluirlo antes de publicar.

## 6. Concurrencia y consistencia

- La restricción `EXCLUDE` es la defensa real contra dos reservas de la misma hora; el servicio captura el error y responde `409 SLOT_TAKEN`.
- Aprobar/rechazar un pago ocurre en una transacción que actualiza `payments` y `bookings` juntas y deja la notificación en la misma transacción (patrón *outbox*) para no perder avisos.

## 7. Decisiones tomadas

1. **Push:** FCM solo como canal de entrega (ver §7.1).
2. **Celular:** solo dato de contacto, sin login por SMS. No hay proveedor de SMS ni OTP.
3. **Reservas sin comprobante:** la hora se libera a los 30 min.
4. **Varias horas:** bloque contiguo de 1 a 4 horas el mismo día, una reserva y un pago; reglas medidas desde la hora de inicio; cancelación total. El máximo de 4 es una constante del servidor y se puede cambiar.
5. **Imágenes:** en disco del VPS, con respaldo fuera del servidor.
6. **Comisión:** hoy solo se cobra la mensualidad; el modelo de pagos permite añadir una comisión después.

### 7.1 Notificaciones push

Decisión: se usa **FCM únicamente como canal de entrega del push**. No se usa Firebase Auth, Firestore, Storage ni Analytics; todo lo demás vive en tu backend.

- **Android:** FCM (con la API HTTP v1, autenticada con una cuenta de servicio). Es lo que permite avisar con la app cerrada.
- **iOS:** APNs directo desde el backend (clave `.p8`), o FCM como puente si prefieres un solo canal. Propongo APNs directo para depender menos de Google.
- **Flujo:** la app registra su token en `POST /devices`; cuando ocurre un evento (pago aprobado/rechazado, reserva confirmada, recordatorio) el backend guarda la fila en `notifications` y encola el envío; un worker llama a FCM/APNs y borra los tokens que respondan "no registrado".
- **La bandeja `notifications` sigue siendo la fuente de verdad:** si el push falla, el aviso igual aparece al abrir la app.
- **Recordatorios de reserva:** se envían desde el backend con un job programado (por ejemplo 2 h antes). Opcionalmente se duplican como notificación local en el teléfono.
- **Respaldo:** los avisos críticos (pago aprobado/rechazado) también se envían por correo.
- **Diseño abierto:** el backend define una interfaz `NotificationChannel` (`inApp`, `fcm`, `apns`, `email`), así que cambiar o agregar canales no afecta al resto.
- **Flutter:** `firebase_core` + `firebase_messaging` solo para recibir el token y los mensajes, más `flutter_local_notifications` para mostrarlos en primer plano. Requiere crear un proyecto en la consola de Firebase para obtener `google-services.json`.

## 8. Orden de implementación sugerido

1. Proyecto NestJS + Docker Compose + migraciones + auth (correo/Google).
2. Canchas, disponibilidad y reservas (con la restricción anti-doble reserva y `BookingPolicy` en el servidor, con tests).
3. Pagos y comprobantes + paneles de dueño.
4. Mensualidades, jobs de vencimiento y panel admin.
5. Reseñas, notificaciones y push.
6. En Flutter: reemplazar los repositorios mock por clientes de la API.

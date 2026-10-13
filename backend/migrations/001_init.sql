-- Esquema inicial de Golazo. Ver docs/backend-design.md.
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TYPE user_role AS ENUM ('player', 'owner', 'admin');

CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role          user_role NOT NULL DEFAULT 'player',
  name          text NOT NULL,
  email         text UNIQUE,                 -- siempre en minúsculas
  phone         text,                        -- contacto, formato 3XXXXXXXXX; obligatorio antes de reservar
  google_sub    text UNIQUE,
  password_hash text,                        -- null si entra solo con Google
  suspended_at  timestamptz,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (email IS NOT NULL OR google_sub IS NOT NULL),
  CHECK (phone IS NULL OR phone ~ '^3[0-9]{9}$')
);

CREATE TYPE court_status AS ENUM ('pending', 'active', 'suspended');

CREATE TABLE courts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id         uuid NOT NULL REFERENCES users(id),
  name             text NOT NULL,
  description      text,
  city             text NOT NULL,
  address          text NOT NULL,
  location         geography(Point, 4326) NOT NULL,
  covered          boolean NOT NULL,
  price_per_hour   integer NOT NULL CHECK (price_per_hour > 0),
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
CREATE INDEX courts_owner_idx ON courts (owner_id);

CREATE TABLE court_photos (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id uuid NOT NULL REFERENCES courts(id) ON DELETE CASCADE,
  path     text NOT NULL,
  position smallint NOT NULL DEFAULT 0
);

CREATE TABLE court_payment_methods (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id uuid NOT NULL REFERENCES courts(id) ON DELETE CASCADE,
  label    text NOT NULL,
  account  text NOT NULL,
  holder   text NOT NULL
);

CREATE TYPE booking_status AS ENUM
  ('pending_payment', 'pending_review', 'confirmed', 'rejected', 'cancelled');

CREATE TABLE bookings (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id     uuid NOT NULL REFERENCES courts(id),
  player_id    uuid NOT NULL REFERENCES users(id),
  start_at     timestamptz NOT NULL,
  hours        smallint NOT NULL CHECK (hours BETWEEN 1 AND 4),
  end_at       timestamptz NOT NULL,
  total        integer NOT NULL CHECK (total > 0),
  deposit      integer NOT NULL DEFAULT 0 CHECK (deposit >= 0),
  last_minute  boolean NOT NULL DEFAULT false,
  status       booking_status NOT NULL,
  cancelled_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (end_at = start_at + make_interval(hours => hours)),
  -- Imposible reservar la misma cancha y hora dos veces mientras la reserva
  -- esté viva. "rejected" conserva la hora porque el jugador puede volver a
  -- subir el comprobante.
  EXCLUDE USING gist (court_id WITH =, tstzrange(start_at, end_at) WITH &&)
    WHERE (status IN ('pending_payment', 'pending_review', 'confirmed', 'rejected'))
);
CREATE INDEX bookings_player_idx ON bookings (player_id, start_at DESC);
CREATE INDEX bookings_court_idx ON bookings (court_id, start_at);

CREATE TYPE payment_kind   AS ENUM ('booking', 'subscription');
CREATE TYPE payment_status AS ENUM ('pending', 'approved', 'rejected');

CREATE TABLE payments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind          payment_kind NOT NULL,
  booking_id    uuid REFERENCES bookings(id),
  court_id      uuid NOT NULL REFERENCES courts(id),
  payer_id      uuid NOT NULL REFERENCES users(id),
  amount        integer NOT NULL CHECK (amount > 0),
  proof_path    text NOT NULL,
  status        payment_status NOT NULL DEFAULT 'pending',
  reviewed_by   uuid REFERENCES users(id),
  reviewed_at   timestamptz,
  reject_reason text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK ((kind = 'booking') = (booking_id IS NOT NULL))
);
CREATE INDEX payments_court_status_idx ON payments (court_id, status);

CREATE TABLE subscription_periods (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id   uuid NOT NULL REFERENCES courts(id),
  payment_id uuid NOT NULL UNIQUE REFERENCES payments(id),
  starts_on  date NOT NULL,
  ends_on    date NOT NULL,
  CHECK (ends_on > starts_on)
);
CREATE INDEX subscription_court_idx ON subscription_periods (court_id, ends_on DESC);

CREATE TABLE reviews (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id   uuid NOT NULL REFERENCES courts(id),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id),
  author_id  uuid NOT NULL REFERENCES users(id),
  stars      smallint NOT NULL CHECK (stars BETWEEN 1 AND 5),
  body       text,
  hidden_at  timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reviews_court_idx ON reviews (court_id) WHERE hidden_at IS NULL;

CREATE TABLE review_reports (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id   uuid NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  reporter_id uuid NOT NULL REFERENCES users(id),
  reason      text,
  resolved_at timestamptz,
  UNIQUE (review_id, reporter_id)
);

CREATE TABLE device_tokens (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform text NOT NULL CHECK (platform IN ('android', 'ios')),
  token    text NOT NULL UNIQUE
);

CREATE TABLE notifications (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title      text NOT NULL,
  body       text NOT NULL,
  read_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_idx ON notifications (user_id, created_at DESC);

CREATE TABLE refresh_tokens (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_user_idx ON refresh_tokens (user_id);

-- Cuentas eliminadas: se anonimizan (sin correo ni Google) pero conservan el historial.
ALTER TABLE users DROP CONSTRAINT users_check;
ALTER TABLE users ADD CONSTRAINT users_identity_check
  CHECK (deleted_at IS NOT NULL OR email IS NOT NULL OR google_sub IS NOT NULL);

-- Una cancha suspendida por el admin no se reactiva sola al pagar la mensualidad.
ALTER TABLE courts ADD COLUMN suspended_by_admin boolean NOT NULL DEFAULT false;

-- Recordatorio de vencimiento de mensualidad enviado una sola vez por periodo.
ALTER TABLE subscription_periods ADD COLUMN reminded_at timestamptz;

-- Datos extra para abrir la pantalla correcta desde una notificación.
ALTER TABLE notifications ADD COLUMN data jsonb;

CREATE TABLE password_resets (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  used_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX password_resets_user_idx ON password_resets (user_id);

-- Un solo comprobante pendiente por reserva y por cancha (mensualidad).
CREATE UNIQUE INDEX payments_one_pending_booking
  ON payments (booking_id) WHERE status = 'pending' AND kind = 'booking';
CREATE UNIQUE INDEX payments_one_pending_subscription
  ON payments (court_id) WHERE status = 'pending' AND kind = 'subscription';

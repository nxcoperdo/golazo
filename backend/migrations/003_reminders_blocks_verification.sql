-- Recordatorio de reserva enviado una sola vez.
ALTER TABLE bookings ADD COLUMN reminded_at timestamptz;

-- El dueño puede bloquear horas a mano (p. ej. reservas que le llegan por WhatsApp).
-- Es una reserva "confirmada" a nombre del dueño que no cuenta como ingreso ni como reserva de jugador.
ALTER TABLE bookings ADD COLUMN owner_block boolean NOT NULL DEFAULT false;
ALTER TABLE bookings ADD COLUMN note text;

-- Verificación de correo. Los usuarios que ya existían se consideran verificados.
ALTER TABLE users ADD COLUMN email_verified_at timestamptz;
UPDATE users SET email_verified_at = created_at WHERE email IS NOT NULL OR google_sub IS NOT NULL;

CREATE TABLE email_verifications (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  used_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX email_verifications_user_idx ON email_verifications (user_id);

-- Para buscar rápido las reservas que toca recordar.
CREATE INDEX bookings_reminder_idx ON bookings (start_at)
  WHERE status = 'confirmed' AND reminded_at IS NULL AND NOT owner_block;

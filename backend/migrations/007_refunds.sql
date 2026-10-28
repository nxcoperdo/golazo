-- Registro de devoluciones. Golazo no mueve dinero: cuando un jugador cancela una reserva cuyo anticipo
-- ya fue aprobado, el dueño debe devolverlo por fuera de la app y aquí queda constancia (pendiente -> hecha).
CREATE TYPE refund_status AS ENUM ('pending', 'done');

CREATE TABLE refunds (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL UNIQUE REFERENCES bookings(id),
  court_id   uuid NOT NULL REFERENCES courts(id),
  player_id  uuid NOT NULL REFERENCES users(id),
  amount     integer NOT NULL CHECK (amount > 0),
  status     refund_status NOT NULL DEFAULT 'pending',
  note       text,
  created_at timestamptz NOT NULL DEFAULT now(),
  done_at    timestamptz,
  CHECK ((status = 'done') = (done_at IS NOT NULL))
);
CREATE INDEX refunds_court_status_idx ON refunds (court_id, status);

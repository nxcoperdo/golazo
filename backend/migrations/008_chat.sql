-- Chat dentro de la app.
--  * 'court':   jugador <-> dueño de la cancha. Un hilo por (cancha, jugador); se puede escribir mientras el
--               jugador tenga una reserva vigente en esa cancha. Al terminar queda solo lectura y se reabre
--               al volver a reservar.
--  * 'support': usuario (jugador o dueño) <-> soporte (administradores). Un hilo por usuario, siempre abierto.
CREATE TYPE chat_kind AS ENUM ('court', 'support');

CREATE TABLE chat_threads (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind            chat_kind NOT NULL,
  court_id        uuid REFERENCES courts(id),
  -- Jugador (hilo de cancha) o usuario que escribe a soporte.
  participant_id  uuid NOT NULL REFERENCES users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  last_message_at timestamptz,
  CHECK ((kind = 'court') = (court_id IS NOT NULL))
);
CREATE UNIQUE INDEX chat_threads_court_uq   ON chat_threads (court_id, participant_id) WHERE kind = 'court';
CREATE UNIQUE INDEX chat_threads_support_uq ON chat_threads (participant_id) WHERE kind = 'support';
CREATE INDEX chat_threads_participant_idx   ON chat_threads (participant_id);

CREATE TABLE chat_messages (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Orden estable y cursor para pedir "lo nuevo" (la app envía after=<seq>).
  seq        bigint GENERATED ALWAYS AS IDENTITY,
  thread_id  uuid NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
  sender_id  uuid NOT NULL REFERENCES users(id),
  body       text,
  image_path text,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Moderación o cuenta eliminada: el mensaje deja de mostrarse.
  hidden_at  timestamptz,
  CHECK (body IS NOT NULL OR image_path IS NOT NULL),
  CHECK (body IS NULL OR char_length(body) <= 1000)
);
CREATE INDEX chat_messages_thread_idx ON chat_messages (thread_id, seq);
CREATE INDEX chat_messages_sender_idx ON chat_messages (sender_id);
CREATE INDEX chat_messages_created_idx ON chat_messages (created_at);

-- Hasta qué mensaje leyó cada participante (para el contador de no leídos).
CREATE TABLE chat_reads (
  thread_id uuid NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
  user_id   uuid NOT NULL REFERENCES users(id),
  last_seq  bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (thread_id, user_id)
);

CREATE TABLE chat_reports (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id  uuid NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
  reporter_id uuid NOT NULL REFERENCES users(id),
  reason      text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolved_by uuid REFERENCES users(id),
  UNIQUE (message_id, reporter_id)
);
CREATE INDEX chat_reports_open_idx ON chat_reports (created_at) WHERE resolved_at IS NULL;

CREATE TABLE chat_blocks (
  blocker_id uuid NOT NULL REFERENCES users(id),
  blocked_id uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

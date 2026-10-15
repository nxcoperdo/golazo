-- Tipo de cancha = jugadores por equipo (Fútbol 5, 6, 7, 8 u 11). Las canchas que ya existían quedan en Fútbol 5.
ALTER TABLE courts ADD COLUMN court_type smallint NOT NULL DEFAULT 5 CHECK (court_type IN (5, 6, 7, 8, 11));

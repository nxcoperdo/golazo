-- Una cancha puede ofrecer varios tipos de juego a la vez (p. ej. Fútbol 5 y Fútbol 7).
-- Se reemplaza court_type (uno) por court_types (lista, ordenada, de 1 a 5 valores permitidos).
ALTER TABLE courts ADD COLUMN court_types smallint[] NOT NULL DEFAULT ARRAY[5]::smallint[];
UPDATE courts SET court_types = ARRAY[court_type];
ALTER TABLE courts ADD CONSTRAINT courts_court_types_check
  CHECK (cardinality(court_types) BETWEEN 1 AND 5 AND court_types <@ ARRAY[5, 6, 7, 8, 11]::smallint[]);
ALTER TABLE courts DROP COLUMN court_type;

-- Prueba de la autorización informada (Ley 1581 de 2012): cuándo y qué versión de los textos aceptó cada usuario.
-- NULL = aún no aceptó (cuentas anteriores o creadas con Google); la app se lo pide antes de seguir.
ALTER TABLE users ADD COLUMN terms_accepted_at timestamptz;
ALTER TABLE users ADD COLUMN terms_version text;

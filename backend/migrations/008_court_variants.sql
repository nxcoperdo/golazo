-- Cada tipo de cancha (Fútbol 5, 7, 11...) pasa a ser una "modalidad" independiente:
-- tiene su propio precio por hora y su propio calendario de reservas.
CREATE TABLE court_variants (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  court_id       uuid NOT NULL REFERENCES courts(id) ON DELETE CASCADE,
  court_type     smallint NOT NULL CHECK (court_type IN (5, 6, 7, 8, 11)),
  price_per_hour integer NOT NULL CHECK (price_per_hour > 0),
  active         boolean NOT NULL DEFAULT true,
  UNIQUE (court_id, court_type)
);

-- Cada tipo que ya tenía la cancha conserva el precio actual.
INSERT INTO court_variants (court_id, court_type, price_per_hour)
SELECT id, unnest(court_types), price_per_hour FROM courts;

-- Las reservas existentes se asignan al tipo más bajo de su cancha.
ALTER TABLE bookings ADD COLUMN variant_id uuid REFERENCES court_variants(id);
UPDATE bookings b SET variant_id = (
  SELECT v.id FROM court_variants v WHERE v.court_id = b.court_id ORDER BY v.court_type LIMIT 1
);
ALTER TABLE bookings ALTER COLUMN variant_id SET NOT NULL;
CREATE INDEX bookings_variant_idx ON bookings (variant_id, start_at);

-- La doble reserva ahora se impide por modalidad, no por cancha completa.
DO $$
DECLARE c text;
BEGIN
  SELECT conname INTO c FROM pg_constraint WHERE conrelid = 'bookings'::regclass AND contype = 'x';
  EXECUTE format('ALTER TABLE bookings DROP CONSTRAINT %I', c);
END $$;

ALTER TABLE bookings ADD CONSTRAINT bookings_variant_no_overlap
  EXCLUDE USING gist (variant_id WITH =, tstzrange(start_at, end_at) WITH &&)
  WHERE (status IN ('pending_payment', 'pending_review', 'confirmed', 'rejected'));

import argon2 from 'argon2';
import pg from 'pg';

/**
 * Crea un administrador (o asciende a uno existente por su correo).
 * Los administradores NO se pueden crear desde la API a propósito.
 *
 * Uso:  npm run create-admin -- correo@dominio.com "Nombre Apellido" "contraseña-larga"
 * Docker: docker compose run --rm migrate node dist/scripts/create-admin.js correo "Nombre" "clave"
 */
const [emailArg, name, password] = process.argv.slice(2);
const url = process.env.DATABASE_URL;

if (!url || !emailArg || !name || !password) {
  console.error('Uso: create-admin <correo> "<nombre>" "<contraseña>"   (requiere DATABASE_URL)');
  process.exit(1);
}
const email = emailArg.trim().toLowerCase();
if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
  console.error('Correo inválido.');
  process.exit(1);
}
if (password.length < 10) {
  console.error('La contraseña de un administrador debe tener al menos 10 caracteres.');
  process.exit(1);
}

const client = new pg.Client({ connectionString: url });
await client.connect();
try {
  const hash = await argon2.hash(password);
  const { rows } = await client.query<{ id: string; created: boolean }>(
    `INSERT INTO users (name, email, password_hash, role) VALUES ($1, $2, $3, 'admin')
     ON CONFLICT (email) DO UPDATE SET role = 'admin', password_hash = EXCLUDED.password_hash,
                                       suspended_at = NULL, deleted_at = NULL
     RETURNING id, (xmax = 0) AS created`,
    [name.trim(), email, hash],
  );
  console.log(`${rows[0]!.created ? 'Administrador creado' : 'Usuario existente ascendido a administrador'}: ${email}`);
} finally {
  await client.end();
}

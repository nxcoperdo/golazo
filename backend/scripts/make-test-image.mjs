// Genera una imagen PNG válida para las pruebas de integración.
// Uso: node scripts/make-test-image.mjs <ruta-de-salida.png>
import sharp from 'sharp';

const out = process.argv[2];
if (!out) {
  console.error('Falta la ruta de salida');
  process.exit(1);
}
await sharp({ create: { width: 64, height: 64, channels: 3, background: '#1b8a3a' } })
  .png()
  .toFile(out);

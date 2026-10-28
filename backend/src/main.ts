import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module.js';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // Las páginas legales son públicas y cuelgan de /legal (sin /v1).
  app.setGlobalPrefix('v1', { exclude: ['legal', 'legal/version', 'legal/:page'] });
  // whitelist descarta campos no declarados; forbidNonWhitelisted los rechaza.
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
  // Detrás de Nginx: confiar en X-Forwarded-For para que el límite de tasa use la IP real.
  app.getHttpAdapter().getInstance().set('trust proxy', 1);
  app.enableShutdownHooks();
  await app.listen(process.env.PORT ?? 3000, '0.0.0.0');
}
await bootstrap();

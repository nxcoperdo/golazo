import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module.js';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // Las páginas legales son públicas y cuelgan de /legal (sin /v1).
  // /open/:target es el puente https → app de los enlaces de los correos.
  app.setGlobalPrefix('v1', { exclude: ['legal', 'legal/version', 'legal/:page', 'open/:target'] });
  // whitelist descarta campos no declarados; forbidNonWhitelisted los rechaza.
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
  // Detrás de Nginx: confiar en X-Forwarded-For para que el límite de tasa use la IP real.
  app.getHttpAdapter().getInstance().set('trust proxy', 1);
  // Documentación OpenAPI (Swagger UI en /docs, JSON en /docs-json): solo si ENABLE_DOCS=1.
  // En producción déjala apagada; para generar docs/openapi.json se enciende en local.
  if (process.env.ENABLE_DOCS === '1') {
    const doc = SwaggerModule.createDocument(
      app,
      new DocumentBuilder()
        .setTitle('Golazo API')
        .setDescription('Reserva de canchas sintéticas. Prefijo /v1; errores { code, message }.')
        .setVersion('1.0')
        .addBearerAuth()
        .build(),
    );
    SwaggerModule.setup('docs', app, doc);
  }
  app.enableShutdownHooks();
  await app.listen(process.env.PORT ?? 3000, '0.0.0.0');
}
await bootstrap();

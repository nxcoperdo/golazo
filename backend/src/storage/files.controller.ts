import { Controller, Get, Header, NotFoundException, Param, StreamableFile } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import { createReadStream, existsSync } from 'node:fs';
import { StorageService } from './storage.service.js';

/** Fotos públicas de canchas. Los comprobantes NO se sirven aquí (son privados). */
@Controller('files')
export class FilesController {
  constructor(private readonly storage: StorageService) {}

  @SkipThrottle()
  @Get('courts/:name')
  @Header('Cache-Control', 'public, max-age=86400, immutable')
  @Header('Content-Type', 'image/jpeg')
  court(@Param('name') name: string): StreamableFile {
    const path = this.storage.pathOf('courts', name);
    if (!path || !existsSync(path)) throw new NotFoundException({ code: 'FILE_NOT_FOUND', message: 'Archivo no encontrado' });
    return new StreamableFile(createReadStream(path));
  }
}

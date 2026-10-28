import { BadRequestException, Injectable, UnsupportedMediaTypeException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { mkdir, unlink, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import sharp from 'sharp';

export type Folder = 'proofs' | 'courts' | 'chat';

/** Tamaño máximo de archivo subido (también lo aplica multer en los controladores). */
export const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;

const NAME_RE = /^[0-9a-f-]{36}\.jpg$/;

/**
 * Guarda imágenes en disco (volumen del VPS). Toda imagen se valida por su
 * contenido real (no por extensión ni Content-Type), se re-codifica y se le
 * quitan los metadatos (EXIF/GPS) antes de guardarse.
 */
@Injectable()
export class StorageService {
  private readonly root: string;

  constructor(config: ConfigService) {
    this.root = resolve(config.get<string>('STORAGE_DIR') ?? './storage');
  }

  async saveImage(buffer: Buffer | undefined, folder: Folder): Promise<string> {
    if (!buffer || buffer.length === 0) {
      throw new BadRequestException({ code: 'NO_FILE', message: 'Falta el archivo' });
    }
    let image = sharp(buffer, { limitInputPixels: 50_000_000, failOn: 'error' });
    let format: string | undefined;
    try {
      format = (await image.metadata()).format;
    } catch {
      throw new UnsupportedMediaTypeException({ code: 'BAD_IMAGE', message: 'El archivo no es una imagen válida' });
    }
    if (!format || !['jpeg', 'png', 'webp'].includes(format)) {
      throw new UnsupportedMediaTypeException({ code: 'BAD_IMAGE', message: 'Solo se aceptan imágenes JPG, PNG o WebP' });
    }
    let out: Buffer;
    try {
      image = image
        .rotate() // aplica la orientación EXIF antes de descartar los metadatos
        .resize({ width: 1600, height: 1600, fit: 'inside', withoutEnlargement: true })
        .flatten({ background: '#ffffff' }) // PNG con transparencia -> fondo blanco
        .jpeg({ quality: 82 });
      out = await image.toBuffer(); // sharp no copia metadatos por defecto
    } catch {
      throw new UnsupportedMediaTypeException({ code: 'BAD_IMAGE', message: 'No se pudo procesar la imagen' });
    }
    const name = `${randomUUID()}.jpg`;
    await mkdir(join(this.root, folder), { recursive: true });
    await writeFile(join(this.root, folder, name), out);
    return name;
  }

  /** Ruta absoluta de un archivo; null si el nombre no tiene el formato esperado (evita path traversal). */
  pathOf(folder: Folder, name: string): string | null {
    return NAME_RE.test(name) ? join(this.root, folder, name) : null;
  }

  async remove(folder: Folder, name: string): Promise<void> {
    const p = this.pathOf(folder, name);
    if (!p) return;
    await unlink(p).catch(() => undefined);
  }
}

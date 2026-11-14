import {
  Body,
  Controller,
  Delete,
  Get,
  Header,
  HttpCode,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  StreamableFile,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Throttle } from '@nestjs/throttler';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { createReadStream, existsSync } from 'node:fs';
import { AuthGuard, CurrentUser, Roles, type AuthUser } from '../auth/auth.guard.js';
import { MAX_UPLOAD_BYTES } from '../storage/storage.service.js';
import { ChatService } from './chat.service.js';
import { MAX_BODY } from './chat.rules.js';

class MessagesQuery {
  /** Último `seq` que ya tiene la app: devuelve solo los mensajes posteriores. */
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) after?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit?: number;
}

class SendDto {
  @IsOptional() @IsString() @MaxLength(MAX_BODY) body?: string;
}

class SubscriptionDto {
  @IsUUID() courtId!: string;
}

class ReportDto {
  @IsOptional() @IsString() @MaxLength(300) reason?: string;
}

class PageQuery {
  @IsOptional() @IsString() @MaxLength(80) search?: string;
  @IsOptional() @IsString() @MaxLength(40) courtId?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset?: number;
}

class ReportsQuery {
  @IsOptional() @IsString() @MaxLength(5) all?: string;
}

const photo = FileInterceptor('image', { limits: { fileSize: MAX_UPLOAD_BYTES, files: 1 } });
/** 30 mensajes por minuto y por IP. */
const SEND_LIMIT = { default: { limit: 30, ttl: 60_000 } };

/** Chat de jugador y dueño (con la cancha de por medio) y chat con soporte. */
@Controller('chat')
@UseGuards(AuthGuard)
export class ChatController {
  constructor(private readonly chat: ChatService) {}

  @Get('threads')
  threads(@CurrentUser() u: AuthUser) {
    return this.chat.listThreads(u);
  }

  /** Abre el chat de una reserva (lo pide el jugador o el dueño de la cancha). */
  @HttpCode(200)
  @Post('bookings/:bookingId')
  forBooking(@CurrentUser() u: AuthUser, @Param('bookingId', ParseUUIDPipe) bookingId: string) {
    return this.chat.openForBooking(u, bookingId);
  }

  @HttpCode(200)
  @Post('support')
  support(@CurrentUser() u: AuthUser) {
    return this.chat.openSupport(u);
  }

  /** Dueño: pide activar o renovar la mensualidad de su cancha; deja el mensaje y la respuesta con las cuentas. */
  @HttpCode(200)
  @Throttle(SEND_LIMIT)
  @Post('support/subscription')
  subscription(@CurrentUser() u: AuthUser, @Body() dto: SubscriptionDto) {
    return this.chat.requestSubscription(u, dto.courtId);
  }

  @Get('threads/:id/messages')
  messages(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Query() q: MessagesQuery) {
    return this.chat.messages(u, id, q.after, q.limit);
  }

  @Throttle(SEND_LIMIT)
  @Post('threads/:id/messages')
  @UseInterceptors(photo)
  send(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: SendDto,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    return this.chat.send(u, id, dto.body, file?.buffer);
  }

  @Get('images/:messageId')
  @Header('Cache-Control', 'private, no-store')
  @Header('Content-Type', 'image/jpeg')
  async image(@CurrentUser() u: AuthUser, @Param('messageId', ParseUUIDPipe) messageId: string): Promise<StreamableFile> {
    const path = await this.chat.imagePath(u, messageId);
    if (!existsSync(path)) throw new NotFoundException({ code: 'MESSAGE_NOT_FOUND', message: 'Foto no encontrada' });
    return new StreamableFile(createReadStream(path));
  }

  @HttpCode(200)
  @Post('messages/:id/report')
  report(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ReportDto) {
    return this.chat.report(u, id, dto.reason);
  }

  @HttpCode(200)
  @Post('blocks/:userId')
  block(@CurrentUser() u: AuthUser, @Param('userId', ParseUUIDPipe) userId: string) {
    return this.chat.block(u, userId);
  }

  @HttpCode(200)
  @Delete('blocks/:userId')
  unblock(@CurrentUser() u: AuthUser, @Param('userId', ParseUUIDPipe) userId: string) {
    return this.chat.unblock(u, userId);
  }
}

/** Soporte y moderación para administradores. */
@Controller('admin/chat')
@UseGuards(AuthGuard)
@Roles('admin')
export class AdminChatController {
  constructor(private readonly chat: ChatService) {}

  @Get('support')
  inbox() {
    return this.chat.supportInbox();
  }

  @Get('threads')
  courtThreads(@Query() q: PageQuery) {
    return this.chat.courtThreads(q);
  }

  /** Lee cualquier hilo (soporte o de cancha). Los de cancha son solo lectura. */
  @Get('threads/:id/messages')
  messages(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Query() q: MessagesQuery) {
    return this.chat.messages(u, id, q.after, q.limit);
  }

  @Throttle(SEND_LIMIT)
  @Post('threads/:id/messages')
  @UseInterceptors(photo)
  reply(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: SendDto,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    return this.chat.send(u, id, dto.body, file?.buffer);
  }

  @Get('reports')
  reports(@Query() q: ReportsQuery) {
    return this.chat.reports(q.all !== 'true');
  }

  @HttpCode(200)
  @Post('reports/:id/resolve')
  resolve(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.chat.resolveReport(u.id, id);
  }

  @HttpCode(200)
  @Post('messages/:id/hide')
  hide(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.chat.hideMessage(u.id, id);
  }
}

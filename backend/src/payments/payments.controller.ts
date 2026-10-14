import {
  Body,
  Controller,
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
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, IsUUID, MaxLength, Max, Min } from 'class-validator';
import { createReadStream, existsSync } from 'node:fs';
import { AuthGuard, CurrentUser, Roles, type AuthUser } from '../auth/auth.guard.js';
import { MAX_UPLOAD_BYTES } from '../storage/storage.service.js';
import { PaymentsService } from './payments.service.js';

const upload = (field: string) => FileInterceptor(field, { limits: { fileSize: MAX_UPLOAD_BYTES, files: 1 } });

class RejectDto {
  @IsOptional() @IsString() @MaxLength(200) reason?: string;
}

class PaymentsQuery {
  @IsOptional() @IsIn(['pending', 'approved', 'rejected']) status?: 'pending' | 'approved' | 'rejected';
  @IsOptional() @IsIn(['booking', 'subscription']) kind?: 'booking' | 'subscription';
  @IsOptional() @IsUUID() courtId?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset?: number;
}

/** El jugador sube el comprobante del anticipo. */
@Controller('bookings')
@UseGuards(AuthGuard)
export class BookingPaymentController {
  constructor(private readonly payments: PaymentsService) {}

  @Post(':id/payment')
  @UseInterceptors(upload('proof'))
  submit(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    return this.payments.submitBookingProof(u.id, id, file?.buffer);
  }
}

/** El dueño revisa los pagos de sus reservas y sube su mensualidad. */
@Controller('owner')
@UseGuards(AuthGuard)
@Roles('owner')
export class OwnerPaymentsController {
  constructor(private readonly payments: PaymentsService) {}

  @Get('payments')
  list(@CurrentUser() u: AuthUser, @Query() q: PaymentsQuery) {
    return this.payments.listForOwner(u.id, q);
  }

  @HttpCode(200)
  @Post('payments/:id/approve')
  approve(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.payments.reviewBookingPayment(u.id, id, true);
  }

  @HttpCode(200)
  @Post('payments/:id/reject')
  reject(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: RejectDto) {
    return this.payments.reviewBookingPayment(u.id, id, false, dto.reason);
  }

  @Post('courts/:id/subscription-payment')
  @UseInterceptors(upload('proof'))
  subscription(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    return this.payments.submitSubscriptionProof(u.id, id, file?.buffer);
  }
}

/** El administrador revisa las mensualidades. */
@Controller('admin/payments')
@UseGuards(AuthGuard)
@Roles('admin')
export class AdminPaymentsController {
  constructor(private readonly payments: PaymentsService) {}

  @Get()
  list(@Query() q: PaymentsQuery) {
    return this.payments.listForAdmin(q);
  }

  @HttpCode(200)
  @Post(':id/approve')
  approve(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.payments.reviewSubscription(u.id, id, true);
  }

  @HttpCode(200)
  @Post(':id/reject')
  reject(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: RejectDto) {
    return this.payments.reviewSubscription(u.id, id, false, dto.reason);
  }
}

/** Descarga privada de un comprobante (quien lo subió, el dueño de la cancha o un admin). */
@Controller('payments')
@UseGuards(AuthGuard)
export class ProofController {
  constructor(private readonly payments: PaymentsService) {}

  @Get(':id/proof')
  @Header('Cache-Control', 'private, no-store')
  @Header('Content-Type', 'image/jpeg')
  async proof(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string): Promise<StreamableFile> {
    const path = await this.payments.proofPath(u.id, u.role, id);
    if (!existsSync(path)) throw new NotFoundException({ code: 'PAYMENT_NOT_FOUND', message: 'Comprobante no encontrado' });
    return new StreamableFile(createReadStream(path));
  }
}

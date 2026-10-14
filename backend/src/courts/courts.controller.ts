import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  Query,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { MAX_UPLOAD_BYTES } from '../storage/storage.service.js';
import { AuthGuard, CurrentUser, Roles, type AuthUser } from '../auth/auth.guard.js';
import {
  AvailabilityQuery,
  CreateCourtDto,
  ListCourtsQuery,
  PaymentMethodsDto,
  UpdateCourtDto,
} from './courts.dto.js';
import { CourtsService } from './courts.service.js';

/** Ciudades con canchas activas. */
@Controller('cities')
export class CitiesController {
  constructor(private readonly courts: CourtsService) {}

  @Get()
  list() {
    return this.courts.cities();
  }
}

/** Rutas públicas: cualquier persona puede ver canchas activas. */
@Controller('courts')
export class CourtsController {
  constructor(private readonly courts: CourtsService) {}

  @Get()
  list(@Query() q: ListCourtsQuery) {
    return this.courts.list(q);
  }

  @Get(':id')
  detail(@Param('id', ParseUUIDPipe) id: string) {
    return this.courts.detail(id);
  }

  @Get(':id/availability')
  availability(@Param('id', ParseUUIDPipe) id: string, @Query() q: AvailabilityQuery) {
    return this.courts.availability(id, q.date);
  }
}

/** Panel del dueño: solo ve y edita sus propias canchas. */
@Controller('owner/courts')
@UseGuards(AuthGuard)
@Roles('owner')
export class OwnerCourtsController {
  constructor(private readonly courts: CourtsService) {}

  @Get()
  list(@CurrentUser() u: AuthUser) {
    return this.courts.listOwn(u.id);
  }

  @Post()
  create(@CurrentUser() u: AuthUser, @Body() dto: CreateCourtDto) {
    return this.courts.create(u.id, dto);
  }

  @Get(':id')
  detail(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.courts.ownerDetail(u.id, id);
  }

  @Patch(':id')
  update(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateCourtDto) {
    return this.courts.update(u.id, id, dto);
  }

  @Post(':id/pause')
  @HttpCode(200)
  pause(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.courts.pause(u.id, id);
  }

  @Post(':id/resume')
  @HttpCode(200)
  resume(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.courts.resume(u.id, id);
  }

  @Put(':id/payment-methods')
  setMethods(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: PaymentMethodsDto) {
    return this.courts.setPaymentMethods(u.id, id, dto.methods);
  }

  @Post(':id/photos')
  @UseInterceptors(FileInterceptor('photo', { limits: { fileSize: MAX_UPLOAD_BYTES, files: 1 } }))
  addPhoto(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @UploadedFile() file: Express.Multer.File | undefined,
  ) {
    return this.courts.addPhoto(u.id, id, file?.buffer);
  }

  @Delete(':id/photos/:photoId')
  removePhoto(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Param('photoId', ParseUUIDPipe) photoId: string,
  ) {
    return this.courts.removePhoto(u.id, id, photoId);
  }
}

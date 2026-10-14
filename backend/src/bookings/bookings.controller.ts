import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, UseGuards } from '@nestjs/common';
import { AuthGuard, CurrentUser, type AuthUser } from '../auth/auth.guard.js';
import { CreateBookingDto } from './bookings.dto.js';
import { BookingsService } from './bookings.service.js';

@Controller('bookings')
@UseGuards(AuthGuard)
export class BookingsController {
  constructor(private readonly bookings: BookingsService) {}

  @Post()
  create(@CurrentUser() u: AuthUser, @Body() dto: CreateBookingDto) {
    return this.bookings.create(u.id, dto);
  }

  @Get('mine')
  mine(@CurrentUser() u: AuthUser) {
    return this.bookings.listMine(u.id);
  }

  @Get(':id')
  detail(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.bookings.detail(u.id, id);
  }

  @HttpCode(200)
  @Post(':id/cancel')
  cancel(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.bookings.cancel(u.id, id);
  }
}

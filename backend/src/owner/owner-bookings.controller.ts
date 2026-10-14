import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsISO8601, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min } from 'class-validator';
import { AuthGuard, CurrentUser, Roles, type AuthUser } from '../auth/auth.guard.js';
import { MAX_HOURS } from '../bookings/booking-policy.js';
import { OwnerBookingsService } from './owner-bookings.service.js';

class BookingsQuery {
  @IsOptional() @IsUUID() courtId?: string;
  @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) from?: string;
  @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) to?: string;
  @IsOptional() @IsIn(['pending_payment', 'pending_review', 'confirmed', 'rejected', 'cancelled']) status?: string;
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(200) limit?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset?: number;
}

class BlockDto {
  @IsISO8601({ strict: true }) startAt!: string;
  @IsInt() @Min(1) @Max(MAX_HOURS) hours!: number;
  @IsOptional() @IsString() @MaxLength(200) note?: string;
}

@Controller('owner')
@UseGuards(AuthGuard)
@Roles('owner')
export class OwnerBookingsController {
  constructor(private readonly bookings: OwnerBookingsService) {}

  @Get('bookings')
  list(@CurrentUser() u: AuthUser, @Query() q: BookingsQuery) {
    return this.bookings.list(u.id, q);
  }

  @Post('courts/:id/blocks')
  block(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: BlockDto) {
    return this.bookings.block(u.id, id, dto);
  }

  @HttpCode(204)
  @Delete('blocks/:id')
  async unblock(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string): Promise<void> {
    await this.bookings.unblock(u.id, id);
  }
}

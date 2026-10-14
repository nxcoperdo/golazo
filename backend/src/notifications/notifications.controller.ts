import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Length, Max, Min } from 'class-validator';
import { AuthGuard, CurrentUser, type AuthUser } from '../auth/auth.guard.js';
import { NotificationsService } from './notifications.service.js';

class ListQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset?: number;
}

class DeviceDto {
  @IsIn(['android', 'ios']) platform!: 'android' | 'ios';
  @IsString() @Length(20, 4096) token!: string;
}

@Controller()
@UseGuards(AuthGuard)
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get('notifications')
  list(@CurrentUser() u: AuthUser, @Query() q: ListQuery) {
    return this.notifications.list(u.id, q.limit ?? 30, q.offset ?? 0);
  }

  @HttpCode(204)
  @Post('notifications/read-all')
  async readAll(@CurrentUser() u: AuthUser): Promise<void> {
    await this.notifications.markAllRead(u.id);
  }

  @HttpCode(204)
  @Post('notifications/:id/read')
  async read(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string): Promise<void> {
    await this.notifications.markRead(u.id, id);
  }

  @HttpCode(204)
  @Post('devices')
  async register(@CurrentUser() u: AuthUser, @Body() dto: DeviceDto): Promise<void> {
    await this.notifications.registerDevice(u.id, dto.platform, dto.token);
  }

  @HttpCode(204)
  @Delete('devices')
  async unregister(@CurrentUser() u: AuthUser, @Body() dto: DeviceDto): Promise<void> {
    await this.notifications.removeDevice(u.id, dto.token);
  }
}

import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { IsOptional, IsUUID, Matches } from 'class-validator';
import { AuthGuard, CurrentUser, Roles, type AuthUser } from '../auth/auth.guard.js';
import { StatsService } from './stats.service.js';

class StatsQuery {
  @IsOptional() @IsUUID() courtId?: string;
  @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) from?: string;
  @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) to?: string;
}

@Controller('owner/stats')
@UseGuards(AuthGuard)
@Roles('owner')
export class StatsController {
  constructor(private readonly stats: StatsService) {}

  @Get()
  get(@CurrentUser() u: AuthUser, @Query() q: StatsQuery) {
    return this.stats.forOwner(u.id, q);
  }
}

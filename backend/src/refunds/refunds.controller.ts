import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { AuthGuard, CurrentUser, Roles, type AuthUser } from '../auth/auth.guard.js';
import { RefundsService } from './refunds.service.js';

class RefundsQuery {
  @IsOptional() @IsIn(['pending', 'done']) status?: 'pending' | 'done';
}

class DoneDto {
  @IsOptional() @IsString() @MaxLength(200) note?: string;
}

/** Devoluciones de anticipos por cancelaciones: el dinero se devuelve fuera de la app, aquí queda el registro. */
@Controller('owner/refunds')
@UseGuards(AuthGuard)
@Roles('owner')
export class RefundsController {
  constructor(private readonly refunds: RefundsService) {}

  @Get()
  list(@CurrentUser() u: AuthUser, @Query() q: RefundsQuery) {
    return this.refunds.listForOwner(u.id, q);
  }

  @HttpCode(200)
  @Post(':id/done')
  done(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: DoneDto) {
    return this.refunds.markDone(u.id, id, dto.note);
  }
}

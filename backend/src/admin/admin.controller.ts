import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Matches, Max, MaxLength, Min } from 'class-validator';
import { AuthGuard, CurrentUser, Roles, type AuthUser } from '../auth/auth.guard.js';
import { JobsService } from '../jobs/jobs.service.js';
import { PaymentsService } from '../payments/payments.service.js';
import { AdminService } from './admin.service.js';

class Page {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset?: number;
}
class UsersQuery extends Page {
  @IsOptional() @IsString() @MaxLength(80) search?: string;
  @IsOptional() @IsIn(['player', 'owner', 'admin']) role?: string;
}
class CourtsQuery extends Page {
  @IsOptional() @IsIn(['pending', 'active', 'suspended']) status?: string;
  @IsOptional() @IsString() @MaxLength(80) search?: string;
}
class TransactionsQuery extends Page {
  @IsOptional() @IsIn(['booking', 'subscription']) kind?: string;
  @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) from?: string;
  @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) to?: string;
}

class ManualSubscriptionDto {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100_000_000) amount?: number;
  @IsOptional() @IsString() @MaxLength(200) note?: string;
}

@Controller('admin')
@UseGuards(AuthGuard)
@Roles('admin')
export class AdminController {
  constructor(
    private readonly admin: AdminService,
    private readonly jobs: JobsService,
    private readonly payments: PaymentsService,
  ) {}

  @Get('users')
  users(@Query() q: UsersQuery) {
    return this.admin.listUsers(q);
  }

  @HttpCode(200)
  @Post('users/:id/suspend')
  suspend(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.admin.suspendUser(u.id, id);
  }

  @HttpCode(200)
  @Post('users/:id/restore')
  restore(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.admin.restoreUser(u.id, id);
  }

  @Delete('users/:id')
  remove(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.admin.deleteUser(u.id, id);
  }

  @Get('courts')
  courts(@Query() q: CourtsQuery) {
    return this.admin.listCourts(q);
  }

  /** Mensualidad cobrada fuera de la app: abre el periodo de 30 días y activa la cancha. */
  @HttpCode(200)
  @Post('courts/:id/subscription-payment')
  registerSubscription(
    @CurrentUser() u: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ManualSubscriptionDto,
  ) {
    return this.payments.registerManualSubscription(u.id, id, dto.amount, dto.note);
  }

  @HttpCode(200)
  @Post('courts/:id/suspend')
  suspendCourt(@Param('id', ParseUUIDPipe) id: string) {
    return this.admin.suspendCourt(id);
  }

  @HttpCode(200)
  @Post('courts/:id/reactivate')
  reactivateCourt(@Param('id', ParseUUIDPipe) id: string) {
    return this.admin.reactivateCourt(id);
  }

  @Get('review-reports')
  reports() {
    return this.admin.listReportedReviews();
  }

  @HttpCode(200)
  @Post('reviews/:id/hide')
  hide(@Param('id', ParseUUIDPipe) id: string) {
    return this.admin.hideReview(id);
  }

  @HttpCode(200)
  @Post('reviews/:id/dismiss')
  dismiss(@Param('id', ParseUUIDPipe) id: string) {
    return this.admin.dismissReports(id);
  }

  @Get('transactions')
  transactions(@Query() q: TransactionsQuery) {
    return this.admin.transactions(q);
  }

  @Get('metrics')
  metrics() {
    return this.admin.metrics();
  }

  /** Ejecuta ahora las tareas programadas (vencimientos y limpieza). */
  @HttpCode(200)
  @Post('jobs/run')
  runJobs() {
    return this.jobs.runAll();
  }
}

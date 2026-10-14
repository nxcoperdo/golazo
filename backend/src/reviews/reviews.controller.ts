import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query, UseGuards } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { AuthGuard, CurrentUser, type AuthUser } from '../auth/auth.guard.js';
import { ReviewsService } from './reviews.service.js';

class CreateReviewDto {
  @IsInt() @Min(1) @Max(5) stars!: number;
  @IsOptional() @IsString() @MaxLength(1000) body?: string;
}

class ReportDto {
  @IsOptional() @IsString() @MaxLength(300) reason?: string;
}

class PageQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50) limit?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset?: number;
}

@Controller()
export class ReviewsController {
  constructor(private readonly reviews: ReviewsService) {}

  @Get('courts/:id/reviews')
  list(@Param('id', ParseUUIDPipe) id: string, @Query() q: PageQuery) {
    return this.reviews.listForCourt(id, q.limit ?? 20, q.offset ?? 0);
  }

  @UseGuards(AuthGuard)
  @Post('bookings/:id/review')
  create(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: CreateReviewDto) {
    return this.reviews.create(u.id, id, dto.stars, dto.body);
  }

  @UseGuards(AuthGuard)
  @HttpCode(204)
  @Post('reviews/:id/report')
  async report(@CurrentUser() u: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ReportDto): Promise<void> {
    await this.reviews.report(u.id, id, dto.reason);
  }
}

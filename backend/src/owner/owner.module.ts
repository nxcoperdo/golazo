import { Module } from '@nestjs/common';
import { OwnerBookingsController } from './owner-bookings.controller.js';
import { OwnerBookingsService } from './owner-bookings.service.js';
import { StatsController } from './stats.controller.js';
import { StatsService } from './stats.service.js';

@Module({ controllers: [StatsController, OwnerBookingsController], providers: [StatsService, OwnerBookingsService] })
export class OwnerModule {}

import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AdminModule } from './admin/admin.module.js';
import { AuthModule } from './auth/auth.module.js';
import { BookingsModule } from './bookings/bookings.module.js';
import { ChatModule } from './chat/chat.module.js';
import { CourtsModule } from './courts/courts.module.js';
import { DbModule } from './db/db.module.js';
import { HealthController } from './health/health.controller.js';
import { JobsModule } from './jobs/jobs.module.js';
import { LegalModule } from './legal/legal.module.js';
import { LinksModule } from './links/links.module.js';
import { NotificationsModule } from './notifications/notifications.module.js';
import { OwnerModule } from './owner/owner.module.js';
import { PaymentsModule } from './payments/payments.module.js';
import { PlatformModule } from './platform/platform.module.js';
import { RefundsModule } from './refunds/refunds.module.js';
import { ReviewsModule } from './reviews/reviews.module.js';
import { StorageModule } from './storage/storage.module.js';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    // Límite general: 120 peticiones por minuto y por IP.
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 120 }]),
    DbModule,
    StorageModule,
    NotificationsModule,
    JobsModule,
    AuthModule,
    CourtsModule,
    BookingsModule,
    PaymentsModule,
    RefundsModule,
    ChatModule,
    ReviewsModule,
    OwnerModule,
    PlatformModule,
    LegalModule,
    LinksModule,
    AdminModule,
  ],
  controllers: [HealthController],
  providers: [{ provide: APP_GUARD, useClass: ThrottlerGuard }],
})
export class AppModule {}

import { Global, Module } from '@nestjs/common';
import { MailerService } from './mailer.service.js';
import { NotificationsController } from './notifications.controller.js';
import { NotificationsService } from './notifications.service.js';
import { PushService } from './push.service.js';

@Global()
@Module({
  controllers: [NotificationsController],
  providers: [NotificationsService, PushService, MailerService],
  exports: [NotificationsService, MailerService, PushService],
})
export class NotificationsModule {}

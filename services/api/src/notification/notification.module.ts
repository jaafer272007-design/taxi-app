import { Global, Module } from '@nestjs/common';
import { NotificationService } from './notification.service';
import { DevicesController } from './devices.controller';
import { NotificationsController } from './notifications.controller';

// Global so any module can inject NotificationService to fire event hooks.
@Global()
@Module({
  controllers: [DevicesController, NotificationsController],
  providers: [NotificationService],
  exports: [NotificationService],
})
export class NotificationModule {}

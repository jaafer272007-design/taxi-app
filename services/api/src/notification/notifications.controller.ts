import { Controller, Get, HttpCode, HttpStatus, Param, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { NotificationService } from './notification.service';

/**
 * The in-app notification centre.
 *
 * Every route is scoped to the caller — `userId` comes from the JWT, never
 * from the request — so there is no way to ask for somebody else's list. The
 * one route that takes an id ([markRead]) checks ownership explicitly.
 */
@Controller('notifications')
@UseGuards(JwtAuthGuard)
export class NotificationsController {
  constructor(private readonly notifications: NotificationService) {}

  /** The list AND the unread count — one round trip, always consistent. */
  @Get()
  list(@CurrentUser('id') userId: string) {
    return this.notifications.list(userId);
  }

  /**
   * The badge alone.
   *
   * A separate route because the badge is polled from every screen while the
   * list is only read when the centre is open — making that poll fetch fifty
   * rows to render one number would be paying for the list everywhere.
   */
  @Get('unread-count')
  unreadCount(@CurrentUser('id') userId: string) {
    return this.notifications.unreadCount(userId);
  }

  @Post('read-all')
  @HttpCode(HttpStatus.OK)
  markAllRead(@CurrentUser('id') userId: string) {
    return this.notifications.markAllRead(userId);
  }

  // Declared AFTER 'read-all' so that literal path can never be swallowed by
  // the `:id` wildcard.
  @Post(':id/read')
  @HttpCode(HttpStatus.OK)
  markRead(@CurrentUser('id') userId: string, @Param('id') id: string) {
    return this.notifications.markRead(userId, id);
  }
}

import { Module } from '@nestjs/common';
import { BookingModule } from '../booking/booking.module';
import { DriverModule } from '../driver/driver.module';
import { PoolController } from './pool.controller';
import { PoolExpiryJob } from './pool-expiry.job';
import { PoolService } from './pool.service';
import { SeatRequestController } from './seat-request.controller';
import { SeatRequestService } from './seat-request.service';

/**
 * Phase 2 — Stage 1: التجميع.
 *
 * `BookingModule` مستورد من أجل `NoShowService`: الإيقاف الذي يمنع الحجز يجب
 * أن يمنع **الطلب** أيضاً، وإلا دخل راكب موقوف تجمّعاً واستُلم على أساس
 * مقاعده. نفس القاعدة، ومصدر واحد لها.
 *
 * `DriverModule` من أجل `assertApprovedDriver` — اللوحة والاستلام واقتراح
 * الرفع كلها للسائق المعتمَد وحده.
 *
 * لا استيراد لـ`TripModule`: الاستلام يكتب صفّ `Trip` داخل معاملته الخاصة،
 * لأن `TripService.createTrip` مسارٌ يبدأه سائق بشروط أخرى تماماً (نطاق
 * السعر، «الآن»، سعة المركبة مقابل مقاعد طلبها هو) — ولأن نداءً خارج
 * المعاملة كان سينقض ذرّية الاستلام. الناتج مع ذلك صفوف عادية تماماً، وهذا
 * ما يهمّ.
 */
@Module({
  imports: [DriverModule, BookingModule],
  controllers: [SeatRequestController, PoolController],
  providers: [SeatRequestService, PoolService, PoolExpiryJob],
  exports: [SeatRequestService, PoolService],
})
export class PoolModule {}

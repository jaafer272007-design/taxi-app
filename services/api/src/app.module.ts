import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { validateEnv } from './config/env.validation';
import { PrismaModule } from './prisma/prisma.module';
import { RedisModule } from './redis/redis.module';
import { AuthModule } from './auth/auth.module';
import { DriverModule } from './driver/driver.module';
import { AdminModule } from './admin/admin.module';
import { DocumentsModule } from './documents/documents.module';
import { CorridorModule } from './corridor/corridor.module';
import { TripModule } from './trip/trip.module';
import { BookingModule } from './booking/booking.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validate: validateEnv,
    }),
    PrismaModule,
    RedisModule,
    AuthModule,
    DriverModule,
    AdminModule,
    DocumentsModule,
    CorridorModule,
    TripModule,
    BookingModule,
  ],
})
export class AppModule {}

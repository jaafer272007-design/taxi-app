import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { AdminAuthController } from './admin-auth.controller';
import { AdminAuthService } from './admin-auth.service';
import { AdminUsersController } from './admin-users.controller';
import { AdminUsersService } from './admin-users.service';
import { LoginThrottleService } from './login-throttle.service';
import { PasswordService } from './password.service';

/**
 * Username + password authentication for admins, and the SUPER_ADMIN-only
 * account management that goes with it. Kept as its own module rather than
 * folded into `auth`, mirroring the schema split: nothing in the rider/driver
 * OTP path should be able to reach a password hash.
 */
@Module({
  imports: [
    PassportModule,
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.getOrThrow<string>('JWT_SECRET'),
        // Admin sessions are shorter than the 30-day rider default: an admin
        // token authorises pricing and driver approval, and it lives in a
        // browser rather than in Android secure storage.
        signOptions: {
          expiresIn: (config.get<string>('ADMIN_JWT_EXPIRES_IN') || '12h') as any,
        },
      }),
    }),
  ],
  controllers: [AdminAuthController, AdminUsersController],
  providers: [AdminAuthService, AdminUsersService, PasswordService, LoginThrottleService],
})
export class AdminAuthModule {}

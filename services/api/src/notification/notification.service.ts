import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as admin from 'firebase-admin';
import { PrismaService } from '../prisma/prisma.service';
import { RegisterDeviceDto } from './dto/register-device.dto';

export interface NotificationPayload {
  title: string;
  body: string;
  data?: Record<string, string | number | null | undefined>;
}

@Injectable()
export class NotificationService {
  private readonly logger = new Logger(NotificationService.name);
  private readonly configured: boolean;

  constructor(
    private readonly prisma: PrismaService,
    config: ConfigService,
  ) {
    const projectId = config.get<string>('FIREBASE_PROJECT_ID');
    const clientEmail = config.get<string>('FIREBASE_CLIENT_EMAIL');
    const privateKey = config.get<string>('FIREBASE_PRIVATE_KEY');
    this.configured = Boolean(projectId && clientEmail && privateKey);

    if (this.configured && admin.apps.length === 0) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId,
          clientEmail,
          // Env-encoded newlines → real newlines.
          privateKey: (privateKey as string).replace(/\\n/g, '\n'),
        }),
      });
    }
  }

  /** Upsert a device token for the user (a user may have several devices). */
  registerDevice(userId: string, dto: RegisterDeviceDto) {
    return this.prisma.deviceToken.upsert({
      where: { token: dto.token },
      update: { userId, platform: dto.platform },
      create: { userId, token: dto.token, platform: dto.platform },
    });
  }

  /** Remove a device token on logout (only the caller's own token). */
  async removeDevice(userId: string, token: string) {
    const res = await this.prisma.deviceToken.deleteMany({ where: { token, userId } });
    return { removed: res.count };
  }

  /**
   * Push a notification to all of a user's devices. NEVER throws — these fire
   * AFTER the DB transaction commits, so a delivery failure must not affect the
   * caller. Invalid/expired tokens are pruned. If FCM isn't configured, logs a
   * DEV-ONLY line instead (not a release blocker).
   */
  async send(userId: string, payload: NotificationPayload): Promise<void> {
    try {
      const devices = await this.prisma.deviceToken.findMany({ where: { userId } });
      if (devices.length === 0) return;

      if (!this.configured) {
        this.logger.log(
          `[DEV-ONLY] push → user ${userId} (${devices.length} device[s]): ${payload.title} — ${payload.body}`,
        );
        return;
      }

      const tokens = devices.map((d) => d.token);
      const invalid = await this.deliverToTokens(tokens, payload);
      if (invalid.length > 0) {
        await this.prisma.deviceToken.deleteMany({ where: { token: { in: invalid } } });
        this.logger.log(`Pruned ${invalid.length} invalid device token(s).`);
      }
    } catch (err) {
      this.logger.error(`Notification send failed for ${userId}: ${(err as Error).message}`);
    }
  }

  /** Deliver via FCM; returns invalid/expired tokens that should be pruned. */
  protected async deliverToTokens(tokens: string[], payload: NotificationPayload): Promise<string[]> {
    const res = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: payload.title, body: payload.body },
      data: this.stringifyData(payload.data),
    });

    const invalid: string[] = [];
    res.responses.forEach((r, i) => {
      if (!r.success) {
        const code = r.error?.code;
        if (
          code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token' ||
          code === 'messaging/invalid-argument'
        ) {
          invalid.push(tokens[i]);
        }
      }
    });
    return invalid;
  }

  private stringifyData(data?: NotificationPayload['data']): Record<string, string> {
    const out: Record<string, string> = {};
    if (data) {
      for (const [k, v] of Object.entries(data)) {
        if (v !== undefined && v !== null) out[k] = String(v);
      }
    }
    return out;
  }
}

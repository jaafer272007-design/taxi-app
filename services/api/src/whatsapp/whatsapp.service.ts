import { Injectable, Logger, InternalServerErrorException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * Sends OTP codes via the WhatsApp Business Cloud API (reuse the Sehat Beitak
 * setup). The expected template is an authentication/utility template whose
 * body has a single `{{1}}` placeholder that receives the code.
 *
 * DEV fallback: if any of PHONE_NUMBER_ID / ACCESS_TOKEN / OTP_TEMPLATE is
 * missing, the code is logged to the console instead of being sent. That mode
 * is DEV-ONLY and a HARD release blocker — it is refused under
 * NODE_ENV=production.
 */
@Injectable()
export class WhatsappService {
  private readonly logger = new Logger(WhatsappService.name);

  private readonly phoneNumberId?: string;
  private readonly accessToken?: string;
  private readonly template?: string;
  private readonly templateLang: string;
  private readonly apiVersion: string;
  private readonly isProduction: boolean;

  constructor(config: ConfigService) {
    this.phoneNumberId = config.get<string>('WHATSAPP_PHONE_NUMBER_ID') || undefined;
    this.accessToken = config.get<string>('WHATSAPP_ACCESS_TOKEN') || undefined;
    this.template = config.get<string>('WHATSAPP_OTP_TEMPLATE') || undefined;
    this.templateLang = config.get<string>('WHATSAPP_TEMPLATE_LANG') || 'ar';
    this.apiVersion = config.get<string>('WHATSAPP_API_VERSION') || 'v21.0';
    this.isProduction = config.get<string>('NODE_ENV') === 'production';

    if (!this.isConfigured() && this.isProduction) {
      // Fail fast: never allow the dev console fallback in production.
      throw new Error(
        'WhatsApp Business Cloud API is not configured but NODE_ENV=production. ' +
          'OTP-to-console is a DEV-ONLY release blocker and is refused in production.',
      );
    }
  }

  isConfigured(): boolean {
    return Boolean(this.phoneNumberId && this.accessToken && this.template);
  }

  async sendOtp(phoneE164: string, code: string): Promise<void> {
    if (!this.isConfigured()) {
      // ── DEV-ONLY fallback ─────────────────────────────────────────────
      this.logger.warn(
        `[DEV-ONLY][RELEASE BLOCKER] WhatsApp not configured — OTP for ${phoneE164} is ${code}. ` +
          `Never ship this: configure WHATSAPP_* env vars before release.`,
      );
      return;
    }

    // WhatsApp Cloud API expects the phone WITHOUT the leading '+'.
    const to = phoneE164.replace(/^\+/, '');
    const url = `https://graph.facebook.com/${this.apiVersion}/${this.phoneNumberId}/messages`;

    const body = {
      messaging_product: 'whatsapp',
      to,
      type: 'template',
      template: {
        name: this.template,
        language: { code: this.templateLang },
        components: [
          {
            type: 'body',
            parameters: [{ type: 'text', text: code }],
          },
        ],
      },
    };

    let res: Response;
    try {
      res = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });
    } catch (err) {
      this.logger.error(`WhatsApp request failed: ${(err as Error).message}`);
      throw new InternalServerErrorException('تعذّر إرسال رمز التحقق. حاول مرة أخرى.');
    }

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      this.logger.error(`WhatsApp API ${res.status}: ${text}`);
      throw new InternalServerErrorException('تعذّر إرسال رمز التحقق. حاول مرة أخرى.');
    }
  }
}

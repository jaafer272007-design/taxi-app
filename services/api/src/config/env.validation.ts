/**
 * Minimal env validation — fails fast at boot if a required var is missing.
 * WhatsApp vars are intentionally NOT required here: when absent, the app
 * runs in DEV-ONLY OTP-to-console mode (a hard release blocker enforced in
 * WhatsappService, which refuses that mode under NODE_ENV=production).
 */
const REQUIRED = ['DATABASE_URL', 'REDIS_URL', 'JWT_SECRET'] as const;

export function validateEnv(config: Record<string, unknown>): Record<string, unknown> {
  const missing = REQUIRED.filter((key) => {
    const v = config[key];
    return v === undefined || v === null || String(v).trim() === '';
  });

  if (missing.length > 0) {
    throw new Error(
      `Missing required environment variables: ${missing.join(', ')}. ` +
        `Copy services/api/.env.example to .env and fill them in.`,
    );
  }

  if (config.NODE_ENV === 'production' && String(config.JWT_SECRET).includes('change-me')) {
    throw new Error('JWT_SECRET is still the example placeholder — set a strong secret in production.');
  }

  return config;
}

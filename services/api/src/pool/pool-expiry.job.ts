import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PoolService } from './pool.service';

/**
 * يكنس التجمّعات المنتهية والمهل المستحقّة — نفس شكل `TripExpiryJob` وللسبب
 * نفسه.
 *
 * جدولة لا كنس على مسار القراءة: لوحة السائق أكثر الطلبات سخونة ولا شأن لها
 * بالكتابة، و«يُنظَّف متى صادف أن نظر أحد» يعني أن تجمّعاً لا ينظر إليه أحد
 * يبقى معلّقاً للأبد — وهو بالضبط ما يجب منعه هنا: الراكب لا يُخبَر أن طلبه
 * سقط، فيبقى ينتظر.
 *
 * خلافاً لكنس الرحلات، هذه المهمّة **تخبر مستخدمين**، فهي ليست ترتيباً
 * فحسب. ومع ذلك تبقى الرؤية مستقلة عنها: اللوحة والاستلام يفلتران بالنافذة
 * بأنفسهما.
 */
@Injectable()
export class PoolExpiryJob {
  private readonly logger = new Logger(PoolExpiryJob.name);

  constructor(private readonly pools: PoolService) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async sweep(): Promise<void> {
    try {
      const expired = await this.pools.expireUnclaimedPools();
      if (expired) this.logger.log(`Expired ${expired} unclaimed pool(s)`);
    } catch (err) {
      // فشل الكنس لا يُسقط العملية — التكّة التالية تعيد المحاولة.
      this.logger.error(`Pool expiry sweep failed: ${(err as Error).message}`);
    }

    try {
      const resolved = await this.pools.resolveDueRaises();
      if (resolved) this.logger.log(`Resolved ${resolved} due price raise(s)`);
    } catch (err) {
      // منفصلة عن الكنس أعلاه عمداً: انتهاء مهلة رفع يقرّر مَن يسافر ومَن
      // يُطلق، فلا يجوز أن يمنعه فشلُ تنظيفٍ لا علاقة له به.
      this.logger.error(`Pool raise sweep failed: ${(err as Error).message}`);
    }
  }
}

import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import {
  BlockState,
  NoShowPolicy,
  blockedMessage,
  evaluateBlock,
  readNoShowPolicy,
  windowStart,
} from './no-show-policy';

/**
 * سجل عدم الحضور: الكتابة، والعدّ، والإلغاء (التظلّم).
 *
 * القاعدة نفسها تعيش في `no-show-policy.ts` بلا قاعدة بيانات ولا Nest، وهذه
 * الخدمة هي الجسر إليها: تجلب الوقائع غير الملغاة داخل النافذة وتسلّمها
 * للقاعدة. هذا الفصل مقصود — القاعدة تُختبر بأرقام، والخدمة تُختبر بصفوف.
 */
@Injectable()
export class NoShowService {
  readonly policy: NoShowPolicy;

  constructor(
    private readonly prisma: PrismaService,
    config: ConfigService,
  ) {
    this.policy = readNoShowPolicy((key) => config.get<string>(key));
  }

  /**
   * سجّل واقعة عدم حضور.
   *
   * تأخذ `tx` لأن نداءها الوحيد يجري **داخل** معاملة تأشير الحجز NO_SHOW:
   * صفّ بلا حالة، أو حالة بلا صف، كلاهما يفسد العدّ لاحقاً بلا أثر يدلّ عليه.
   *
   * `bookingId` فريد في المخطط، فإعادة التأشير لا تضاعف الواقعة.
   */
  record(
    tx: Prisma.TransactionClient,
    input: { riderId: string; tripId: string; bookingId: string; seatCount: number },
  ) {
    return tx.noShowRecord.create({ data: input });
  }

  /** الوقائع غير الملغاة داخل النافذة — ما يحتاجه العدّ، لا أكثر. */
  private activeInWindow(riderId: string, now: Date) {
    return this.prisma.noShowRecord.findMany({
      where: {
        riderId,
        voidedAt: null,
        createdAt: { gt: windowStart(this.policy, now) },
      },
      select: { createdAt: true },
    });
  }

  /** هل هذا الراكب موقوف الآن، وحتى متى؟ */
  async blockStateFor(riderId: string, now: Date = new Date()): Promise<BlockState> {
    return evaluateBlock(await this.activeInWindow(riderId, now), this.policy, now);
  }

  /** الرسالة العربية المرافقة للرفض. */
  message(state: BlockState): string {
    return blockedMessage(state, this.policy);
  }

  /**
   * عدد الوقائع غير الملغاة (داخل النافذة) لكل راكب من مجموعة.
   *
   * استعلام واحد لقائمة حجوزات رحلة كاملة: الشاشة تعرض عدّاداً بجانب كل
   * راكب، و«استعلام لكل صف» على شاشة يفتحها السائق قبل كل رحلة ثمنها حقيقي.
   */
  async countsFor(riderIds: string[], now: Date = new Date()): Promise<Map<string, number>> {
    if (riderIds.length === 0) return new Map();
    const rows = await this.prisma.noShowRecord.groupBy({
      by: ['riderId'],
      where: {
        riderId: { in: [...new Set(riderIds)] },
        voidedAt: null,
        createdAt: { gt: windowStart(this.policy, now) },
      },
      _count: { _all: true },
    });
    return new Map(rows.map((r) => [r.riderId, r._count._all]));
  }

  /** تاريخ راكب كامل للوحة — بما فيه الملغى، لأن السجل هو نقطة المراجعة. */
  history(riderId: string) {
    return this.prisma.noShowRecord.findMany({
      where: { riderId },
      orderBy: { createdAt: 'desc' },
    });
  }

  /**
   * ألغِ واقعة (مسار التظلّم).
   *
   * إلغاء **ناعم**: الصف يبقى ومعه السبب ومَن ألغى. حذفه كان سيمحو الدليل
   * على أن أحداً راجع الحالة أصلاً، وهذا بالضبط ما تحتاجه المراجعة لاحقاً.
   * إعادة إلغاء واقعة ملغاة لا تفعل شيئاً (`voidedAt: null` في الشرط).
   */
  async void(id: string, adminId: string, reason: string) {
    const changed = await this.prisma.noShowRecord.updateMany({
      where: { id, voidedAt: null },
      data: { voidedAt: new Date(), voidedBy: adminId, voidReason: reason },
    });
    return { voided: changed.count === 1 };
  }

  /**
   * ارفع إيقاف راكب: ألغِ كل وقائعه غير الملغاة داخل النافذة دفعةً واحدة.
   *
   * رفع الإيقاف بلا إلغاء الوقائع كان سيعيد الإيقاف فوراً عند أول تقييم —
   * الوقائع هي مصدر الحالة، فرفعها لازم يمرّ منها. الوقائع خارج النافذة
   * تبقى: تاريخ الراكب لا يُمحى، هو فقط يخرج من العدّ.
   */
  async liftBlock(riderId: string, adminId: string, reason: string, now: Date = new Date()) {
    const changed = await this.prisma.noShowRecord.updateMany({
      where: {
        riderId,
        voidedAt: null,
        createdAt: { gt: windowStart(this.policy, now) },
      },
      data: { voidedAt: now, voidedBy: adminId, voidReason: reason },
    });
    return { voided: changed.count };
  }

  /**
   * الركّاب الموقوفون الآن.
   *
   * يجمع العدّاد في قاعدة البيانات ثم يقيّم القاعدة في الذاكرة للمرشّحين
   * فقط: «متى تنتهي المدة» تحتاج آخر واقعة لكل راكب، وهو ما لا يعطيه
   * `groupBy` بضربة واحدة، لكن عدد مَن تجاوزوا العتبة صغير بطبيعته.
   */
  async blockedRiders(now: Date = new Date()) {
    const candidates = await this.prisma.noShowRecord.groupBy({
      by: ['riderId'],
      where: { voidedAt: null, createdAt: { gt: windowStart(this.policy, now) } },
      _count: { _all: true },
      having: { riderId: { _count: { gte: this.policy.threshold } } },
    });
    if (candidates.length === 0) return [];

    const riderIds = candidates.map((c) => c.riderId);
    const [records, riders] = await Promise.all([
      this.prisma.noShowRecord.findMany({
        where: {
          riderId: { in: riderIds },
          voidedAt: null,
          createdAt: { gt: windowStart(this.policy, now) },
        },
        select: { riderId: true, createdAt: true },
      }),
      this.prisma.user.findMany({
        where: { id: { in: riderIds } },
        select: { id: true, name: true, phone: true },
      }),
    ]);

    const byRider = new Map<string, { createdAt: Date }[]>();
    for (const r of records) {
      (byRider.get(r.riderId) ?? byRider.set(r.riderId, []).get(r.riderId)!).push(r);
    }
    const riderById = new Map(riders.map((r) => [r.id, r]));

    return riderIds
      .map((id) => ({
        rider: riderById.get(id) ?? null,
        state: evaluateBlock(byRider.get(id) ?? [], this.policy, now),
      }))
      .filter((row) => row.state.blocked)
      .sort(
        (a, b) =>
          (b.state.blockedUntil?.getTime() ?? 0) - (a.state.blockedUntil?.getTime() ?? 0),
      );
  }
}

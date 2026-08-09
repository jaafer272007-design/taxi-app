import { Injectable } from '@nestjs/common';
import { AdminActionType, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/** Who did it — resolved from the JWT, never sent by the client. */
export interface ActingAdmin {
  id: string;
  username: string;
}

export type AuditEntityType = 'BOOKING' | 'TRIP' | 'DRIVER' | 'RIDER';

export interface ListActionsFilter {
  adminId?: string;
  entityType?: string;
  entityId?: string;
  take?: number;
}

/**
 * سجل تدخّلات الأدمن.
 *
 * ## لماذا كل تدخّل يمرّ من هنا
 *
 * قبل هذا، التدخّل الوحيد كان كتابة SQL بـ psql — صار ثلاث مرات أثناء
 * الاختبار. ذاك لا يتوسّع أبعد من شخص واحد، والأسوأ أنه **لا يترك أثراً**:
 * لا مَن، ولا لماذا، ولا متى.
 *
 * ## الترتيب: نفّذ ثم سجّل
 *
 * الفعل نفسه يجري أولاً عبر خدمته الأصلية، والسجل يُكتب **بعد نجاحه**. لو
 * كُتب السجل أولاً لامتلأ بأفعال لم تحصل (رفضتها آلة الحالة مثلاً)، وسجل
 * تدقيق يكذب أسوأ من غيابه.
 *
 * العكس — نجاح الفعل وفشل كتابة السجل — ممكن نظرياً، لكنه الاتجاه الصحيح
 * للخطأ: الحالة سليمة والأثر ناقص، بدل حالة سليمة وأثر يصف فعلاً آخر.
 */
@Injectable()
export class AdminAuditService {
  constructor(private readonly prisma: PrismaService) {}

  record(
    admin: ActingAdmin,
    input: {
      type: AdminActionType;
      entityType: AuditEntityType;
      entityId: string;
      reason: string;
    },
  ) {
    return this.prisma.adminAction.create({
      data: {
        adminId: admin.id,
        // Copied, not joined — the row has to stay readable after the account
        // is gone, which is exactly when an incident gets reviewed.
        adminUsername: admin.username,
        type: input.type,
        entityType: input.entityType,
        entityId: input.entityId,
        reason: input.reason.trim(),
      },
    });
  }

  /**
   * The log, newest first.
   *
   * Two filters and no more, because there are only two questions anyone asks
   * of an audit log: "what did this admin do" and "what happened to this
   * thing". A free-text search over reasons would invite reading the log as
   * prose rather than as a record.
   */
  list(filter: ListActionsFilter = {}) {
    const where: Prisma.AdminActionWhereInput = {};
    if (filter.adminId) where.adminId = filter.adminId;
    if (filter.entityType) where.entityType = filter.entityType;
    if (filter.entityId) where.entityId = filter.entityId;

    return this.prisma.adminAction.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      // Bounded: the panel paginates by narrowing, not by scrolling forever.
      take: Math.min(filter.take ?? 100, 200),
    });
  }

  /** Distinct admins that appear in the log, for the filter dropdown. */
  async actingAdmins(): Promise<{ adminId: string; adminUsername: string }[]> {
    const rows = await this.prisma.adminAction.groupBy({
      by: ['adminId', 'adminUsername'],
      orderBy: { adminUsername: 'asc' },
    });
    return rows.map((r) => ({ adminId: r.adminId, adminUsername: r.adminUsername }));
  }
}

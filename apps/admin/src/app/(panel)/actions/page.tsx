import { TriangleAlert } from "lucide-react";

import { requireAdmin } from "@/lib/admin-session";
import { ApiError, listActionAdmins, listAdminActions } from "@/lib/backend";
import type { AdminAction } from "@/lib/types";
import { ActionsClient } from "./actions-client";

export const metadata = { title: "سجل الإجراءات — تكسي" };

/**
 * سجل الإجراءات.
 *
 * ## ليش هذا السجل موجود
 *
 * التدخّل الإداري يغيّر رحلة شخص أو دخل سائق. قبل هذه الأدوات كان يُنفَّذ
 * بكتابة SQL: بلا مَن، ولا لماذا، ولا متى. والحالة التي يُسأل فيها «مَن ألغى
 * هذا الحجز؟» تأتي دائماً بعد أسابيع، حين لا يتذكّر أحد.
 *
 * الفلترتان هما السؤالان الوحيدان اللذان يُطرحان فعلاً: «شنو سوّى هذا
 * الأدمن» و«شنو صار لهذا الكيان». بحث نصّي حرّ بالأسباب كان سيدعو لقراءة
 * السجل كنثر بدل قراءته كسجل.
 */
export default async function ActionsPage({
  searchParams,
}: {
  searchParams: Promise<{ adminId?: string; entityType?: string; entityId?: string }>;
}) {
  const { token } = await requireAdmin();
  const { adminId, entityType, entityId } = await searchParams;

  let actions: AdminAction[] | null = null;
  let admins: { adminId: string; adminUsername: string }[] = [];
  let errorMessage: string | null = null;

  try {
    [actions, admins] = await Promise.all([
      listAdminActions(token, { adminId, entityType, entityId }),
      listActionAdmins(token),
    ]);
  } catch (err) {
    errorMessage = err instanceof ApiError ? err.message : "حدث خطأ غير متوقع.";
  }

  if (!actions) {
    return (
      <div className="flex flex-col items-center gap-3 rounded-xl border border-dashed border-border py-16 text-center">
        <div className="flex size-14 items-center justify-center rounded-full bg-destructive-tonal text-destructive">
          <TriangleAlert className="size-6" />
        </div>
        <p className="font-medium">{errorMessage}</p>
        <p className="text-sm text-muted-foreground">أعد تحميل الصفحة للمحاولة مرة أخرى.</p>
      </div>
    );
  }

  return (
    <ActionsClient
      actions={actions}
      admins={admins}
      selected={{ adminId: adminId ?? "", entityType: entityType ?? "" }}
    />
  );
}

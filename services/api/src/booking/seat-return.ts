import { BookingStatus, Prisma, Trip, TripStatus } from '@prisma/client';
import { isCatchable } from '../trip/trip-window';

/**
 * إرجاع مقعد إلى رحلته — **التنفيذ الوحيد**.
 *
 * ## ليش مستخرَجة
 *
 * ثلاث خطوات لا تنفصل: قلبُ الحجز `CONFIRMED → CANCELLED` بحارس سباق، وزيادة
 * `seatsAvailable`، وإعادة فتح رحلة ممتلئة ما زالت قابلة للّحاق. أي منادٍ
 * ينسى واحدة منها يكسر ضمانة صفرية-الحجز-الزائد بصمت، على المسار الذي
 * يُستعمل غالباً **بعد أن يكون شيء قد ساء أصلاً**.
 *
 * كان لها منادٍ واحد (إلغاء الراكب/الأدمن). ثم جاء Phase 2 بمنادٍ ثانٍ:
 * راكبٌ يُطلَق لأنه رفض رفع السعر. الحالتان مختلفتان تماماً في المعنى
 * والإشعارات، ومتطابقتان تماماً في **حساب المقاعد** — وهذا بالضبط ما يجب
 * ألّا يُنسخ.
 *
 * ## تأخذ `tx`، ولا تفتح واحدة
 *
 * لأن نداءها في Phase 2 يجري داخل معاملة تحسم رفع السعر كله: إطلاق نصف
 * الركّاب ثم الفشل يترك مقاعد غير محسوبة وسعراً بين اثنين.
 *
 * ## لا تُشعِر أحداً
 *
 * مَن يُشعَر وبأي نصّ يختلف بين المنادِيَين — إلغاء الراكب يخبر السائق أن
 * مقعداً تحرّر، وإطلاقُ رافضٍ للرفع يخبره أن اقتراحه كلّفه راكباً. الإشعار
 * يبقى عند المنادي، **بعد** الـcommit، كما في بقية الملف.
 */
export interface SeatReturnResult {
  /** `false` = لم يكن الحجز `CONFIRMED` (أُلغي قبلاً) فلم يُرجَع شيء. */
  released: boolean;
  /** الرحلة بعد الإرجاع — لتقرير ما إذا بقي فيها ركّاب. */
  trip: Trip;
}

export async function releaseSeat(
  tx: Prisma.TransactionClient,
  bookingId: string,
): Promise<SeatReturnResult> {
  const booking = await tx.seatBooking.findUniqueOrThrow({
    where: { id: bookingId },
    include: { trip: true },
  });

  // حارس السباق: إلغاء واحد فقط يقلب الحالة، فالمقعد يُرجَع **مرة واحدة**
  // مهما تزامن منادِيان (راكب يلغي بينما تُحسم مهلة رفع، مثلاً).
  const cancelled = await tx.seatBooking.updateMany({
    where: { id: bookingId, status: BookingStatus.CONFIRMED },
    data: { status: BookingStatus.CANCELLED },
  });
  if (cancelled.count !== 1) {
    return { released: false, trip: booking.trip };
  }

  await tx.trip.update({
    where: { id: booking.tripId },
    data: { seatsAvailable: { increment: booking.seatCount } },
  });

  // إعادة فتح رحلة امتلأت وما زالت قابلة للّحاق.
  //
  // `isCatchable` وليس `departureTime > now`: رحلة «الآن» يمضي وقت مغادرتها
  // لحظة إعلانها، فالمقارنة اليدوية كانت تتركها `LOCKED` لبقية نافذتها —
  // المقعد المتحرّر لا يُعرض على أحد والسائق يمضي بمكان فارغ.
  const afterTrip = await tx.trip.findUniqueOrThrow({ where: { id: booking.tripId } });
  if (afterTrip.status === TripStatus.LOCKED && isCatchable(afterTrip)) {
    const reopened = await tx.trip.update({
      where: { id: booking.tripId },
      data: { status: TripStatus.OPEN },
    });
    return { released: true, trip: reopened };
  }

  return { released: true, trip: afterTrip };
}

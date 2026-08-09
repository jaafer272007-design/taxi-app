import { Injectable, NotFoundException } from '@nestjs/common';
import { AdminActionType, UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AdminService } from './admin.service';
import { BookingService } from '../booking/booking.service';
import { NoShowService } from '../booking/no-show.service';
import { TripService } from '../trip/trip.service';
import { normalizeIraqiPhone } from '../common/phone.util';
import { ActingAdmin, AdminAuditService } from './admin-audit.service';

/**
 * أدوات الدعم: البحث، والعرض، والتدخّل.
 *
 * ## المشكلة التي يحلّها هذا الملف
 *
 * اللوحة كانت تقدر تعتمد سائقاً وتسعّر ممراً، وما عدا ذلك كان يُنفَّذ بكتابة
 * SQL يدوياً — **ثلاث مرات أثناء الاختبار وحده**. ذاك لا يتوسّع أبعد من شخص
 * واحد، وبأول يوم تشغيل حقيقي راح يتصل أحد يقول «حجزي اختفى» وما في وسيلة
 * لمساعدته.
 *
 * ## القاعدة الحاكمة: كل تدخّل يمرّ بنفس خدمة التطبيق
 *
 * لا شيء هنا يكتب حالةً مباشرة. الإلغاء يمرّ بـ`BookingService` و
 * `TripService` نفسها التي يستعملها الراكب والسائق — بنفس معاملة المقاعد،
 * ونفس آلة الحالة، ونفس بثّ الإشعارات. لو كتب الأدمن الحالة مباشرة لتجاوز
 * ضمان **منع الـoverbooking** بصمت، وبالضبط على المسار الذي يُستعمل عندما
 * يكون شيء ما قد اختلّ أصلاً.
 *
 * ويتبع ذلك أن التدخّل **ليس أوسع صلاحية** من الفعل الأصلي: إذا كان الراكب
 * لا يقدر يلغي على رحلة `EN_ROUTE`، فالأدمن كذلك. آلة الحالة قاعدة المنتج،
 * لا مجاملة للراكب.
 *
 * ## الخصوصية
 *
 * أرقام الهواتف مرئية للأدمن **بحكم الضرورة** — الدعم يبدأ برقم يتصل منه
 * شخص. هذا عرض **مميّز** لا عام. أما **جهة اتصال الطوارئ** فلا تظهر هنا
 * إطلاقاً: هي بيانات الراكب الخاصة عن نفسه، وما في مهمة دعم واحدة تحتاجها.
 * كل `select` بهذا الملف صريح لهذا السبب، ويحرسه `admin-support.int-spec.ts`
 * بالتفتيش النصّي لا بفحص الحقول.
 */

/** Never `include: { user: true }` — that would carry the emergency contact. */
const PUBLIC_USER_SELECT = {
  id: true,
  phone: true,
  name: true,
  gender: true,
  roles: true,
  createdAt: true,
} as const;

@Injectable()
export class AdminSupportService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly admins: AdminService,
    private readonly bookings: BookingService,
    private readonly trips: TripService,
    private readonly noShows: NoShowService,
    private readonly audit: AdminAuditService,
  ) {}

  // ── Lookup ──────────────────────────────────────────────────────────────

  /**
   * One box, three kinds of answer.
   *
   * Support starts with whatever the caller can read out: a phone number, or
   * an id someone pasted from a screenshot. Making the admin choose the right
   * search field first is a step that only exists because the software could
   * not be bothered to look.
   */
  async search(query: string) {
    const q = query.trim();
    if (!q) return { kind: 'EMPTY' as const };

    // A phone is unambiguous, so try it first — and normalise, because the
    // caller will say «٠٧٧٠…» and the admin will type it however they type it.
    const phone = normalizeIraqiPhone(q);
    if (phone) {
      const user = await this.prisma.user.findUnique({
        where: { phone },
        select: PUBLIC_USER_SELECT,
      });
      return user
        ? { kind: 'USER' as const, user }
        : { kind: 'NOT_FOUND' as const, searchedPhone: phone };
    }

    // Otherwise it is an id. Which kind is not knowable from its shape (both
    // are cuids), so ask both tables rather than making the admin guess.
    const [trip, booking] = await Promise.all([
      this.prisma.trip.findUnique({ where: { id: q }, select: { id: true } }),
      this.prisma.seatBooking.findUnique({ where: { id: q }, select: { id: true, tripId: true } }),
    ]);
    if (trip) return { kind: 'TRIP' as const, tripId: trip.id };
    if (booking) return { kind: 'BOOKING' as const, bookingId: booking.id, tripId: booking.tripId };
    return { kind: 'NOT_FOUND' as const };
  }

  /** Everything support needs about one rider, in one call. */
  async rider(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: PUBLIC_USER_SELECT,
    });
    if (!user) throw new NotFoundException('المستخدم غير موجود.');

    const [bookings, ratingsGiven, ratingsReceived, noShows, block] = await Promise.all([
      this.prisma.seatBooking.findMany({
        where: { riderId: userId },
        orderBy: { createdAt: 'desc' },
        take: 50,
        include: { trip: { include: { corridor: true } } },
      }),
      this.prisma.rating.findMany({
        where: { fromUserId: userId },
        orderBy: { createdAt: 'desc' },
        take: 20,
      }),
      this.prisma.rating.findMany({
        where: { toUserId: userId },
        orderBy: { createdAt: 'desc' },
        take: 20,
      }),
      this.noShows.history(userId),
      this.noShows.blockStateFor(userId),
    ]);

    return {
      user,
      bookings: bookings.map((b) => ({
        id: b.id,
        tripId: b.tripId,
        status: b.status,
        seatCount: b.seatCount,
        fare: b.fare,
        paymentStatus: b.paymentStatus,
        createdAt: b.createdAt,
        pickupLabel: b.pickupLabel,
        dropoffLabel: b.dropoffLabel,
        trip: {
          status: b.trip.status,
          departureTime: b.trip.departureTime,
          originCity: b.trip.corridor.originCity,
          destCity: b.trip.corridor.destCity,
        },
      })),
      ratingsGiven,
      ratingsReceived,
      noShows,
      block: {
        blocked: block.blocked,
        blockedUntil: block.blockedUntil,
        countInWindow: block.countInWindow,
      },
      policy: this.noShows.policy,
    };
  }

  /** The driver side: profile, vehicle, documents, trips, earnings, ratings. */
  async driver(profileId: string) {
    const profile = await this.prisma.driverProfile.findUnique({
      where: { id: profileId },
      include: {
        user: { select: PUBLIC_USER_SELECT },
        vehicle: true,
        documents: true,
      },
    });
    if (!profile) throw new NotFoundException('السائق غير موجود.');

    const [trips, earnings, ratingsReceived] = await Promise.all([
      this.prisma.trip.findMany({
        where: { driverId: profileId },
        orderBy: { departureTime: 'desc' },
        take: 50,
        include: { corridor: true, _count: { select: { bookings: true } } },
      }),
      this.prisma.earningsRecord.aggregate({
        where: { driverId: profileId },
        _sum: { amount: true },
        _count: { _all: true },
      }),
      this.prisma.rating.findMany({
        where: { toUserId: profile.userId },
        orderBy: { createdAt: 'desc' },
        take: 20,
      }),
    ]);

    return {
      profile: {
        id: profile.id,
        status: profile.status,
        rejectionReason: profile.rejectionReason,
        ratingAvg: profile.ratingAvg,
        tripsDone: profile.tripsDone,
        user: profile.user,
        vehicle: profile.vehicle,
        documents: profile.documents,
      },
      trips: trips.map((t) => ({
        id: t.id,
        status: t.status,
        departureTime: t.departureTime,
        seatsTotal: t.seatsTotal,
        seatsAvailable: t.seatsAvailable,
        pricePerSeat: t.pricePerSeat,
        bookingCount: t._count.bookings,
        originCity: t.corridor.originCity,
        destCity: t.corridor.destCity,
      })),
      earnings: {
        total: earnings._sum.amount ?? 0,
        collected: earnings._count._all,
      },
      ratingsReceived,
    };
  }

  /** One trip, its bookings with rider names, and who posted it. */
  async trip(tripId: string) {
    const trip = await this.prisma.trip.findUnique({
      where: { id: tripId },
      include: { corridor: true },
    });
    if (!trip) throw new NotFoundException('الرحلة غير موجودة.');

    const [bookings, driver, vehicle] = await Promise.all([
      this.prisma.seatBooking.findMany({
        where: { tripId },
        orderBy: { createdAt: 'asc' },
      }),
      this.prisma.driverProfile.findUnique({
        where: { id: trip.driverId },
        select: {
          id: true,
          status: true,
          ratingAvg: true,
          user: { select: PUBLIC_USER_SELECT },
        },
      }),
      this.prisma.vehicle.findUnique({ where: { id: trip.vehicleId } }),
    ]);

    const riderIds = [...new Set(bookings.map((b) => b.riderId))];
    const riders = await this.prisma.user.findMany({
      where: { id: { in: riderIds } },
      select: { id: true, name: true, phone: true },
    });
    const riderById = new Map(riders.map((r) => [r.id, r]));

    return {
      trip: {
        id: trip.id,
        status: trip.status,
        departureTime: trip.departureTime,
        departNow: trip.departNow,
        seatsTotal: trip.seatsTotal,
        seatsAvailable: trip.seatsAvailable,
        pricePerSeat: trip.pricePerSeat,
        tripType: trip.tripType,
        createdAt: trip.createdAt,
        originCity: trip.corridor.originCity,
        destCity: trip.corridor.destCity,
      },
      driver,
      vehicle,
      bookings: bookings.map((b) => ({
        id: b.id,
        status: b.status,
        seatCount: b.seatCount,
        fare: b.fare,
        paymentStatus: b.paymentStatus,
        createdAt: b.createdAt,
        pickupLabel: b.pickupLabel,
        dropoffLabel: b.dropoffLabel,
        rider: riderById.get(b.riderId) ?? null,
      })),
      // There is no status-history table in Phase 1, so this is the honest
      // answer rather than a fabricated timeline: what an admin DID to this
      // trip is recorded, and what the state machine did is not.
      adminActions: await this.audit.list({ entityType: 'TRIP', entityId: tripId }),
    };
  }

  // ── Intervention ────────────────────────────────────────────────────────
  //
  // Each one: run the REAL service method, then record. Never the reverse —
  // a log written first fills with actions the state machine refused, and an
  // audit log that lies is worse than none.

  async cancelBooking(admin: ActingAdmin, bookingId: string, reason: string) {
    const booking = await this.bookings.cancelAsAdmin(bookingId);
    await this.audit.record(admin, {
      type: AdminActionType.BOOKING_CANCELLED,
      entityType: 'BOOKING',
      entityId: bookingId,
      reason,
    });
    return booking;
  }

  async cancelTrip(admin: ActingAdmin, tripId: string, reason: string) {
    const trip = await this.trips.cancelTripAsAdmin(tripId);
    await this.audit.record(admin, {
      type: AdminActionType.TRIP_CANCELLED,
      entityType: 'TRIP',
      entityId: tripId,
      reason,
    });
    return trip;
  }

  async suspendDriver(admin: ActingAdmin, profileId: string, reason: string) {
    const profile = await this.admins.suspend(profileId);
    await this.audit.record(admin, {
      type: AdminActionType.DRIVER_SUSPENDED,
      entityType: 'DRIVER',
      entityId: profileId,
      reason,
    });
    return profile;
  }

  async unsuspendDriver(admin: ActingAdmin, profileId: string, reason: string) {
    const profile = await this.admins.unsuspend(profileId);
    await this.audit.record(admin, {
      type: AdminActionType.DRIVER_UNSUSPENDED,
      entityType: 'DRIVER',
      entityId: profileId,
      reason,
    });
    return profile;
  }

  /**
   * The no-show appeal, surfaced here rather than reimplemented.
   *
   * `NoShowService` already owns the soft-void and the reason — this adds the
   * audit row so a void done from a rider's support page appears in the same
   * log as everything else an admin did that day.
   */
  async voidNoShow(admin: ActingAdmin, recordId: string, reason: string) {
    const result = await this.noShows.void(recordId, admin.id, reason);
    if (result.voided) {
      await this.audit.record(admin, {
        type: AdminActionType.NO_SHOW_VOIDED,
        entityType: 'RIDER',
        entityId: recordId,
        reason,
      });
    }
    return result;
  }

  async liftBlock(admin: ActingAdmin, riderId: string, reason: string) {
    const result = await this.noShows.liftBlock(riderId, admin.id, reason);
    await this.audit.record(admin, {
      type: AdminActionType.NO_SHOW_BLOCK_LIFTED,
      entityType: 'RIDER',
      entityId: riderId,
      reason,
    });
    return result;
  }

  /** Is this user a driver? Used by the panel to offer the right detail view. */
  async driverProfileIdFor(userId: string): Promise<string | null> {
    const profile = await this.prisma.driverProfile.findUnique({
      where: { userId },
      select: { id: true },
    });
    return profile?.id ?? null;
  }

  /** Riders only, for a sanity check on the search result. */
  isRider(roles: UserRole[]): boolean {
    return roles.includes(UserRole.RIDER);
  }
}

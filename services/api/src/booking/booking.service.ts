import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  BookingStatus,
  Gender,
  NotificationType,
  PaymentMethod,
  PaymentStatus,
  Prisma,
  SeatBooking,
  TripStatus,
  TripType,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { DriverService } from '../driver/driver.service';
import { NotificationService, NotificationPayload } from '../notification/notification.service';
import { CreateBookingDto } from './dto/create-booking.dto';
import { SearchTripsDto } from './dto/search-trips.dto';
import { catchableTripFilter, catchableUntil, isCatchable } from '../trip/trip-window';
import {
  isBookingUpcoming,
  isRatableByRider,
  TERMINAL_BOOKING_STATUSES,
} from './booking-lifecycle';
import { NoShowService } from './no-show.service';

/**
 * ─── لماذا اختفى قطع الإلغاء (١٥ دقيقة) ────────────────────────────────────
 *
 * كانت القاعدة: لا إلغاء بعد `catchableUntil − 15 دقيقة`. صارت: **يجوز
 * الإلغاء ما دامت الرحلة لم تبدأ (`EN_ROUTE`)**، مهما كان الوقت.
 *
 * غيّرها إدخال عقوبة عدم الحضور. مع وجود عقوبة، أي لحظة يكون فيها الراكب
 * محبوساً داخل حجز لا يستطيع الخروج منه تصير فخّاً: يُؤشَّر «لم يحضر» على
 * رحلة ما كان يقدر يتركها. والحالة الأسوأ حقيقية — رحلة «الآن» تُقفل نافذتها
 * بعد ٣٠ دقيقة والسائق لم يبدأ بعد، فيبقى الراكب مرتبطاً بلا مخرج.
 *
 * والأهم أن هذا **في صالح السائق لا ضده**، وهو ما يجعله قراراً سهلاً:
 *
 * | ماذا يحصل قبل الانطلاق | السائق يحصل على |
 * |---|---|
 * | الراكب يلغي (السلوك الجديد) | مقعد شاغر **قابل لإعادة البيع** فوراً، بلا خسارة |
 * | الراكب يُمنَع فيتخلّف (السلوك القديم) | مقعد فارغ **وواقعة عدم حضور**، والرحلة انطلقت ناقصة |
 *
 * القطع كان يحمي السائق من إلغاء اللحظة الأخيرة، لكنه عملياً كان يحوّل
 * الإلغاء إلى تخلّف — وهو أسوأ نتيجة للطرفين. حماية السائق الحقيقية هي
 * سجل عدم الحضور نفسه (`no-show-policy.ts`)، لا حبس الراكب.
 *
 * بعد `EN_ROUTE` لا إلغاء إطلاقاً — الرحلة انطلقت والمقعد استُهلك فعلاً.
 */
const CANCELLABLE_BEFORE = [TripStatus.OPEN, TripStatus.LOCKED] as const;

@Injectable()
export class BookingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly drivers: DriverService,
    private readonly notifications: NotificationService,
    private readonly noShows: NoShowService,
  ) {}

  /** Rider-facing search: only OPEN, still-catchable, seats-available trips. */
  async search(dto: SearchTripsDto) {
    const now = new Date();

    // Deliberately a pure read: an expired trip is invisible because of
    // `catchableTripFilter`, not because something swept it first. Retiring the
    // row is housekeeping and belongs on the scheduler (TripExpiryJob), not on
    // the rider's hottest path.
    //
    // Bounds the RIDER asked for (a day, a from/to time). Separate from the
    // catchability rule below, which is ours and not negotiable.
    const requestedBounds: Prisma.DateTimeFilter[] = [];

    if (dto.date) {
      const day = dto.date.slice(0, 10); // YYYY-MM-DD
      const dayStart = new Date(`${day}T00:00:00`); // process TZ = Asia/Baghdad
      const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);
      requestedBounds.push({ gte: dayStart, lt: dayEnd });
    }
    if (dto.fromTime) requestedBounds.push({ gte: new Date(dto.fromTime) });
    if (dto.toTime) requestedBounds.push({ lte: new Date(dto.toTime) });

    const where: Prisma.TripWhereInput = {
      status: TripStatus.OPEN,
      seatsAvailable: { gt: 0 },
      AND: [
        // NOT a plain `departureTime > now`: that is exactly the filter that
        // made every departNow trip invisible the moment it was posted, since
        // departNow sets departureTime to now. See trip-window.ts.
        catchableTripFilter(now),
        ...requestedBounds.map((filter) => ({ departureTime: filter })),
      ],
    };
    if (dto.corridorId) where.corridorId = dto.corridorId;
    if (dto.tripType) where.tripType = dto.tripType;

    const trips = await this.prisma.trip.findMany({ where, orderBy: { departureTime: 'asc' } });
    if (trips.length === 0) return [];

    // Trip.driverId / vehicleId are plain FKs (no Prisma relation), so enrich in bulk.
    const driverIds = [...new Set(trips.map((t) => t.driverId))];
    const vehicleIds = [...new Set(trips.map((t) => t.vehicleId))];
    const [drivers, vehicles] = await Promise.all([
      this.prisma.driverProfile.findMany({
        where: { id: { in: driverIds } },
        select: {
          id: true,
          ratingAvg: true,
          user: { select: { name: true, gender: true } },
        },
      }),
      this.prisma.vehicle.findMany({
        where: { id: { in: vehicleIds } },
        select: { id: true, make: true, model: true, color: true, seats: true },
      }),
    ]);
    const driverMap = new Map(drivers.map((d) => [d.id, d]));
    const vehicleMap = new Map(vehicles.map((v) => [v.id, v]));

    const results = trips.map((t) => {
      const vehicle = vehicleMap.get(t.vehicleId);
      const driver = driverMap.get(t.driverId);
      return {
        id: t.id,
        corridorId: t.corridorId,
        departureTime: t.departureTime,
        pricePerSeat: t.pricePerSeat,
        seatsAvailable: t.seatsAvailable,
        seatsTotal: t.seatsTotal,
        tripType: t.tripType,
        driverName: driver?.user?.name ?? null,
        driverGender: driver?.user?.gender ?? null,
        driverRatingAvg: driver?.ratingAvg ?? 0,
        vehicle: vehicle
          ? { make: vehicle.make, model: vehicle.model, color: vehicle.color, seats: vehicle.seats }
          : null,
      };
    });

    // driverGender lives on User (no Trip→User relation), so it can't be a DB
    // where-filter — post-filter the enriched rows. An empty result is valid
    // (e.g. near-zero female-driver supply), not an error.
    if (dto.driverGender) {
      return results.filter((r) => r.driverGender === dto.driverGender);
    }
    return results;
  }

  /** Book seats on a trip. Seat reservation is atomic and overbooking-safe. */
  async book(userId: string, dto: CreateBookingDto) {
    const trip = await this.prisma.trip.findUnique({ where: { id: dto.tripId } });
    if (!trip) {
      throw new NotFoundException('الرحلة غير موجودة.');
    }
    if (trip.status !== TripStatus.OPEN) {
      throw new ConflictException('الرحلة غير متاحة للحجز.');
    }
    // The SAME rule search uses. If these two ever diverge again the rider gets
    // the worst possible version of the bug: the trip is listed, and tapping
    // «احجز مقعد» answers «انتهى وقت هذه الرحلة».
    if (!isCatchable(trip)) {
      throw new ConflictException('انتهى وقت هذه الرحلة.');
    }
    const myProfile = await this.drivers.findProfileByUserId(userId);
    if (myProfile && myProfile.id === trip.driverId) {
      throw new BadRequestException('لا يمكنك حجز رحلتك الخاصة.');
    }
    if (dto.seatCount > trip.seatsAvailable) {
      throw new ConflictException('المقاعد المطلوبة غير متاحة.');
    }

    // Gender eligibility — enforced BEFORE the seat-reservation transaction so the
    // atomic row-lock/overbooking guarantee below is never weakened.
    // Rule: a rider must have a gender set to book anything (complete profile);
    // a WOMEN_FAMILY trip additionally requires the rider to be FEMALE (a woman
    // may book extra seats for family). GENERAL trips place no gender restriction.
    const rider = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { gender: true },
    });
    if (!rider || rider.gender == null) {
      throw new ForbiddenException('يرجى إكمال ملفك الشخصي (تحديد الجنس) قبل الحجز.');
    }
    if (trip.tripType === TripType.WOMEN_FAMILY && rider.gender !== Gender.FEMALE) {
      throw new ForbiddenException('هذه الرحلة مخصّصة للنساء والعائلات فقط.');
    }

    // ─── الإيقاف المؤقت بسبب تكرار عدم الحضور ────────────────────────────
    // مثل فحص الجنس: **قبل** معاملة المقعد، فلا يضعف ضمانها.
    //
    // الخادم هو البوّابة. التطبيق يعرض الحالة قبل نموذج الحجز حتى لا يملأه
    // الراكب بلا فائدة، لكن ذلك تحسين تجربة لا حراسة: مَن ينادي الـ API
    // مباشرة يُرفض هنا.
    //
    // الرد يحمل حقولاً مبنيّة (`blockedUntil` بصيغة ISO) بجانب الرسالة، حتى
    // يعرض التطبيق التاريخ بالأرقام العربية وبتنسيقه هو، بدل تفكيك نصّ.
    const block = await this.noShows.blockStateFor(userId);
    if (block.blocked) {
      throw new ForbiddenException({
        statusCode: 403,
        error: 'Forbidden',
        code: 'RIDER_BLOCKED_NO_SHOW',
        message: this.noShows.message(block),
        blockedUntil: block.blockedUntil?.toISOString() ?? null,
        noShowCount: block.countInWindow,
        threshold: this.noShows.policy.threshold,
        windowDays: this.noShows.policy.windowDays,
      });
    }

    const booking = await this.prisma.$transaction(async (tx) => {
      // Atomic, race-safe reservation. The WHERE guard (status OPEN AND
      // seatsAvailable >= seatCount) makes concurrent bookings for the last
      // seat safe: exactly one UPDATE affects the row; the loser sees count 0.
      // seatsAvailable can never go negative.
      const reserved = await tx.trip.updateMany({
        where: { id: dto.tripId, status: TripStatus.OPEN, seatsAvailable: { gte: dto.seatCount } },
        data: { seatsAvailable: { decrement: dto.seatCount } },
      });
      if (reserved.count !== 1) {
        throw new ConflictException('لم يعد المقعد متاحاً.');
      }

      // ─── ONE BOOKING PER RIDER PER TRIP ──────────────────────────────────
      // Deliberately AFTER the updateMany above, which is what makes this
      // race-safe without a new index: that statement takes a row lock on the
      // trip, so a second concurrent booking by the same rider blocks here
      // until the first commits and then sees it. A pre-transaction check
      // would let a double-tap through.
      //
      // Why block at all: a second row is never what the rider means — they
      // mean "more seats" — and it silently defeats the 4-seat cap the DTO
      // enforces (4 + 4 = 8). It also gives the driver two entries for one
      // passenger group at one pickup point. `changeSeats` is the real answer.
      const existing = await tx.seatBooking.findFirst({
        where: {
          tripId: dto.tripId,
          riderId: userId,
          status: { notIn: [...TERMINAL_BOOKING_STATUSES] },
        },
        select: { id: true },
      });
      if (existing) {
        throw new ConflictException(
          'لديك حجز على هذه الرحلة بالفعل. يمكنك تعديل عدد المقاعد بدل حجز جديد.',
        );
      }

      const afterTrip = await tx.trip.findUniqueOrThrow({ where: { id: dto.tripId } });
      // Auto-lock the trip when it fills up (business rule: lock at seatsAvailable=0).
      if (afterTrip.seatsAvailable === 0) {
        await tx.trip.update({ where: { id: dto.tripId }, data: { status: TripStatus.LOCKED } });
      }

      // TODO(Phase 2): validate pickup within origin city / dropoff within dest city (PostGIS).
      return tx.seatBooking.create({
        data: {
          tripId: dto.tripId,
          riderId: userId,
          pickupLat: dto.pickup.lat,
          pickupLng: dto.pickup.lng,
          pickupLabel: dto.pickup.label,
          dropoffLat: dto.dropoff.lat,
          dropoffLng: dto.dropoff.lng,
          dropoffLabel: dto.dropoff.label,
          seatCount: dto.seatCount,
          fare: afterTrip.pricePerSeat * dto.seatCount,
          paymentMethod: PaymentMethod.CASH,
          paymentStatus: PaymentStatus.PENDING,
          status: BookingStatus.CONFIRMED,
        },
      });
    });

    // Fire AFTER commit — a notification failure must not roll back the booking.
    await this.notifyDriver(trip.driverId, {
      type: NotificationType.BOOKING_CREATED,
      title: 'حجز جديد',
      body: 'حجز جديد على رحلتك.',
      tripId: trip.id,
      bookingId: booking.id,
    });
    // The rider's own receipt. It was missing: the driver learned a seat had
    // gone and the rider, who had just committed to a journey, was told
    // nothing they could go back and look at.
    await this.notifications.send(userId, {
      type: NotificationType.BOOKING_CONFIRMED,
      title: 'تم تأكيد حجزك',
      body: 'حجزك مؤكد. ستصلك إشعارات عن الرحلة هنا.',
      tripId: trip.id,
      bookingId: booking.id,
    });
    // The car, so «شارك رحلتي» works on the confirmation screen without a
    // second round trip the rider would sit and wait for.
    //
    // The PLATE is the entitlement question, and the answer is the same rule
    // /bookings/mine uses: a rider who holds a booking may see the car they
    // are getting into. Search deliberately does NOT carry it — otherwise
    // scrolling results would hand anyone every driver's plate, the same
    // reasoning that keeps phone numbers behind a booking.
    //
    // Non-fatal, for the same reason the notifications above it are: the seat
    // is already COMMITTED. Failing the response here would tell a rider their
    // booking failed when it did not — and their retry would then hit «لديك
    // حجز على هذه الرحلة بالفعل». A missing car costs them a share button.
    let vehicle: {
      make: string;
      model: string;
      plate: string;
      color: string;
    } | null = null;
    try {
      vehicle = await this.prisma.vehicle.findUnique({
        where: { driverId: trip.driverId },
        select: { make: true, model: true, plate: true, color: true },
      });
    } catch {
      vehicle = null;
    }
    return { ...booking, vehicle };
  }

  /**
   * Rider's bookings with trip info, each flagged upcoming vs past and carrying
   * what the rider needs to rate their driver.
   *
   * The bucket comes from `isBookingUpcoming` — a STATUS question, not a clock
   * one; see `booking-lifecycle.ts` for why that distinction has now cost us
   * two bugs.
   *
   * Three queries regardless of how many bookings come back: the bookings, the
   * driver profiles behind them, and this rider's ratings for those trips.
   * `Trip.driverId` is a plain FK with no Prisma relation, so the driver's USER
   * id — the thing a rating is addressed to — has to be resolved separately.
   */
  async listMine(userId: string) {
    const bookings = await this.prisma.seatBooking.findMany({
      where: { riderId: userId },
      include: { trip: { include: { corridor: true } } },
      orderBy: { createdAt: 'desc' },
    });
    if (bookings.length === 0) return [];

    const profiles = await this.prisma.driverProfile.findMany({
      where: { id: { in: [...new Set(bookings.map((b) => b.trip.driverId))] } },
      select: {
        id: true,
        userId: true,
        user: { select: { name: true } },
        // The car, for «شارك رحلتي». The PLATE is the point: it is the one
        // item that lets someone at the other end of a WhatsApp message pick
        // this vehicle out of a rank.
        //
        // No new exposure — /trips/search already shows the rider the car
        // before they book, which is how they choose. Explicit `select`
        // rather than `include` so the driver's own user row cannot ride
        // along with it.
        vehicle: {
          select: { make: true, model: true, plate: true, color: true },
        },
      },
    });
    const driverByProfileId = new Map(profiles.map((p) => [p.id, p]));

    // Ratings this rider has already written for these trips. Only their own —
    // whether the DRIVER rated THEM is none of the rider's business here.
    const ratings = await this.prisma.rating.findMany({
      where: {
        fromUserId: userId,
        tripId: { in: [...new Set(bookings.map((b) => b.tripId))] },
      },
      select: { tripId: true, toUserId: true },
    });
    const ratedPairs = new Set(ratings.map((r) => `${r.tripId}:${r.toUserId}`));

    const now = new Date();
    return bookings.map((b) => {
      const driver = driverByProfileId.get(b.trip.driverId);
      return {
        ...b,
        upcoming: isBookingUpcoming(
          {
            bookingStatus: b.status,
            tripStatus: b.trip.status,
            // departNow travels with departureTime or the bucket cannot tell
            // "leaving now" from "already gone". See booking-lifecycle.ts.
            departNow: b.trip.departNow,
            departureTime: b.trip.departureTime,
          },
          now,
        ),
        // The driver's USER id, which is who a rating is addressed to. No phone
        // number here — that stays behind GET /trips/:id/contacts, the one
        // place in the server a number ever leaves.
        driverUserId: driver?.userId ?? null,
        driverName: driver?.user?.name ?? null,
        // Null when a driver somehow has no vehicle row. The share sheet drops
        // the line rather than printing "null" into a message a rider is about
        // to send their family.
        vehicle: driver?.vehicle ?? null,
        ratable: isRatableByRider(b.status, b.trip.status),
        ratedDriver: driver ? ratedPairs.has(`${b.tripId}:${driver.userId}`) : false,
      };
    });
  }

  /**
   * Change how many seats a booking holds (owning rider).
   *
   * ## Why this exists
   *
   * Until now there was no way to edit a booking at all, so a rider who needed
   * one more seat booked the same trip a second time. That workaround is now
   * refused (see `book`), which would leave them strictly worse off if this did
   * not exist — cancel-and-rebook risks losing the seats to someone else in the
   * gap, on a corridor where a trip fills in minutes.
   *
   * The seat delta goes through the SAME atomic guard as a first booking:
   * growing re-runs the overbooking-safe `updateMany`, shrinking returns seats
   * and reopens a trip that had locked. Never a read-then-write.
   */
  async changeSeats(userId: string, bookingId: string, seatCount: number): Promise<SeatBooking> {
    const booking = await this.prisma.seatBooking.findUnique({
      where: { id: bookingId },
      include: { trip: true },
    });
    if (!booking) {
      throw new NotFoundException('الحجز غير موجود.');
    }
    if (booking.riderId !== userId) {
      throw new ForbiddenException('هذا ليس حجزك.');
    }
    if (booking.status !== BookingStatus.CONFIRMED) {
      throw new ConflictException('لا يمكن تعديل هذا الحجز.');
    }
    // Same window as cancelling, for the same reason: shrinking a booking is a
    // partial cancel, and a rider must not be blocked from it at a moment they
    // would be allowed to drop the whole thing. See [CANCELLABLE_BEFORE].
    const trip = booking.trip;
    if (!CANCELLABLE_BEFORE.includes(trip.status as (typeof CANCELLABLE_BEFORE)[number])) {
      throw new ConflictException('لا يمكن التعديل بعد بدء الرحلة.');
    }
    // Idempotent: asking for the count it already has is success, not a 409.
    if (seatCount === booking.seatCount) return booking;

    const delta = seatCount - booking.seatCount;

    return this.prisma.$transaction(async (tx) => {
      if (delta > 0) {
        // Same WHERE guard as booking: exactly one UPDATE wins the last seat.
        const reserved = await tx.trip.updateMany({
          where: { id: trip.id, status: TripStatus.OPEN, seatsAvailable: { gte: delta } },
          data: { seatsAvailable: { decrement: delta } },
        });
        if (reserved.count !== 1) {
          throw new ConflictException('المقاعد المطلوبة غير متاحة.');
        }
        const afterTrip = await tx.trip.findUniqueOrThrow({ where: { id: trip.id } });
        if (afterTrip.seatsAvailable === 0) {
          await tx.trip.update({ where: { id: trip.id }, data: { status: TripStatus.LOCKED } });
        }
      } else {
        await tx.trip.update({
          where: { id: trip.id },
          data: { seatsAvailable: { increment: -delta } },
        });
        // Freed seats make a full trip bookable again — same rule as cancel.
        const afterTrip = await tx.trip.findUniqueOrThrow({ where: { id: trip.id } });
        if (afterTrip.status === TripStatus.LOCKED && isCatchable(afterTrip)) {
          await tx.trip.update({ where: { id: trip.id }, data: { status: TripStatus.OPEN } });
        }
      }

      // Re-assert CONFIRMED so a concurrent cancel cannot be overwritten.
      const changed = await tx.seatBooking.updateMany({
        where: { id: bookingId, status: BookingStatus.CONFIRMED },
        data: { seatCount, fare: trip.pricePerSeat * seatCount },
      });
      if (changed.count !== 1) {
        throw new ConflictException('تم تغيير حالة الحجز. حدّث الصفحة وحاول مرة أخرى.');
      }
      return tx.seatBooking.findUniqueOrThrow({ where: { id: bookingId } });
    });
  }

  /** Cancel a booking (owning rider), returning the seat atomically. */
  async cancel(userId: string, bookingId: string): Promise<SeatBooking> {
    return this.cancelBooking(bookingId, { requireRiderId: userId });
  }

  /**
   * Cancel a booking on the rider's behalf, from the admin panel.
   *
   * ## Why this is three lines and not a copy
   *
   * It calls the SAME method the rider's own cancel does — same seat
   * transaction, same state machine, same notification fan-out. The ONLY
   * difference is that there is no ownership check to make, because the caller
   * is not the owner.
   *
   * Writing the state directly from an admin endpoint would have bypassed the
   * row-locked seat return, the LOCKED→OPEN reopen, and both notifications —
   * i.e. the zero-overbooking guarantee, silently, on the one code path used
   * when something has already gone wrong.
   *
   * It is deliberately NOT more permissive than the rider's path: an admin
   * cannot cancel on an `EN_ROUTE` trip either. If a rider is refused, so is
   * an admin — the state machine is the product's rule, not a rider-facing
   * courtesy.
   */
  async cancelAsAdmin(bookingId: string): Promise<SeatBooking> {
    return this.cancelBooking(bookingId, {});
  }

  private async cancelBooking(
    bookingId: string,
    opts: { requireRiderId?: string },
  ): Promise<SeatBooking> {
    const booking = await this.prisma.seatBooking.findUnique({
      where: { id: bookingId },
      include: { trip: true },
    });
    if (!booking) {
      throw new NotFoundException('الحجز غير موجود.');
    }
    if (opts.requireRiderId !== undefined && booking.riderId !== opts.requireRiderId) {
      throw new ForbiddenException('هذا ليس حجزك.');
    }
    if (booking.status !== BookingStatus.CONFIRMED) {
      throw new ConflictException('لا يمكن إلغاء هذا الحجز.');
    }
    // The ONLY gate is "has the trip started". No clock cutoff — see
    // [CANCELLABLE_BEFORE] for why the 15-minute rule was removed rather than
    // relaxed: with a no-show penalty on the other side, any moment a rider
    // cannot get out of a booking is a trap, and a released seat is strictly
    // better for the driver than an empty one plus a no-show.
    const trip = booking.trip;
    if (!CANCELLABLE_BEFORE.includes(trip.status as (typeof CANCELLABLE_BEFORE)[number])) {
      throw new ConflictException('لا يمكن الإلغاء بعد بدء الرحلة.');
    }

    const cancelledBooking = await this.prisma.$transaction(async (tx) => {
      // Race guard: only one concurrent cancel flips CONFIRMED→CANCELLED, so the
      // seat is returned exactly once (no double refund).
      const cancelled = await tx.seatBooking.updateMany({
        where: { id: bookingId, status: BookingStatus.CONFIRMED },
        data: { status: BookingStatus.CANCELLED },
      });
      if (cancelled.count !== 1) {
        throw new ConflictException('تم إلغاء الحجز مسبقاً.');
      }

      await tx.trip.update({
        where: { id: trip.id },
        data: { seatsAvailable: { increment: booking.seatCount } },
      });

      // Reopen a full-but-still-live trip so freed seats are bookable again.
      //
      // `isCatchable`, NOT `departureTime > now` — which is what this said, and
      // was the same departNow bug in a fourth place: a rider cancelling a seat
      // on a full «الآن» trip left it LOCKED for the rest of its window, so the
      // freed seat was never offered to anyone and the driver drove with an
      // empty place.
      const afterTrip = await tx.trip.findUniqueOrThrow({ where: { id: trip.id } });
      if (afterTrip.status === TripStatus.LOCKED && isCatchable(afterTrip)) {
        await tx.trip.update({ where: { id: trip.id }, data: { status: TripStatus.OPEN } });
      }

      return tx.seatBooking.findUniqueOrThrow({ where: { id: bookingId } });
    });

    // AFTER commit: tell the driver a seat opened up…
    await this.notifyDriver(trip.driverId, {
      type: NotificationType.BOOKING_CANCELLED_BY_RIDER,
      title: 'إلغاء حجز',
      body: 'أُلغي حجز على رحلتك.',
      tripId: trip.id,
      bookingId,
    });
    // …and leave the rider a record of their own cancellation. Not redundant
    // with the tap they just made: this is what they scroll back to when they
    // are no longer sure whether the seat actually went.
    // …and leave the RIDER a record — resolved from the booking, not from the
    // caller, so an admin-initiated cancel still reaches the person whose seat
    // it was rather than nobody.
    await this.notifications.send(booking.riderId, {
      type: NotificationType.BOOKING_CANCELLED,
      title: 'أُلغي حجزك',
      body: 'تم إلغاء حجزك ولن تُحاسب عليه.',
      tripId: trip.id,
      bookingId,
    });
    return cancelledBooking;
  }

  /** Resolve a trip's driver userId and push a notification (after commit). */
  private async notifyDriver(driverProfileId: string, payload: NotificationPayload): Promise<void> {
    const driver = await this.prisma.driverProfile.findUnique({
      where: { id: driverProfileId },
      select: { userId: true },
    });
    if (driver) {
      await this.notifications.send(driver.userId, payload);
    }
  }

  /** Driver marks a rider onboard: CONFIRMED → ONBOARD (trip must be EN_ROUTE). */
  onboard(userId: string, bookingId: string): Promise<SeatBooking> {
    return this.driverBookingTransition(userId, bookingId, BookingStatus.ONBOARD);
  }

  /**
   * Driver marks a rider no-show: CONFIRMED → NO_SHOW (trip must be EN_ROUTE).
   * The seat is NOT returned (held; no cash refund in the MVP) and the fare is
   * excluded from earnings at completion. Recorded for rider reputation.
   */
  noShow(userId: string, bookingId: string): Promise<SeatBooking> {
    return this.driverBookingTransition(userId, bookingId, BookingStatus.NO_SHOW);
  }

  private async driverBookingTransition(
    userId: string,
    bookingId: string,
    target: BookingStatus,
  ): Promise<SeatBooking> {
    const booking = await this.prisma.seatBooking.findUnique({
      where: { id: bookingId },
      include: { trip: true },
    });
    if (!booking) {
      throw new NotFoundException('الحجز غير موجود.');
    }
    const profile = await this.drivers.findProfileByUserId(userId);
    if (!profile || profile.id !== booking.trip.driverId) {
      throw new ForbiddenException('هذه ليست رحلتك.');
    }
    if (booking.trip.status !== TripStatus.EN_ROUTE) {
      throw new ConflictException('يجب أن تكون الرحلة جارية (EN_ROUTE).');
    }
    if (booking.status !== BookingStatus.CONFIRMED) {
      throw new ConflictException('لا يمكن تغيير حالة هذا الحجز.');
    }

    return this.prisma.$transaction(async (tx) => {
      // Re-assert CONFIRMED in the write: two drivers' devices (or a double
      // tap) must not produce two no-show records for one seat.
      const changed = await tx.seatBooking.updateMany({
        where: { id: bookingId, status: BookingStatus.CONFIRMED },
        data: { status: target },
      });
      if (changed.count !== 1) {
        throw new ConflictException('لا يمكن تغيير حالة هذا الحجز.');
      }

      // The history row and the status are written together or not at all.
      // A status with no row silently under-counts the rolling window; a row
      // with no status is a penalty nobody can trace back to a trip.
      if (target === BookingStatus.NO_SHOW) {
        await this.noShows.record(tx, {
          riderId: booking.riderId,
          tripId: booking.tripId,
          bookingId: booking.id,
          seatCount: booking.seatCount,
        });
      }

      return tx.seatBooking.findUniqueOrThrow({ where: { id: bookingId } });
    });
  }
}

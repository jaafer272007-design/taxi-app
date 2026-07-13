# بريف تقني — Phase 1 (MVP)
**النموذج:** السائق يعلن مسار + الراكب يحجز مقعد · ممر **النجف↔كربلاء** · مشترك بالمقعد · door-to-door · cash · Android.
**الغرض:** وثيقة بناء لـ Claude Code — module-by-module.

---

## 0. النطاق
**داخل Phase 1:** WhatsApp OTP · اعتماد سائق + مستمسكات · السائق يعلن رحلة (مجدولة أو "الآن") · بحث الراكب + حجز مقعد (door-to-door) · دورة حياة الرحلة · تحصيل نقدي + أرباح · تقييم متبادل · إشعارات · لوحة أدمن أساسية.
**خارج Phase 1 (لا تبنيه):** ❌ تجميع النظام (system-pooling) ❌ الطلب الآني بالمطابقة الحية ❌ دفع رقمي/محفظة ❌ iOS ❌ ممرات متعددة ❌ surge/كوبونات ❌ تتبّع لحظي كامل للموقع (يكفي حالة الرحلة + معلومات السائق).

---

## 1. الـ Stack المعتمد
- **API:** NestJS (modular monolith) · **ORM:** Prisma (قابل للتبديل لـ TypeORM) · **DB:** PostgreSQL (+ PostGIS متاح، بس Phase 1 يستعمل lat/lng بسيط) · **Cache:** Redis.
- **Mobile:** Flutter (كود واحد، شاشات راكب/سائق) — Android.
- **Admin:** React/Next.js.
- **Auth:** JWT + WhatsApp Business Cloud API للـ OTP (أعِد استخدام إعداد Sehat Beitak).
- **Push:** FCM.
- ثوابت: عملة **IQD**، توقيت **Asia/Baghdad**، لغة **عربي RTL**، هاتف **+964**.
> تبديل أي عنصر بالـ stack ما يغيّر تصميم الـ modules/endpoints أدناه.

---

## 2. نموذج البيانات (Prisma-style — مُصمَّم لاستيعاب Phase 2)
```prisma
enum UserRole { RIDER DRIVER ADMIN }
enum DriverStatus { PENDING APPROVED SUSPENDED REJECTED }
enum DocType { NATIONAL_ID DRIVING_LICENSE VEHICLE_REG }
enum DocStatus { PENDING APPROVED REJECTED }
enum TripStatus { OPEN LOCKED EN_ROUTE COMPLETED SETTLED CANCELLED }
enum TripCreatedBy { DRIVER SYSTEM }        // SYSTEM = Phase 2
enum BookingStatus { CONFIRMED ONBOARD COMPLETED CANCELLED NO_SHOW }
enum PaymentMethod { CASH }                 // WALLET/ZAINCASH = Phase 3
enum PaymentStatus { PENDING COLLECTED }

model User {
  id        String   @id @default(cuid())
  phone     String   @unique               // +964...
  name      String?
  roles     UserRole[]
  driver    DriverProfile?
  createdAt DateTime @default(now())
}

model DriverProfile {
  id        String       @id @default(cuid())
  userId    String       @unique
  user      User         @relation(fields: [userId], references: [id])
  status    DriverStatus @default(PENDING)
  rejectionReason String? // Phase 1 amendment (Step 3): reason set by admin on reject, cleared on approve
  ratingAvg Float        @default(0)
  tripsDone Int          @default(0)
  vehicle   Vehicle?
  documents Document[]
}

model Vehicle {
  id       String @id @default(cuid())
  driverId String @unique
  driver   DriverProfile @relation(fields: [driverId], references: [id])
  make     String
  model    String
  plate    String
  color    String
  seats    Int          // سعة المقاعد القصوى
}

model Document {
  id         String    @id @default(cuid())
  driverId   String
  driver     DriverProfile @relation(fields: [driverId], references: [id])
  type       DocType
  url        String
  status     DocStatus @default(PENDING)
  reviewedBy String?
}

model Corridor {
  id         String  @id @default(cuid())
  originCity String  // "Najaf"
  destCity   String  // "Karbala"
  active     Boolean @default(true)
  pricePerSeat Int    // ثابت يحدده الأدمن (IQD)
  trips      Trip[]
}

model Trip {
  id            String        @id @default(cuid())
  corridorId    String
  corridor      Corridor      @relation(fields: [corridorId], references: [id])
  driverId      String
  vehicleId     String
  departureTime DateTime
  departNow     Boolean       @default(false)
  seatsTotal    Int
  seatsAvailable Int
  pricePerSeat  Int
  status        TripStatus    @default(OPEN)
  createdBy     TripCreatedBy @default(DRIVER)
  bookings      SeatBooking[]
  createdAt     DateTime      @default(now())
}

model SeatBooking {
  id            String        @id @default(cuid())
  tripId        String
  trip          Trip          @relation(fields: [tripId], references: [id])
  riderId       String
  pickupLat     Float
  pickupLng     Float
  pickupLabel   String
  dropoffLat    Float
  dropoffLng    Float
  dropoffLabel  String
  seatCount     Int           @default(1)
  fare          Int
  paymentMethod PaymentMethod @default(CASH)
  paymentStatus PaymentStatus @default(PENDING)
  status        BookingStatus @default(CONFIRMED)
  createdAt     DateTime      @default(now())
}

model Rating {
  id         String  @id @default(cuid())
  tripId     String
  fromUserId String
  toUserId   String
  score      Int     // 1..5
  comment    String?
  createdAt  DateTime @default(now())
}

model EarningsRecord {
  id          String   @id @default(cuid())
  driverId    String
  tripId      String
  amount      Int
  collectedAt DateTime @default(now())
}

// Phase 1 amendment (Step 6): FCM device tokens for push notifications.
model DeviceToken {
  id        String   @id @default(cuid())
  userId    String
  token     String   @unique
  platform  String
  createdAt DateTime @default(now())
  @@index([userId])
}
// SeatRequest = Phase 2 (لا يُبنى الآن)
```

---

## 3. آلات الحالة
**Trip:** `OPEN` (يقبل حجوزات) → `LOCKED` (امتلأ أو حان الوقت) → `EN_ROUTE` (السائق بدأ) → `COMPLETED` → `SETTLED`. أي وقت قبل EN_ROUTE → `CANCELLED`.
**SeatBooking:** `CONFIRMED` → `ONBOARD` (اختياري) → `COMPLETED`. أو `CANCELLED` (قبل القطع) / `NO_SHOW` (السائق يأشّرها).

---

## 4. الـ Modules + الـ Endpoints

### `auth`
- `POST /auth/request-otp` `{ phone }` → يرسل OTP عبر واتساب.
- `POST /auth/verify-otp` `{ phone, code }` → JWT (يُنشئ User إذا جديد).
- `GET /auth/me`.
**قبول:** رقم عراقي يستلم كود واتساب ويدخل بنجاح؛ إعادة الإرسال محدودة (rate-limit).

### `driver`
- `POST /driver/profile` (يصير سائق) · `POST /driver/vehicle` · `POST /driver/documents` (رفع) · `GET /driver/profile`.
- أدمن: `GET /admin/drivers?status=` · `POST /admin/drivers/:id/approve|reject|suspend`.
**قبول:** سائق يرفع مستمسكاته → أدمن يعتمده → يقدر يعلن رحلة.

### `corridor` (أدمن)
- `GET /corridors` · `POST /corridors` `{ originCity, destCity, pricePerSeat }` · `PATCH /corridors/:id`.
**قبول:** ممر النجف↔كربلاء (اتجاهين) موجود بسعر/مقعد محدد.

### `trip` (جانب السائق)
- `POST /trips` `{ corridorId, departureTime | departNow, seatsTotal }` (يأخذ pricePerSeat من الممر).
- `GET /trips/mine` · `POST /trips/:id/start` → EN_ROUTE (يقفل) · `POST /trips/:id/complete` → COMPLETED (+ EarningsRecord) · `POST /trips/:id/cancel`.
**قواعد:** `seatsTotal ≤ vehicle.seats`. سائق مُعتمد فقط. `departNow=true` → departureTime=now، ونافذة صلاحية افتراضية 30 دقيقة (قابلة للتمديد).
**قبول:** سائق مُعتمد يعلن رحلة نجف→كربلاء بمقاعد؛ تظهر OPEN.

### `booking` (جانب الراكب)
- `GET /trips/search?corridorId=&date=&fromTime=&toTime=` → رحلات OPEN و seatsAvailable>0 (مع وقت، سعر، تقييم السائق، السيارة).
- `POST /bookings` `{ tripId, pickup{lat,lng,label}, dropoff{lat,lng,label}, seatCount }` → CONFIRMED.
- `GET /bookings/mine` · `POST /bookings/:id/cancel`.
- سائق: `POST /bookings/:id/onboard` · `POST /bookings/:id/no-show`.
**⚠ قاعدة حرجة — Concurrency:** خصم `seatsAvailable` لازم يكون **transactional مع row-lock** (أو `UPDATE ... WHERE seatsAvailable >= seatCount`) لمنع overbooking عند حجزين متزامنين على آخر مقعد. الإلغاء يرجّع المقاعد.
**قطع الحجز:** إلغاء مجاني حتى 15 دقيقة قبل المغادرة (افتراضي)؛ بعدها يُعلَّم.
**قبول:** راكبان يحجزون آخر مقعد بنفس اللحظة → واحد ينجح فقط، والمخزون صحيح.

### `rating`
- `POST /ratings` `{ tripId, toUserId, score, comment }` (بعد COMPLETED فقط) · تحديث `ratingAvg`.
**قبول:** الطرفان يقيّمون بعضهم بعد اكتمال الرحلة.

### `notification`
- `POST /devices` `{ token }` (FCM). أحداث تُطلق إشعار: حجز جديد (للسائق)، تأكيد حجز (للراكب)، تذكير مغادرة، إلغاء رحلة، بدء/إكمال.
**قبول:** الأحداث الرئيسية تُطلق إشعارات فعلاً.

### `earnings` (نقدي)
- `GET /driver/earnings?range=` (يومي/إجمالي). يُسجَّل عند إكمال الرحلة.
**قبول:** أرباح اليوم تظهر صح للسائق بعد رحلة مكتملة.

---

## 5. الشاشات
**تطبيق الراكب:** (1) onboarding: هاتف→OTP→اسم · (2) بحث: ممر + تاريخ/وقت + from/to · (3) نتائج (كروت: وقت، سعر/مقعد، مقاعد متبقية، تقييم السائق) · (4) تفاصيل + حجز: أشّر نقطة الصعود والنزول على الخريطة + عدد المقاعد → تأكيد (cash) · (5) حجوزاتي (قادمة/سابقة) · (6) متابعة الرحلة (معلومات السائق + الحالة) · (7) تقييم السائق · (8) الملف.
**تطبيق السائق:** (1) onboarding + رفع مستمسكات (هوية، إجازة سوق، تسجيل مركبة) → بانتظار الاعتماد · (2) إعلان مسار (ممر، الآن/مجدول، مقاعد) · (3) رحلاتي + حجوزات كل رحلة (راكب، صعود/نزول، مقاعد) · (4) إدارة الرحلة: بدء/إكمال/إلغاء، onboard/no-show · (5) الأرباح · (6) تقييم الركّاب · (7) الملف.
**لوحة الأدمن:** (1) Dashboard (عدّادات) · (2) اعتماد السواق + مراجعة المستمسكات · (3) مراقبة الرحلات · (4) الممرات والتسعير · (5) بحث/دعم أساسي.
> تصميم الشاشات تفصيلياً: يُطبَّق سكل `ui-ux-pro-max` بمرحلة الـ UI.

---

## 6. قواعد تجارية مهمة
- **مخزون المقاعد:** transactional حصراً (قسم booking).
- **التسعير:** ثابت لكل ممر من الأدمن؛ `fare = pricePerSeat × seatCount`.
- **قفل الرحلة:** تلقائي عند `seatsAvailable=0` أو عند `departureTime`؛ أو يدوي ببدء السائق.
- **No-show:** السائق يعلّمها → تؤثر على سمعة الراكب (لا خصم مالي بالـ MVP).
- **إلغاء السائق للرحلة:** كل الحجوزات CANCELLED + إشعار الركّاب فوراً.
- **الهوية:** رقم الموبايل هو المفتاح؛ مستخدم واحد بدورين ممكن.

---

## 7. ترتيب البناء لـ Claude Code (كل خطوة قابلة للاختبار)
1. **Scaffold + DB + `auth`** → *milestone:* دخول بواتساب OTP يشتغل.
2. **`driver` + اعتماد الأدمن** → *milestone:* سائق يُعتمد.
3. **`corridor` + `trip` posting** → *milestone:* سائق يعلن رحلة نجف↔كربلاء.
4. **`booking` (بحث + حجز transactional)** → *milestone:* راكب يحجز، المخزون صحيح، لا overbooking.
5. **`trip-lifecycle` + `earnings`** → *milestone:* رحلة كاملة تكتمل، النقد مسجّل.
6. **`rating` + `notification`** → *milestone:* تقييم + إشعارات رئيسية تشتغل.
7. **Admin dashboard + صقل** → *milestone:* معايير قبول Phase 1 تتحقق.
> اختبر رحلة كاملة (حجز→ركوب→نقد→تقييم) قبل ما تنتقل للـ milestone التالي.

---

## 8. معايير قبول Phase 1 (تعريف "خلصت")
- سائق يسجّل، يُعتمد، يعلن رحلة نجف↔كربلاء بمقاعد وسعر.
- راكب يبحث، يلگّيها، يحجز مقعد مع صعود/نزول؛ المقاعد تنخصم صح بلا overbooking.
- السائق يبدأ ويكمل الرحلة؛ النقد يُسجَّل أرباح؛ الطرفان يتقيّمون.
- الإلغاء والـ no-show مُعالَجان؛ الإشعارات تشتغل.
- كله عربي RTL، IQD، Asia/Baghdad، WhatsApp OTP، Android.

---

## 9. قرارات مبدئية — عدّلها إذا تريد
| القرار | الافتراضي |
|---|---|
| منو يحدد السعر | الأدمن، ثابت لكل ممر |
| نقطة الصعود/النزول | الراكب يأشّرها على الخريطة (door-to-door) |
| أقصى مقاعد للرحلة | 4 (مقيّد بسعة السيارة) |
| قطع الإلغاء المجاني | 15 دقيقة قبل المغادرة |
| نافذة "الآن" | تنتهي بعد 30 دقيقة إن لم تمتلئ (قابلة للتمديد) |

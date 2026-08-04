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
enum Gender { MALE FEMALE }                 // Phase 1 amendment: required to complete a profile
enum DriverStatus { PENDING APPROVED SUSPENDED REJECTED }
enum DocType { NATIONAL_ID DRIVING_LICENSE VEHICLE_REG }
enum DocStatus { PENDING APPROVED REJECTED }
enum TripStatus { OPEN LOCKED EN_ROUTE COMPLETED SETTLED CANCELLED }
enum TripCreatedBy { DRIVER SYSTEM }        // SYSTEM = Phase 2
enum TripType { GENERAL WOMEN_FAMILY }      // Phase 1 amendment: عامة / نسائية-عائلية
enum BookingStatus { CONFIRMED ONBOARD COMPLETED CANCELLED NO_SHOW }
enum PaymentMethod { CASH }                 // WALLET/ZAINCASH = Phase 3
enum PaymentStatus { PENDING COLLECTED }

model User {
  id        String   @id @default(cuid())
  phone     String   @unique               // +964...
  name      String?
  gender    Gender?  // Phase 1 amendment: nullable in DB (existing rows), API-required to complete
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
  originCity String  // "Najaf" — من قائمة المدن الرسمية (18 محافظة)
  destCity   String  // "Karbala"
  active     Boolean @default(true)
  // Phase 1 amendment (تسعير يحدده السائق): الأدمن ما عاد يحدد الأجرة؛ يحدد
  // اقتراحاً + حدّين. القيد: 0 < min <= suggested <= max (يفرضه CorridorService).
  suggestedPricePerSeat Int // السعر المعتاد على هذا المسار (IQD)
  minPricePerSeat       Int // أدنى سعر مسموح للسائق (IQD)
  maxPricePerSeat       Int // أعلى سعر مسموح للسائق (IQD)
  trips      Trip[]
  @@unique([originCity, destCity]) // ممر واحد لكل زوج (اتجاه)؛ يمنع التكرار
}
// المدن: قائمة رسمية بـ 18 مدينة (محافظة) — services/api/src/corridor/cities.ts
// و packages/shared/lib/constants/iraqi_cities.dart (متطابقتان). الممر يُنشأ بين
// أي مدينتين من القائمة؛ زوج المدن يصبح قابلاً للبحث/النشر فقط بعد إنشاء ممر له.

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
  pricePerSeat  Int           // Phase 1 amendment: يحدده **السائق** عند النشر ضمن حدود الممر
  status        TripStatus    @default(OPEN)
  createdBy     TripCreatedBy @default(DRIVER)
  tripType      TripType      @default(GENERAL) // Phase 1 amendment: عامة / نسائية-عائلية
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
// Phase 1 amendment (Step 7): حسابات الأدمن — اسم مستخدم + كلمة مرور.
// منفصلة عمداً عن User (هاتف + OTP): الأدمن مو راكب، وجدول واحد بس يحمل
// passwordHash فما يقدر أي استعلام راكب/سائق يمسّه. الدوران يتشاركان كل
// صلاحيات التشغيل؛ الفرق الوحيد أن SUPER_ADMIN يدير حسابات المدراء.
enum AdminRole { SUPER_ADMIN ADMIN }

model AdminUser {
  id           String    @id @default(cuid())
  username     String    @unique
  passwordHash String                       // bcrypt — لا يُرجَع بأي endpoint
  role         AdminRole @default(ADMIN)
  active       Boolean   @default(true)     // معطّل = يحتفظ بسجله ولا يدخل
  createdAt    DateTime  @default(now())
  createdBy    String?                      // AdminUser.id — null للمزروع من البيئة
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
- `GET /auth/me` → يرجّع `{ …, gender, profileComplete }`.
- `PATCH /auth/me` `{ name?, gender? }` → تحديث جزئي (كل حقل اختياري ويُكتب وحده). **Phase 1 amendment:** `gender` (`MALE|FEMALE`) مطلوب لإكمال الملف؛ الملف **مكتمل** فقط عند ضبط الاسم **و** الجنس معاً (`profileComplete`). المستخدمون القدامى `gender=null` = غير مكتمل حتى يضبطوه. جنس غير صالح → 400.
**قبول:** رقم عراقي يستلم كود واتساب ويدخل بنجاح؛ إعادة الإرسال محدودة (rate-limit)؛ ضبط الاسم والجنس يُكمل الملف.

### `admin-auth` (Phase 1 amendment — Step 7)
الأدمن يدخل بـ**اسم مستخدم + كلمة مرور**، مو WhatsApp OTP: المجموعة داخلية
صغيرة، وإعداد واتساب لسه معلّق. الحسابات بجدول `AdminUser` منفصل.
- `POST /admin/auth/login` `{ username, password }` → JWT بادّعاء `kind=admin`.
- `GET /admin/auth/me` → `{ id, username, role }` (اللوحة تقرأ الدور من هنا، مو من فكّ الـJWT بالمتصفح).
- **SUPER_ADMIN فقط:** `POST /admin/users` · `GET /admin/users` · `PATCH /admin/users/:id` (تفعيل/تعطيل) · `POST /admin/users/:id/password`.
**أمن (غير قابل للتفاوض):** bcrypt بكلفة 12 · **كل إخفاق دخول يرجع نفس الجملة**
(اسم غير موجود = كلمة مرور خاطئة = حساب معطّل) ويحرق مقارنة bcrypt حتى للاسم
غير الموجود، فلا النصّ ولا التوقيت يكشف أي أسماء حقيقية · حدّ محاولات
**٥ / ١٥ دقيقة بمفتاح username+IP** (الـIP وحده يقفل مكتباً كاملاً، والاسم وحده
يخلّي أي شخص يقفل حساب مدير) · الحدّ الأدنى للطول ١٠ · **الهاش ما يغادر الخادم أبداً**.
**فصل الأدوار:** الاثنان يملكان كل صلاحيات التشغيل (الممرات، اعتماد السائقين،
لوحة المعلومات) لأن مبدأ الأدمن يحمل `roles:[ADMIN]`؛ `SuperAdminGuard` وحده
يحرس `/admin/users`. الـJWT يُعاد قراءة صفّه بكل طلب، فتعطيل مدير يسري فوراً
لا عند انتهاء رمزه.
**قبول:** المدير الأعلى يُزرع من البيئة ويدخل؛ مدير أنشأه يدخل؛ المدير العادي
يأخذ **403** على كل `/admin/users` ولا يرى بند التنقّل.

### `driver`
- `POST /driver/profile` (يصير سائق) · `POST /driver/vehicle` · `POST /driver/documents` (رفع) · `GET /driver/profile`.
- أدمن: `GET /admin/drivers?status=` · `POST /admin/drivers/:id/approve|reject|suspend`.
**قبول:** سائق يرفع مستمسكاته → أدمن يعتمده → يقدر يعلن رحلة.

### `corridor` (أدمن)
- `GET /corridors` (أي مستخدم مُصادَق — يرجّع `suggestedPricePerSeat` و `minPricePerSeat` و `maxPricePerSeat`) · `POST /corridors` `{ originCity, destCity, suggestedPricePerSeat, minPricePerSeat, maxPricePerSeat }` · `PATCH /corridors/:id` (أسعار/تفعيل/تعطيل). الإنشاء/التعديل **admin فقط** (RolesGuard). **Phase 1 amendment:** الأسعار الثلاثة أعداد صحيحة موجبة، ويُرفض أي طلب يكسر `min <= suggested <= max` بـ `400` عربي يسمّي الحدّ المخالف — وبالتعديل الجزئي يُدمج المُرسَل مع الصف المخزون قبل الفحص.
- **Phase 1 amendment (مدن كل المحافظات):** `originCity`/`destCity` يجب أن تكونا من قائمة المدن الرسمية (18) وإلا **400**؛ نفس المدينة للطرفين **400**؛ تكرار زوج `(origin,dest)` **409** (مع فهرس فريد بالـ DB). الأدمن ينشئ ممراً بين أي مدينتين فيصبح قابلاً للبحث/النشر فوراً.
- **Phase 1 amendment (شبكة الممرات الكاملة):** الـ seed يزرع **كل زوج مرتّب** من المحافظات الـ18 — `18 × 17 = 306` ممر، كلها `active`. كل اتجاه صف مستقل (النجف→بغداد غير بغداد→النجف) حتى يقدر الأدمن يسعّر أو يعطّل اتجاهاً دون الآخر.
**قبول:** الشبكة الكاملة (٣٠٦) موجودة وكلها مفعّلة؛ الراكب يبحث بأي زوج مدن والسائق ينشر على أي زوج؛ إعادة تشغيل الـ seed لا تغيّر شيئاً ولا تمسّ سعراً عدّله الأدمن.

#### تسعير الشبكة الأولي — من أين جاءت الأرقام

> **هذه تقديرات، مو بيانات مسح.** موجودة حتى يصير كل زوج مدن قابلاً للحجز من اليوم الأول برقم **معقول**، لا برقم **موثّق**. الأدمن يضبط كل ممر من اللوحة، والـ seed **لا يكتب فوق أي سعر معدّل**.

**المسافات.** بدل جدول مسافات يدوي بـ153 خانة، نخزن **إحداثيات تقريبية لمركز كل محافظة** (18 صفاً فقط) ونحسب المسافة بـ haversine — أقل عرضة للخطأ المطبعي، والنتيجة متماثلة تلقائياً، والإحداثية الغلط تنكشف على الخريطة بعكس خانة غلط بجدول. المصدر: `services/api/src/corridor/corridor-grid.ts`.

**معامل التواء الطريق = 1.10** (طريق فعلي ÷ خط مستقيم). **مُعايَر، مو مفترض:** قِيس مقابل تسع مسافات طرق معروفة (نجف–كربلاء ٨٠كم، بغداد–كربلاء ١٠٥، بغداد–نجف ١٦٠، بغداد–حلة ١٠٠، بغداد–بصرة ٥٥٠، بغداد–موصل ٤٠٠، بغداد–أربيل ٣٥٠، بغداد–كركوك ٢٤٠، أربيل–دهوك ١٥٠) فأعطى خطأ متوسط ~٦٪ مقابل ~٩٪ عند 1.20 و~١١٪ عند 1.25. منخفض لأن طرق العراق بين المحافظات صحراوية مستقيمة غالباً — وبالمقابل **يقلّل تقدير** الطرق الجبلية شمالاً، والأدمن يضبط الشواذ.

**الصيغة (شريحتان):**
```
السعر = 3,000  +  110 × (أول 100 كم)  +  55 × (ما بعد 100 كم)     ثم يُقرّب لأقرب 500 IQD
        └ أجرة أساس: الالتقاط، الانتظار، انحراف door-to-door بالطرفين
```
شريحتان لأن سعراً ثابتاً للكيلومتر ما ينفع لطرفَي البلد: الرحلة القصيرة تحكمها الكلفة الثابتة، والكيلومتر الإضافي بمشوار ٥٠٠كم أرخص بكثير. بسعر واحد للكيلومتر، تثبيت القصيرة يخلّي بغداد→البصرة تقريباً **ضعف** سعر المقعد الحقيقي.

**التثبيت:** المعامل 110 مختار حتى ينزل **النجف→كربلاء على ١٢٬٠٠٠ بالضبط** — السعر المستعمل فعلاً — وكل الباقي يتدرّج منه:

| المسار | طريق تقريبي | السعر المقترح |
|---|---|---|
| كربلاء→الحلة | ~٤٥ كم | ٨٬٠٠٠ |
| **النجف→كربلاء** | **~٨٢ كم** | **١٢٬٠٠٠** (مثبّت) |
| بغداد→النجف | ~١٦١ كم | ١٧٬٥٠٠ |
| بغداد→أربيل | ~٣٥٤ كم | ٢٨٬٠٠٠ |
| بغداد→البصرة | ~٤٩٣ كم | ٣٥٬٥٠٠ |
| البصرة→دهوك | ~٩١٨ كم | ٥٩٬٠٠٠ |

**الحدود:** `min = 60%` و `max = 160%` من المقترح، مقرّبة لأقرب ٥٠٠، ثم **مقصوصة** (`LEAST`/`GREATEST`) حتى يبقى `0 < min <= suggested <= max` بكل صف — نفس انضباط ترحيل «تسعير يحدده السائق»؛ التقريب لوحده يقدر يرفع `min` فوق المقترح بالأرقام الصغيرة، وممر بهذا الكسر يملأ للسائق سعراً يرفضه `POST /trips` فوراً.

**الحماية من الكتابة فوق التعديلات:** الـ seed يستعمل `createMany({ skipDuplicates: true })` — ما عنده مسار تحديث أصلاً، فما **يقدر** يمسح سعراً ضبطه الأدمن ولا يعيد تفعيل ممر عطّله عمداً. `upsert` بـ`update: {}` كان يتصرف نفس الشيء اليوم، بس يبعد تعديلاً واحداً طائشاً عن تصفير أسعار البلد كله بأول deploy.

### `trip` (جانب السائق)
- `POST /trips` `{ corridorId, departureTime | departNow, seatsTotal, pricePerSeat, tripType? }`. **Phase 1 amendment:** `tripType` (`GENERAL` افتراضياً · `WOMEN_FAMILY`). **Phase 1 amendment (تسعير يحدده السائق):** `pricePerSeat` **مطلوب** ويحدده السائق (عدد صحيح موجب، IQD)؛ يُفحص على الخادم مقابل `[minPricePerSeat, maxPricePerSeat]` للممر، وخارجها → `400` يحمل رسالة عربية تذكر المدى مع `code: "TRIP_PRICE_OUT_OF_RANGE"` و `minPricePerSeat`/`maxPricePerSeat` كأرقام (حتى يعيد تطبيق السائق عرض المدى بالأرقام العربية-الهندية). السعر يُخزَّن لقطةً على الرحلة، فتغيير الأدمن للممر لاحقاً لا يمسّ رحلة منشورة ولا أجرة حجز قائم.
- `GET /trips/mine` · `POST /trips/:id/start` → EN_ROUTE (يقفل) · `POST /trips/:id/complete` → COMPLETED (+ EarningsRecord) · `POST /trips/:id/cancel`.
**قواعد:** `seatsTotal ≤ vehicle.seats`. سائق مُعتمد فقط. `departNow=true` → departureTime=now، ونافذة صلاحية افتراضية 30 دقيقة (قابلة للتمديد). **سائق أي جنس يقدر يعلن رحلة `WOMEN_FAMILY`** (تقييد الركّاب يُفرض عند الحجز، لا عند النشر).
**قبول:** سائق مُعتمد يعلن رحلة نجف→كربلاء بمقاعد؛ تظهر OPEN.

### `booking` (جانب الراكب)
- `GET /trips/search?corridorId=&date=&fromTime=&toTime=&tripType=&driverGender=` → رحلات OPEN و seatsAvailable>0 (مع وقت، سعر، تقييم السائق، السيارة). **Phase 1 amendment:** فلاتر اختيارية `tripType` و`driverGender`؛ كل رحلة ترجع `tripType` + `driverGender` للشارات. قائمة فارغة نتيجة صالحة (توفّر السائقات ~صفر حالياً)، ليست خطأ.
- `POST /bookings` `{ tripId, pickup{lat,lng,label}, dropoff{lat,lng,label}, seatCount }` → CONFIRMED.
- `GET /bookings/mine` · `POST /bookings/:id/cancel`.
- سائق: `POST /bookings/:id/onboard` · `POST /bookings/:id/no-show`.
**⚠ قاعدة حرجة — Concurrency:** خصم `seatsAvailable` لازم يكون **transactional مع row-lock** (أو `UPDATE ... WHERE seatsAvailable >= seatCount`) لمنع overbooking عند حجزين متزامنين على آخر مقعد. الإلغاء يرجّع المقاعد.
**⚠ أهلية الجنس (Phase 1 amendment — تُفرض على الخادم قبل معاملة المقعد):** الراكب بلا جنس محدَّد → **403** (أكمل الملف)؛ على رحلة `WOMEN_FAMILY` الراكب غير الأنثى → **403**؛ رحلة `GENERAL` بلا تقييد جنس. الفحص يسبق الـ transaction فلا يُضعف ضمان المقاعد.
**قطع الحجز:** إلغاء مجاني حتى 15 دقيقة قبل المغادرة (افتراضي)؛ بعدها يُعلَّم.
**قبول:** راكبان يحجزون آخر مقعد بنفس اللحظة → واحد ينجح فقط، والمخزون صحيح؛ راكب ذكر يُرفض على رحلة نسائية، وأنثى تنجح.

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
**لوحة الأدمن:** (1) دخول باسم مستخدم + كلمة مرور · (2) Dashboard (عدّادات) · (3) اعتماد السواق + مراجعة المستمسكات · (4) مراقبة الرحلات · (5) الممرات والتسعير · (6) إدارة المدراء (**للمدير الأعلى فقط**) · (7) بحث/دعم أساسي.
> اللوحة Next.js بنفس نظام تصميم "مَسار" (صنوبري/زعفراني على ورق دافئ) وعربية RTL، والأرقام المعروضة عربية-هندية والإدخال غربي — نفس قاعدة التطبيقين.
> تصميم الشاشات تفصيلياً: يُطبَّق سكل `ui-ux-pro-max` بمرحلة الـ UI.

---

## 6. قواعد تجارية مهمة
- **مخزون المقاعد:** transactional حصراً (قسم booking).
- **التسعير (Phase 1 amendment — يحدده السائق):** **السائق** يحدد سعر المقعد عند نشر الرحلة؛ الممر يعطي **اقتراحاً** (`suggestedPricePerSeat`) وحدّين (`min`/`max`) يضبطهما الأدمن. الأجرة تبقى `fare = trip.pricePerSeat × seatCount` بلا تغيير.
  - **لماذا:** هيك تشتغل الكراجات العراقية فعلياً (السائق يعلن سعره)؛ السعر الواحد الثابت ما ينفع لمسارات تختلف مسافاتها اختلافاً كبيراً؛ ويصير بإمكان الراكب يقارن أسعار السائقين على نفس المسار.
  - **الحدود** تحمي من الخطأ المطبعي ومن الاستغلال، بلا ما تلغي حرية السائق. الترحيل اشتق حدوداً واسعة عمداً (٥٠٪ – ٢٠٠٪ من السعر القديم، مقرّبة لأقرب ٢٥٠ IQD) حتى لا يتحوّل ترحيل بيانات إلى قرار منتج صامت؛ الأدمن يضيّقها لكل ممر من اللوحة.
- **قفل الرحلة:** تلقائي عند `seatsAvailable=0` أو عند `departureTime`؛ أو يدوي ببدء السائق.
- **No-show:** السائق يعلّمها → تؤثر على سمعة الراكب (لا خصم مالي بالـ MVP).
- **إلغاء السائق للرحلة:** كل الحجوزات CANCELLED + إشعار الركّاب فوراً.
- **الهوية:** رقم الموبايل هو المفتاح؛ مستخدم واحد بدورين ممكن.
- **الجنس مطلوب (Phase 1 amendment):** `gender` يُضبط بالتسجيل؛ الملف مكتمل عند الاسم+الجنس. لا يقدر راكب بلا جنس أن يحجز أي رحلة (`403` — أكمل الملف).
- **رحلة نسائية/عائلية (`WOMEN_FAMILY`) — Phase 1 amendment:** **كل الركّاب يجب أن يكنّ إناثاً** (المرأة تحجز مقاعد إضافية للعائلة)، بينما **السائق قد يكون ذكراً أو أنثى** — يطابق واقع العرض العراقي. تُفرض الأهلية على الخادم عند `POST /bookings` **قبل** معاملة حجز المقعد (فلا تُضعف ضمان الـ transactional). الراكب قد يفلتر اختيارياً بجنس السائق (`driverGender`)، وقائمة فارغة نتيجة صالحة.

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

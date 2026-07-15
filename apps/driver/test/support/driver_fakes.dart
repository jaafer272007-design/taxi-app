import 'package:driver/driver/document_picker.dart';
import 'package:driver/driver/driver_api.dart';
import 'package:driver/driver/driver_models.dart';
import 'package:driver/trip/driver_trip_api.dart';
import 'package:driver/trip/driver_trip_models.dart';
import 'package:shared/shared.dart';

// ── DriverApi fake ───────────────────────────────────────────────────────────

/// A scriptable fake of [DriverApi]. Mutations evolve [profile] so the
/// controller's post-mutation refresh reflects the change.
class FakeDriverApi implements DriverApi {
  DriverProfile? profile;
  Object? getProfileError;
  Object? createError;
  Object? vehicleError;
  Object? uploadError;

  int createCalls = 0;
  int vehicleCalls = 0;
  int uploadCalls = 0;
  DocType? lastUploadType;
  String? lastUploadPath;

  @override
  Future<DriverProfile?> getProfile() async {
    if (getProfileError != null) throw getProfileError!;
    return profile;
  }

  @override
  Future<DriverProfile> createProfile() async {
    createCalls++;
    if (createError != null) throw createError!;
    profile = profile ?? profileFixture(status: DriverStatus.pending);
    return profile!;
  }

  @override
  Future<Vehicle> saveVehicle({
    required String make,
    required String model,
    required String plate,
    required String color,
    required int seats,
  }) async {
    vehicleCalls++;
    if (vehicleError != null) throw vehicleError!;
    final vehicle = Vehicle(
      make: make,
      model: model,
      plate: plate,
      color: color,
      seats: seats,
    );
    profile = (profile ?? profileFixture()).copyWith(vehicle: vehicle);
    return vehicle;
  }

  @override
  Future<DriverDocument> uploadDocument({
    required DocType type,
    required String filePath,
  }) async {
    uploadCalls++;
    lastUploadType = type;
    lastUploadPath = filePath;
    if (uploadError != null) throw uploadError!;
    final doc = DriverDocument(
      id: 'doc-${type.api}',
      type: type,
      status: DocStatus.pending,
    );
    final current = profile ?? profileFixture();
    final docs = [
      ...current.documents.where((d) => d.type != type),
      doc,
    ];
    profile = current.copyWith(documents: docs);
    return doc;
  }
}

/// A [DocumentPicker] that returns a fixed path (or null to simulate cancel).
class FakeDocumentPicker implements DocumentPicker {
  FakeDocumentPicker([this.pathToReturn = '/tmp/fake_doc.jpg']);

  String? pathToReturn;
  int calls = 0;

  @override
  Future<String?> pickImage() async {
    calls++;
    return pathToReturn;
  }
}

// ── DriverTripApi fake ───────────────────────────────────────────────────────

class FakeDriverTripApi implements DriverTripApi {
  List<Corridor> corridors = const [];
  Object? corridorsError;

  DriverTrip? postResult;
  Object? postError;
  int postCalls = 0;
  String? lastCorridorId;
  int? lastSeatsTotal;
  bool? lastDepartNow;
  DateTime? lastDepartureTime;
  TripType? lastTripType;

  List<DriverTrip> myTripsResult = const [];
  Object? myTripsError;

  // Trip detail / lifecycle scripting.
  List<TripBooking> tripBookingsResult = const [];

  /// When set, [completeTrip] swaps [tripBookingsResult] to this — models the
  /// backend settling ONBOARD/CONFIRMED bookings to COMPLETED on completion.
  List<TripBooking>? settledBookingsResult;
  Object? tripBookingsError;

  int startCalls = 0;
  int completeCalls = 0;
  int cancelCalls = 0;
  Object? startError;
  Object? completeError;
  Object? cancelError;

  final List<String> onboardCalls = [];
  final List<String> noShowCalls = [];
  Object? onboardError;
  Object? noShowError;

  Map<String, DriverEarnings> earningsByRange = const {};
  Object? earningsError;

  int rateCalls = 0;
  String? lastRateRiderId;
  int? lastRateScore;
  String? lastRateComment;
  Object? rateError;

  @override
  Future<List<Corridor>> getCorridors() async {
    if (corridorsError != null) throw corridorsError!;
    return corridors;
  }

  @override
  Future<DriverTrip> postTrip({
    required String corridorId,
    required int seatsTotal,
    bool departNow = false,
    DateTime? departureTime,
    TripType tripType = TripType.general,
  }) async {
    postCalls++;
    lastCorridorId = corridorId;
    lastSeatsTotal = seatsTotal;
    lastDepartNow = departNow;
    lastDepartureTime = departureTime;
    lastTripType = tripType;
    if (postError != null) throw postError!;
    return postResult ??
        tripFixture(
          corridorId: corridorId,
          seatsTotal: seatsTotal,
          tripType: tripType,
        );
  }

  @override
  Future<List<DriverTrip>> myTrips() async {
    if (myTripsError != null) throw myTripsError!;
    return myTripsResult;
  }

  @override
  Future<List<TripBooking>> tripBookings(String tripId) async {
    if (tripBookingsError != null) throw tripBookingsError!;
    return tripBookingsResult;
  }

  @override
  Future<void> startTrip(String tripId) async {
    startCalls++;
    if (startError != null) throw startError!;
  }

  @override
  Future<void> completeTrip(String tripId) async {
    completeCalls++;
    if (completeError != null) throw completeError!;
    if (settledBookingsResult != null) {
      tripBookingsResult = settledBookingsResult!;
    }
  }

  @override
  Future<void> cancelTrip(String tripId) async {
    cancelCalls++;
    if (cancelError != null) throw cancelError!;
  }

  @override
  Future<void> onboard(String bookingId) async {
    onboardCalls.add(bookingId);
    if (onboardError != null) throw onboardError!;
  }

  @override
  Future<void> noShow(String bookingId) async {
    noShowCalls.add(bookingId);
    if (noShowError != null) throw noShowError!;
  }

  @override
  Future<DriverEarnings> earnings({required String range}) async {
    if (earningsError != null) throw earningsError!;
    return earningsByRange[range] ??
        const DriverEarnings(total: 0, records: []);
  }

  @override
  Future<void> rateRider({
    required String tripId,
    required String toUserId,
    required int score,
    String? comment,
  }) async {
    rateCalls++;
    lastRateRiderId = toUserId;
    lastRateScore = score;
    lastRateComment = comment;
    if (rateError != null) throw rateError!;
  }
}

// ── Auth fake (for the smoke test) ───────────────────────────────────────────

class FakeAuthApi implements AuthApi {
  AuthSession? verifyResult;
  ApiException? verifyError;
  AuthUser? meResult;
  Object? meError;
  String? lastName;
  Gender? lastGender;

  @override
  Future<void> requestOtp(String phone) async {}

  @override
  Future<AuthSession> verifyOtp(String phone, String code) async {
    if (verifyError != null) throw verifyError!;
    return verifyResult!;
  }

  @override
  Future<AuthUser> me() async {
    if (meError != null) throw meError!;
    return meResult!;
  }

  @override
  Future<AuthUser> updateName(String name) async => fakeUser(name: name);

  @override
  Future<AuthUser> updateProfile({String? name, Gender? gender}) async {
    if (name != null) lastName = name;
    if (gender != null) lastGender = gender;
    return fakeUser(name: name ?? lastName, gender: gender ?? lastGender);
  }
}

AuthUser fakeUser({String? name, Gender? gender}) => AuthUser(
      id: 'u1',
      phone: '+9647701234567',
      name: name,
      gender: gender,
      roles: const ['DRIVER'],
      profileComplete:
          (name?.trim().isNotEmpty ?? false) && gender != null,
    );

// ── fixtures ─────────────────────────────────────────────────────────────────

const najafKarbala = Corridor(
  id: 'c1',
  originCity: 'Najaf',
  destCity: 'Karbala',
  active: true,
  pricePerSeat: 6000,
);
const karbalaNajaf = Corridor(
  id: 'c2',
  originCity: 'Karbala',
  destCity: 'Najaf',
  active: true,
  pricePerSeat: 6000,
);

Vehicle vehicleFixture({int seats = 4}) => Vehicle(
      make: 'Toyota',
      model: 'Corolla',
      plate: '12345 بغداد',
      color: 'أبيض',
      seats: seats,
    );

DriverProfile profileFixture({
  String id = 'd1',
  DriverStatus status = DriverStatus.pending,
  Vehicle? vehicle,
  List<DriverDocument> documents = const [],
  String? rejectionReason,
}) =>
    DriverProfile(
      id: id,
      status: status,
      vehicle: vehicle,
      documents: documents,
      rejectionReason: rejectionReason,
    );

DriverDocument docFixture({
  required DocType type,
  DocStatus status = DocStatus.pending,
}) =>
    DriverDocument(id: 'doc-${type.api}', type: type, status: status);

/// A profile that has uploaded all three documents (used for the pending golden).
DriverProfile pendingWithAllDocs() => profileFixture(
      status: DriverStatus.pending,
      vehicle: vehicleFixture(),
      documents: [
        for (final t in kRequiredDocs) docFixture(type: t),
      ],
    );

DriverTrip tripFixture({
  String id = 't1',
  String corridorId = 'c1',
  int hourUtc = 4,
  int minute = 30,
  int seatsTotal = 4,
  int seatsAvailable = 4,
  int price = 6000,
  TripStatus status = TripStatus.open,
  bool departNow = false,
  TripType tripType = TripType.general,
}) =>
    DriverTrip(
      id: id,
      corridorId: corridorId,
      departureTime: DateTime.utc(2026, 7, 20, hourUtc, minute),
      departNow: departNow,
      seatsTotal: seatsTotal,
      seatsAvailable: seatsAvailable,
      pricePerSeat: price,
      status: status,
      tripType: tripType,
    );

TripBooking bookingFixture({
  String id = 'b1',
  String riderId = 'r1',
  String? riderName = 'علي حسن',
  int seatCount = 1,
  String pickupLabel = 'كراج النجف',
  String dropoffLabel = 'باب القبلة',
  int fare = 6000,
  BookingStatus status = BookingStatus.confirmed,
}) =>
    TripBooking(
      id: id,
      riderId: riderId,
      riderName: riderName,
      seatCount: seatCount,
      pickupLabel: pickupLabel,
      dropoffLabel: dropoffLabel,
      fare: fare,
      status: status,
    );

EarningsRecord earningsRecordFixture({
  String id = 'e1',
  String tripId = 't1',
  int amount = 6000,
  int hourUtc = 5,
  int minute = 0,
}) =>
    EarningsRecord(
      id: id,
      tripId: tripId,
      amount: amount,
      collectedAt: DateTime.utc(2026, 7, 20, hourUtc, minute),
    );

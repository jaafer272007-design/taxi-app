/// Driver approval state (mirrors the backend `DriverStatus` enum).
enum DriverStatus { pending, approved, suspended, rejected, unknown }

DriverStatus driverStatusFrom(String? raw) => switch (raw) {
      'PENDING' => DriverStatus.pending,
      'APPROVED' => DriverStatus.approved,
      'SUSPENDED' => DriverStatus.suspended,
      'REJECTED' => DriverStatus.rejected,
      _ => DriverStatus.unknown,
    };

/// A required verification document (mirrors the backend `DocType` enum).
enum DocType { nationalId, drivingLicense, vehicleReg }

/// The three documents a driver must upload, in display order.
const List<DocType> kRequiredDocs = [
  DocType.nationalId,
  DocType.drivingLicense,
  DocType.vehicleReg,
];

extension DocTypeX on DocType {
  /// The exact enum string the backend expects (the `type` form field).
  String get api => switch (this) {
        DocType.nationalId => 'NATIONAL_ID',
        DocType.drivingLicense => 'DRIVING_LICENSE',
        DocType.vehicleReg => 'VEHICLE_REG',
      };

  String get labelAr => switch (this) {
        DocType.nationalId => 'الهوية',
        DocType.drivingLicense => 'إجازة السوق',
        DocType.vehicleReg => 'تسجيل المركبة',
      };
}

DocType? docTypeFrom(String? raw) => switch (raw) {
      'NATIONAL_ID' => DocType.nationalId,
      'DRIVING_LICENSE' => DocType.drivingLicense,
      'VEHICLE_REG' => DocType.vehicleReg,
      _ => null,
    };

/// Per-document review state (mirrors the backend `DocStatus` enum).
enum DocStatus { pending, approved, rejected, unknown }

DocStatus docStatusFrom(String? raw) => switch (raw) {
      'PENDING' => DocStatus.pending,
      'APPROVED' => DocStatus.approved,
      'REJECTED' => DocStatus.rejected,
      _ => DocStatus.unknown,
    };

/// The driver's vehicle (one per driver).
class Vehicle {
  const Vehicle({
    required this.make,
    required this.model,
    required this.plate,
    required this.color,
    required this.seats,
  });

  final String make;
  final String model;
  final String plate;
  final String color;
  final int seats;

  String get label => '$make $model';

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        make: json['make'] as String,
        model: json['model'] as String,
        plate: json['plate'] as String,
        color: json['color'] as String,
        seats: (json['seats'] as num).toInt(),
      );
}

/// An uploaded verification document. (`url` is a server filesystem path, not a
/// public HTTP URL — never render it directly; we only surface [status].)
class DriverDocument {
  const DriverDocument({required this.id, required this.type, required this.status});

  final String id;
  final DocType? type;
  final DocStatus status;

  factory DriverDocument.fromJson(Map<String, dynamic> json) => DriverDocument(
        id: json['id'] as String,
        type: docTypeFrom(json['type'] as String?),
        status: docStatusFrom(json['status'] as String?),
      );
}

/// The driver's profile: status + (optional) vehicle + uploaded documents.
/// GET /driver/profile returns the full shape; POST /driver/profile returns it
/// without vehicle/documents (both default to null/empty here).
class DriverProfile {
  const DriverProfile({
    required this.id,
    required this.status,
    this.rejectionReason,
    this.vehicle,
    this.documents = const [],
  });

  final String id;
  final DriverStatus status;
  final String? rejectionReason;
  final Vehicle? vehicle;
  final List<DriverDocument> documents;

  bool get hasVehicle => vehicle != null;

  /// The uploaded document of [type], or null if not yet uploaded.
  DriverDocument? documentFor(DocType type) {
    for (final d in documents) {
      if (d.type == type) return d;
    }
    return null;
  }

  /// All three required documents have been uploaded.
  bool get hasAllDocuments =>
      kRequiredDocs.every((t) => documentFor(t) != null);

  DriverProfile copyWith({
    DriverStatus? status,
    String? rejectionReason,
    Vehicle? vehicle,
    List<DriverDocument>? documents,
  }) =>
      DriverProfile(
        id: id,
        status: status ?? this.status,
        rejectionReason: rejectionReason ?? this.rejectionReason,
        vehicle: vehicle ?? this.vehicle,
        documents: documents ?? this.documents,
      );

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
        id: json['id'] as String,
        status: driverStatusFrom(json['status'] as String?),
        rejectionReason: json['rejectionReason'] as String?,
        vehicle: json['vehicle'] == null
            ? null
            : Vehicle.fromJson(json['vehicle'] as Map<String, dynamic>),
        documents: (json['documents'] as List<dynamic>? ?? const [])
            .map((e) => DriverDocument.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

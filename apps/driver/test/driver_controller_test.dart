import 'package:driver/driver/driver_controller.dart';
import 'package:driver/driver/driver_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

import 'support/driver_fakes.dart';

DriverController _controller(FakeDriverApi api, {FakeDocumentPicker? picker}) =>
    DriverController(api: api, picker: picker ?? FakeDocumentPicker());

void main() {
  group('DriverController onboarding', () {
    test('load: user is not a driver → profile null', () async {
      final api = FakeDriverApi()..profile = null;
      final c = _controller(api);
      await c.load();
      expect(c.loadState, DriverLoad.ready);
      expect(c.profile, isNull);
      expect(c.isDriver, isFalse);
      expect(c.status, DriverStatus.unknown);
    });

    test('load: error surfaces an Arabic message', () async {
      final api = FakeDriverApi()..getProfileError = const ApiException('خطأ ما.');
      final c = _controller(api);
      await c.load();
      expect(c.loadState, DriverLoad.error);
      expect(c.loadError, 'خطأ ما.');
    });

    test('becomeDriver → PENDING profile with no vehicle yet', () async {
      final api = FakeDriverApi();
      final c = _controller(api);
      await c.load();
      final ok = await c.becomeDriver();
      expect(ok, isTrue);
      expect(api.createCalls, 1);
      expect(c.isDriver, isTrue);
      expect(c.status, DriverStatus.pending);
      expect(c.profile!.hasVehicle, isFalse);
    });

    test('saveVehicle attaches the vehicle (flow can advance to documents)',
        () async {
      final api = FakeDriverApi()
        ..profile = profileFixture(status: DriverStatus.pending);
      final c = _controller(api);
      await c.load();
      final ok = await c.saveVehicle(
        make: 'Toyota',
        model: 'Corolla',
        plate: '12345',
        color: 'أبيض',
        seats: 4,
      );
      expect(ok, isTrue);
      expect(api.vehicleCalls, 1);
      expect(c.profile!.hasVehicle, isTrue);
      expect(c.profile!.vehicle!.seats, 4);
      expect(c.profile!.hasAllDocuments, isFalse);
    });

    test('uploading all three documents → hasAllDocuments becomes true',
        () async {
      final api = FakeDriverApi()
        ..profile = profileFixture(
          status: DriverStatus.pending,
          vehicle: vehicleFixture(),
        );
      final c = _controller(api);
      await c.load();
      for (final type in kRequiredDocs) {
        final err = await c.pickAndUploadDocument(type);
        expect(err, isNull);
      }
      expect(api.uploadCalls, 3);
      expect(c.profile!.hasAllDocuments, isTrue);
    });

    test('pickAndUpload: cancelling the picker is a no-op', () async {
      final api = FakeDriverApi()
        ..profile = profileFixture(
          status: DriverStatus.pending,
          vehicle: vehicleFixture(),
        );
      final c = _controller(api, picker: FakeDocumentPicker(null)); // cancel
      await c.load();
      final err = await c.pickAndUploadDocument(DocType.nationalId);
      expect(err, isNull);
      expect(api.uploadCalls, 0);
      expect(c.profile!.documentFor(DocType.nationalId), isNull);
    });

    test('upload error surfaces the backend Arabic message', () async {
      final api = FakeDriverApi()
        ..profile = profileFixture(
          status: DriverStatus.pending,
          vehicle: vehicleFixture(),
        )
        ..uploadError = const ApiException('نوع الملف غير مدعوم (صورة أو PDF فقط).');
      final c = _controller(api);
      await c.load();
      final err = await c.pickAndUploadDocument(DocType.drivingLicense);
      expect(err, contains('غير مدعوم'));
    });

    test('approved profile flags isApproved', () async {
      final api = FakeDriverApi()
        ..profile = profileFixture(
          status: DriverStatus.approved,
          vehicle: vehicleFixture(seats: 5),
        );
      final c = _controller(api);
      await c.load();
      expect(c.isApproved, isTrue);
    });
  });
}

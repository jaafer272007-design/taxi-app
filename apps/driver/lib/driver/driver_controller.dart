import 'package:flutter/foundation.dart';
import 'package:shared/shared.dart';

import 'document_picker.dart';
import 'driver_api.dart';
import 'driver_models.dart';

enum DriverLoad { loading, error, ready }

/// Owns the driver's onboarding/verification state: loading the profile, becoming
/// a driver, saving the vehicle, and uploading documents. The onboarding router
/// derives which screen to show from [profile] + [status].
class DriverController extends ChangeNotifier {
  DriverController({required DriverApi api, required DocumentPicker picker})
      : _api = api,
        _picker = picker;

  final DriverApi _api;
  final DocumentPicker _picker;

  DriverLoad _load = DriverLoad.loading;
  DriverProfile? _profile;
  String? _loadError;
  bool _busy = false;
  String? _actionError;
  final Set<DocType> _uploading = {};

  DriverLoad get loadState => _load;
  DriverProfile? get profile => _profile;
  String? get loadError => _loadError;

  /// A become-driver / save-vehicle action is in flight.
  bool get busy => _busy;
  String? get actionError => _actionError;

  DriverStatus get status => _profile?.status ?? DriverStatus.unknown;
  bool get isDriver => _profile != null;
  bool get isApproved => status == DriverStatus.approved;
  bool isUploading(DocType type) => _uploading.contains(type);

  /// Load the current driver profile (null when the user isn't a driver yet).
  Future<void> load() async {
    _load = DriverLoad.loading;
    _loadError = null;
    notifyListeners();
    try {
      _profile = await _api.getProfile();
      _load = DriverLoad.ready;
    } on ApiException catch (e) {
      _loadError = e.message;
      _load = DriverLoad.error;
    } catch (_) {
      _loadError = 'تعذّر تحميل حسابك. حاول مرة أخرى.';
      _load = DriverLoad.error;
    } finally {
      notifyListeners();
    }
  }

  /// "كن سائقاً" → create the driver profile (PENDING).
  Future<bool> becomeDriver() => _mutate(() async {
        _profile = await _api.createProfile();
      });

  /// Save the vehicle, then refresh the profile so the flow advances.
  Future<bool> saveVehicle({
    required String make,
    required String model,
    required String plate,
    required String color,
    required int seats,
  }) =>
      _mutate(() async {
        await _api.saveVehicle(
          make: make,
          model: model,
          plate: plate,
          color: color,
          seats: seats,
        );
        _profile = await _api.getProfile();
      });

  /// Pick an image for [type] and upload it, then refresh the profile. Returns
  /// null on success or when the user cancels the picker; otherwise an Arabic
  /// error message.
  Future<String?> pickAndUploadDocument(DocType type) async {
    if (_uploading.contains(type)) return null;

    String? path;
    try {
      path = await _picker.pickImage();
    } catch (_) {
      return 'تعذّر فتح المعرض. حاول مرة أخرى.';
    }
    if (path == null) return null; // cancelled

    _uploading.add(type);
    _actionError = null;
    notifyListeners();
    try {
      await _api.uploadDocument(type: type, filePath: path);
      _profile = await _api.getProfile();
      return null;
    } on ApiException catch (e) {
      _actionError = e.message;
      return e.message;
    } catch (_) {
      const msg = 'تعذّر رفع المستند. حاول مرة أخرى.';
      _actionError = msg;
      return msg;
    } finally {
      _uploading.remove(type);
      notifyListeners();
    }
  }

  void clearActionError() {
    if (_actionError == null) return;
    _actionError = null;
    notifyListeners();
  }

  Future<bool> _mutate(Future<void> Function() action) async {
    if (_busy) return false;
    _busy = true;
    _actionError = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      _actionError = e.message;
      return false;
    } catch (_) {
      _actionError = 'حدث خطأ غير متوقع. حاول مرة أخرى.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

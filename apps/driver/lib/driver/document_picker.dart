/// Picks a document image for upload. Abstracted (no `image_picker` import here)
/// so the controller and tests never depend on the platform plugin; the real
/// implementation lives in image_picker_document_picker.dart (wired in main).
abstract interface class DocumentPicker {
  /// Returns the picked image file path, or null if the user cancelled.
  Future<String?> pickImage();
}

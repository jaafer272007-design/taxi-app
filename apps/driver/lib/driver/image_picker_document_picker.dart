import 'package:image_picker/image_picker.dart';

import 'document_picker.dart';

/// Production [DocumentPicker] backed by the gallery image picker. Only wired in
/// `main.dart`; controllers/tests use the [DocumentPicker] interface + a fake.
class ImagePickerDocumentPicker implements DocumentPicker {
  ImagePickerDocumentPicker([ImagePicker? picker])
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    return file?.path;
  }
}

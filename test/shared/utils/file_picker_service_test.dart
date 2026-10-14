import 'package:flutter_test/flutter_test.dart';
import 'package:tachyon/shared/utils/file_picker_service.dart';

void main() {
  group('FilePickerService', () {
    test('pickDirectory method signature and interface', () {
      expect(FilePickerService.pickDirectory, isA<Function>());
    });

    test('pickImage method signature and interface', () {
      expect(FilePickerService.pickImage, isA<Function>());
    });
  });
}

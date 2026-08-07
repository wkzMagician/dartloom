import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses a meaningful default tray tooltip', () {
    expect(DartloomResidentController().tooltip, 'Dartloom application');
  });
}

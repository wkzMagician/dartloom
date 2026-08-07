import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:flutter_test/flutter_test.dart';

final class TestResidentService implements ResidentService {
  bool initialized = false;
  @override
  Future<void> dispose() async => initialized = false;
  @override
  Future<void> initialize({required String iconPath}) async =>
      initialized = true;
  @override
  Future<void> quit() async {}
  @override
  Future<void> restore() async {}
}

void main() {
  test('resident lifecycle is platform neutral', () async {
    final service = TestResidentService();
    await service.initialize(iconPath: 'icon.ico');
    expect(service.initialized, isTrue);
    await service.dispose();
    expect(service.initialized, isFalse);
  });
}

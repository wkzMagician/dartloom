import 'package:dartloom_autostart/dartloom_autostart.dart';
import 'package:test/test.dart';

void main() {
  test('autostart can be toggled through the platform-neutral API', () async {
    final service = MemoryAutostartService();
    await service.enable();
    expect(await service.isEnabled(), isTrue);
    await service.disable();
    expect(await service.isEnabled(), isFalse);
  });
}

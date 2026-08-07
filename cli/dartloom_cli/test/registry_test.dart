import 'package:dartloom/dartloom.dart';
import 'package:test/test.dart';

void main() {
  test('registry exposes metadata for every capability', () {
    expect(CapabilityRegistry.all.keys, containsAll(Capability.values));
    expect(CapabilityRegistry.parse('autostart'), Capability.autostart);
  });

  test('registry rejects invalid capability', () {
    expect(() => CapabilityRegistry.parse('unknown'), throwsArgumentError);
  });
}

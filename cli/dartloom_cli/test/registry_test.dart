import 'dart:io';

import 'package:dartloom/dartloom.dart';
import 'package:test/test.dart';

void main() {
  test('registry exposes metadata for every capability', () {
    expect(CapabilityRegistry.all.keys, containsAll(Capability.values));
    expect(CapabilityRegistry.parse('autostart'), Capability.autostart);
    expect(CapabilityRegistry.parse('localization'), Capability.localization);
    expect(CapabilityRegistry.parse('resident'), Capability.resident);
    expect(CapabilityRegistry.parse('messaging'), Capability.messaging);
    expect(CapabilityRegistry.parse('pairing'), Capability.pairing);
    expect(CapabilityRegistry.parse('singleton'), Capability.singleton);
  });

  test('registry rejects invalid capability', () {
    expect(() => CapabilityRegistry.parse('unknown'), throwsArgumentError);
  });

  test('registry separates native file storage and web pairing adapters', () {
    final storage = CapabilityRegistry.all[Capability.storage]!;
    final text = storage.implementations
        .firstWhere((implementation) => implementation.id == 'text_file');
    expect(text.platforms, isNot(contains(TargetPlatform.web)));

    final pairing = CapabilityRegistry.all[Capability.pairing]!;
    expect(pairing.platforms, contains(TargetPlatform.web));
    final relay = pairing.implementations
        .firstWhere((implementation) => implementation.id == 'relay_pairing');
    expect(relay.platforms, {TargetPlatform.web});
  });

  test('WebDAV adapter contributes Android Internet permission', () async {
    final manifest = File.fromUri(
      Directory.current.uri.resolve(
        '../../packages/dartloom_sync_webdav/android/src/main/AndroidManifest.xml',
      ),
    );

    expect(
        await manifest.readAsString(), contains('android.permission.INTERNET'));
  });
}

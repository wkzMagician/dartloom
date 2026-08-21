import 'dart:convert';
import 'dart:io';

import 'package:dartloom_pairing/mdns.dart';
import 'package:test/test.dart';

void main() {
  test('builds a DNS-SD announcement with a pairing TXT record', () {
    final packet = MdnsPacketBuilder.serviceAnnouncement(
      serviceType: '_actent._tcp.local',
      serviceInstance: 'device._actent._tcp.local',
      hostName: 'device.local',
      address: InternetAddress.loopbackIPv4,
      port: 4321,
      deviceId: 'device',
      displayName: 'Desk;One',
      platform: 'windows',
      fingerprint: 'abcd',
      ttl: const Duration(seconds: 120),
    );
    final body = utf8.decode(packet, allowMalformed: true);
    expect(body, contains('pairingAvailable'));
    expect(body, contains('Desk%3BOne'));
    expect(packet.length, greaterThan(40));
  });
}

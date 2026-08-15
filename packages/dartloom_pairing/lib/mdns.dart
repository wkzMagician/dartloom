import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:multicast_dns/multicast_dns.dart';

import 'pairing_contracts.dart';

export 'pairing_contracts.dart' show PairingAdvertisement;

const _mdnsAddress = '224.0.0.251';
const _mdnsPort = 5353;

abstract interface class PairingDiscovery {
  Stream<PairingAdvertisement> discover();
}

/// Publishes the short-lived LAN pairing service using DNS-SD/mDNS.
///
/// The TXT record is a locator only. The pairing channel must still verify the
/// device key and short code before a Device is persisted.
class MdnsPairingAdvertiser {
  MdnsPairingAdvertiser({
    required this.deviceId,
    required this.displayName,
    required this.platform,
    required this.fingerprint,
    required this.port,
    this.serviceType = '_pigeon._tcp.local',
    this.ttl = const Duration(seconds: 120),
    this.advertisedAddress,
    this.socketFactory = RawDatagramSocket.bind,
  });

  final String deviceId;
  final String displayName;
  final String platform;
  final String fingerprint;
  final int port;
  final String serviceType;
  final Duration ttl;
  final InternetAddress? advertisedAddress;
  final Future<RawDatagramSocket> Function(
    InternetAddress address,
    int port, {
    bool reuseAddress,
    bool reusePort,
    int ttl,
  }) socketFactory;

  RawDatagramSocket? _socket;
  Timer? _refresh;
  InternetAddress? _address;

  bool get isRunning => _socket != null;

  String get serviceInstance => '${_safeLabel(deviceId)}.$serviceType';

  String get hostName => '${_safeLabel(deviceId)}.local';

  Future<void> start() async {
    if (_socket != null) return;
    if (port <= 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'must be a valid TCP port');
    }
    final address = advertisedAddress ?? await _firstLocalIpv4();
    final socket = await socketFactory(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
      reusePort: false,
      ttl: 1,
    );
    _socket = socket;
    _address = address;
    _announce();
    _refresh = Timer.periodic(ttl ~/ 2, (_) => _announce());
  }

  Future<void> stop() async {
    final socket = _socket;
    if (socket == null) return;
    _refresh?.cancel();
    _refresh = null;
    final goodbye = MdnsPacketBuilder.serviceAnnouncement(
      serviceType: serviceType,
      serviceInstance: serviceInstance,
      hostName: hostName,
      address: _address!,
      port: port,
      deviceId: deviceId,
      displayName: displayName,
      platform: platform,
      fingerprint: fingerprint,
      ttl: Duration.zero,
    );
    socket.send(goodbye, InternetAddress(_mdnsAddress), _mdnsPort);
    socket.close();
    _socket = null;
    _address = null;
  }

  void _announce() {
    final socket = _socket;
    final address = _address;
    if (socket == null || address == null) return;
    final packet = MdnsPacketBuilder.serviceAnnouncement(
      serviceType: serviceType,
      serviceInstance: serviceInstance,
      hostName: hostName,
      address: address,
      port: port,
      deviceId: deviceId,
      displayName: displayName,
      platform: platform,
      fingerprint: fingerprint,
      ttl: ttl,
    );
    socket.send(packet, InternetAddress(_mdnsAddress), _mdnsPort);
  }
}

/// Resolves DNS-SD advertisements published by [MdnsPairingAdvertiser].
class MdnsPairingDiscovery implements PairingDiscovery {
  MdnsPairingDiscovery({
    this.serviceName = '_pigeon._tcp.local',
    this.lookupTimeout = const Duration(seconds: 3),
  });

  final String serviceName;
  final Duration lookupTimeout;

  @override
  Stream<PairingAdvertisement> discover() async* {
    final client = MDnsClient();
    await client.start();
    try {
      await for (final pointer in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(serviceName),
        timeout: lookupTimeout,
      )) {
        try {
          final service = await client
              .lookup<SrvResourceRecord>(
                ResourceRecordQuery.service(pointer.domainName),
                timeout: lookupTimeout,
              )
              .first;
          final text = await client
              .lookup<TxtResourceRecord>(
                ResourceRecordQuery.text(pointer.domainName),
                timeout: lookupTimeout,
              )
              .first;
          final values = _parseTxt(text.text);
          if (values['state'] != 'pairingAvailable' || service.port <= 0) {
            continue;
          }
          final deviceId = values['deviceId'];
          final displayName = values['displayName'];
          final platform = values['platform'];
          final fingerprint = values['fingerprint'];
          if ([
            deviceId,
            displayName,
            platform,
            fingerprint,
          ].any((value) => value == null || value.isEmpty)) {
            continue;
          }
          yield PairingAdvertisement(
            deviceId: deviceId!,
            displayName: displayName!,
            platform: platform!,
            fingerprint: fingerprint!,
            host: service.target,
            port: service.port,
          );
        } on Object {
          // Ignore one malformed service and continue discovering others.
        }
      }
    } finally {
      client.stop();
    }
  }
}

class MdnsPacketBuilder {
  const MdnsPacketBuilder._();

  static Uint8List serviceAnnouncement({
    required String serviceType,
    required String serviceInstance,
    required String hostName,
    required InternetAddress address,
    required int port,
    required String deviceId,
    required String displayName,
    required String platform,
    required String fingerprint,
    required Duration ttl,
  }) {
    final records = <Uint8List>[
      _record(_name(serviceType), 12, ttl.inSeconds, _name(serviceInstance)),
      _record(
        _name(serviceInstance),
        33,
        ttl.inSeconds,
        Uint8List.fromList([
          ..._uint16(0),
          ..._uint16(0),
          ..._uint16(port),
          ..._name(hostName),
        ]),
      ),
      _record(
        _name(serviceInstance),
        16,
        ttl.inSeconds,
        _txt(<String>[
          'state=pairingAvailable',
          'deviceId=${_escapeTxt(deviceId)}',
          'displayName=${_escapeTxt(displayName)}',
          'platform=${_escapeTxt(platform)}',
          'fingerprint=${_escapeTxt(fingerprint)}',
        ]),
      ),
      _record(
        _name(hostName),
        1,
        ttl.inSeconds,
        Uint8List.fromList(address.rawAddress),
      ),
    ];
    final header = BytesBuilder(copy: false)
      ..add(_uint16(0))
      ..add(_uint16(0x8400))
      ..add(_uint16(0))
      ..add(_uint16(records.length))
      ..add(_uint16(0))
      ..add(_uint16(0));
    for (final record in records) {
      header.add(record);
    }
    return header.takeBytes();
  }

  static Uint8List _record(Uint8List name, int type, int ttl, Uint8List data) {
    final builder = BytesBuilder(copy: false)
      ..add(name)
      ..add(_uint16(type))
      ..add(_uint16(1))
      ..add(_uint32(ttl < 0 ? 0 : ttl))
      ..add(_uint16(data.length))
      ..add(data);
    return builder.takeBytes();
  }

  static Uint8List _name(String value) {
    final builder = BytesBuilder(copy: false);
    for (final label in value.split('.')) {
      final bytes = utf8.encode(label);
      if (bytes.isEmpty || bytes.length > 63) {
        throw FormatException('invalid DNS label: $label');
      }
      builder
        ..addByte(bytes.length)
        ..add(bytes);
    }
    builder.addByte(0);
    return builder.takeBytes();
  }

  static Uint8List _txt(List<String> values) {
    final builder = BytesBuilder(copy: false);
    for (final value in values) {
      final bytes = utf8.encode(value);
      if (bytes.length > 255) throw FormatException('TXT value is too long');
      builder
        ..addByte(bytes.length)
        ..add(bytes);
    }
    return builder.takeBytes();
  }

  static Uint8List _uint16(int value) =>
      Uint8List.fromList([(value >> 8) & 0xff, value & 0xff]);

  static Uint8List _uint32(int value) => Uint8List.fromList([
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff,
      ]);
}

Map<String, String> _parseTxt(String value) {
  final result = <String, String>{};
  for (final item in value.split(';')) {
    final separator = item.indexOf('=');
    if (separator <= 0) continue;
    final key = item.substring(0, separator);
    final encoded = item.substring(separator + 1);
    result[key] = Uri.decodeComponent(encoded);
  }
  return result;
}

String _escapeTxt(String value) => Uri.encodeComponent(value);

String _safeLabel(String value) {
  final label = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
  if (label.isEmpty) return 'pigeon-device';
  final end = label.length > 63 ? 63 : label.length;
  return label.substring(0, end);
}

Future<InternetAddress> _firstLocalIpv4() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (!address.isLoopback) return address;
    }
  }
  return InternetAddress.loopbackIPv4;
}

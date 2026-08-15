import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'mdns.dart' as mdns;
import 'pairing_contracts.dart';

enum PairingStatus {
  created,
  accepted,
  confirmed,
  rejected,
  cancelled,
  expired,
}

class PairingInvite {
  PairingInvite({
    required this.nonce,
    required this.issuerDeviceId,
    required this.issuerPublicKey,
    required this.relayUrl,
    required this.temporaryTopic,
    this.issuerRelayTopic = '',
    this.issuerLanHost,
    this.issuerLanPort,
    this.issuerPairingLanPort,
    this.issuerCertificateSha256,
    required this.shortCode,
    required this.createdAt,
    required this.expiresAt,
    this.version = 1,
  });

  final int version;
  final String nonce;
  final String issuerDeviceId;
  final String issuerPublicKey;
  final String relayUrl;
  final String temporaryTopic;
  final String issuerRelayTopic;
  final String? issuerLanHost;
  final int? issuerLanPort;
  final int? issuerPairingLanPort;
  final String? issuerCertificateSha256;
  final String shortCode;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now.toUtc());

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'nonce': nonce,
        'issuerDeviceId': issuerDeviceId,
        'issuerPublicKey': issuerPublicKey,
        'relayUrl': relayUrl,
        'temporaryTopic': temporaryTopic,
        'issuerRelayTopic': issuerRelayTopic,
        if (issuerLanHost != null) 'issuerLanHost': issuerLanHost,
        if (issuerLanPort != null) 'issuerLanPort': issuerLanPort,
        if (issuerPairingLanPort != null)
          'issuerPairingLanPort': issuerPairingLanPort,
        if (issuerCertificateSha256 != null)
          'issuerCertificateSha256': issuerCertificateSha256,
        'shortCode': shortCode,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      };

  String toUri() {
    final token =
        base64UrlEncode(utf8.encode(jsonEncode(toJson()))).replaceAll('=', '');
    return 'pigeon://pair/v1/$token';
  }

  factory PairingInvite.fromUri(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'pigeon' || uri.host != 'pair') {
      throw const PairingValidationException('invalid pigeon pairing URI');
    }
    if (uri.pathSegments.length != 2 || uri.pathSegments.first != 'v1') {
      throw const PairingValidationException('unsupported pairing URI version');
    }
    try {
      final encoded = uri.pathSegments[1];
      final padded = encoded.padRight(((encoded.length + 3) ~/ 4) * 4, '=');
      final decoded = utf8.decode(base64Url.decode(padded));
      final json = jsonDecode(decoded);
      if (json is! Map) throw const FormatException('invite must be an object');
      final map = Map<String, Object?>.from(json);
      _rejectUnknown(map, const {
        'version',
        'nonce',
        'issuerDeviceId',
        'issuerPublicKey',
        'relayUrl',
        'temporaryTopic',
        'issuerRelayTopic',
        'issuerLanHost',
        'issuerLanPort',
        'issuerPairingLanPort',
        'issuerCertificateSha256',
        'shortCode',
        'createdAt',
        'expiresAt',
      });
      final version = _int(map['version'], 'version');
      if (version != 1) {
        throw PairingValidationException('unsupported invite version $version');
      }
      final issuerRelayTopic = map['issuerRelayTopic'];
      final issuerLanHost = map['issuerLanHost'];
      final issuerLanPort = map['issuerLanPort'];
      final issuerPairingLanPort = map['issuerPairingLanPort'];
      final issuerCertificateSha256 = map['issuerCertificateSha256'];
      if (issuerRelayTopic != null && issuerRelayTopic is! String) {
        throw const PairingValidationException(
          'issuerRelayTopic must be a string',
        );
      }
      if (issuerLanHost != null && issuerLanHost is! String) {
        throw const PairingValidationException(
          'issuerLanHost must be a string',
        );
      }
      _validatePort(issuerLanPort, 'issuerLanPort');
      _validatePort(issuerPairingLanPort, 'issuerPairingLanPort');
      if (issuerCertificateSha256 != null &&
          issuerCertificateSha256 is! String) {
        throw const PairingValidationException(
          'issuerCertificateSha256 must be a string',
        );
      }
      return PairingInvite(
        version: version,
        nonce: _string(map['nonce'], 'nonce'),
        issuerDeviceId: _string(map['issuerDeviceId'], 'issuerDeviceId'),
        issuerPublicKey: _string(map['issuerPublicKey'], 'issuerPublicKey'),
        relayUrl: _string(map['relayUrl'], 'relayUrl'),
        temporaryTopic: _string(map['temporaryTopic'], 'temporaryTopic'),
        issuerRelayTopic: issuerRelayTopic as String? ?? '',
        issuerLanHost: _optionalString(issuerLanHost, 'issuerLanHost'),
        issuerLanPort: issuerLanPort as int?,
        issuerPairingLanPort: issuerPairingLanPort as int?,
        issuerCertificateSha256: _optionalString(
          issuerCertificateSha256,
          'issuerCertificateSha256',
        ),
        shortCode: _code(map['shortCode']),
        createdAt: _date(map['createdAt'], 'createdAt'),
        expiresAt: _date(map['expiresAt'], 'expiresAt'),
      );
    } on PairingValidationException {
      rethrow;
    } on Object catch (error) {
      throw PairingValidationException('invalid invite payload: $error');
    }
  }
}

class PairingValidationException implements Exception {
  const PairingValidationException(this.message);

  final String message;

  @override
  String toString() => 'Invalid pairing invite: $message';
}

class PairingSession {
  PairingSession(this.invite) : status = PairingStatus.created;

  final PairingInvite invite;
  PairingStatus status;
  String? remoteDeviceId;
  String? remotePublicKey;

  bool get isTerminal => switch (status) {
        PairingStatus.confirmed ||
        PairingStatus.rejected ||
        PairingStatus.cancelled ||
        PairingStatus.expired =>
          true,
        PairingStatus.created || PairingStatus.accepted => false,
      };

  void accept({
    required String remoteDeviceId,
    required String remotePublicKey,
    DateTime? now,
  }) {
    _ensureUsable(now);
    if (status != PairingStatus.created) {
      throw StateError('pairing invite is not awaiting acceptance');
    }
    this.remoteDeviceId = remoteDeviceId;
    this.remotePublicKey = remotePublicKey;
    status = PairingStatus.accepted;
  }

  void confirm(String code, {DateTime? now}) {
    _ensureUsable(now);
    if (status != PairingStatus.accepted || code != invite.shortCode) {
      throw const PairingValidationException('short code confirmation failed');
    }
    status = PairingStatus.confirmed;
  }

  void reject({DateTime? now}) {
    _ensureUsable(now);
    status = PairingStatus.rejected;
  }

  void cancel({DateTime? now}) {
    _ensureUsable(now);
    status = PairingStatus.cancelled;
  }

  void expire({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    if (!isTerminal && invite.isExpired(current)) {
      status = PairingStatus.expired;
    }
  }

  void _ensureUsable(DateTime? now) {
    expire(now: now);
    if (status == PairingStatus.expired) {
      throw const PairingValidationException('pairing invite has expired');
    }
    if (isTerminal) throw StateError('pairing session is already terminal');
  }
}

class PairingCoordinator {
  PairingCoordinator({this.clock = _systemClock, Random? random})
      : _random = random ?? Random.secure();

  final DateTime Function() clock;
  final Random _random;
  final Map<String, PairingSession> _sessions = {};

  PairingSession createInvite({
    required String issuerDeviceId,
    required String issuerPublicKey,
    required String relayUrl,
    required String temporaryTopic,
    String issuerRelayTopic = '',
    String? issuerLanHost,
    int? issuerLanPort,
    int? issuerPairingLanPort,
    String? issuerCertificateSha256,
    Duration lifetime = const Duration(minutes: 10),
  }) {
    if (lifetime <= Duration.zero) {
      throw ArgumentError.value(lifetime, 'lifetime');
    }
    final createdAt = clock().toUtc();
    final invite = PairingInvite(
      nonce: _randomToken(24),
      issuerDeviceId: issuerDeviceId,
      issuerPublicKey: issuerPublicKey,
      relayUrl: relayUrl,
      temporaryTopic: temporaryTopic,
      issuerRelayTopic: issuerRelayTopic,
      issuerLanHost: issuerLanHost,
      issuerLanPort: issuerLanPort,
      issuerPairingLanPort: issuerPairingLanPort,
      issuerCertificateSha256: issuerCertificateSha256,
      shortCode: _randomCode(),
      createdAt: createdAt,
      expiresAt: createdAt.add(lifetime),
    );
    final session = PairingSession(invite);
    _sessions[invite.nonce] = session;
    return session;
  }

  PairingSession? find(String nonce) => _sessions[nonce];

  void expireAll() {
    for (final session in _sessions.values) {
      session.expire(now: clock());
    }
  }

  String _randomToken(int length) => List<int>.generate(
        length,
        (_) => _random.nextInt(256),
      ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();

  String _randomCode() =>
      List<int>.generate(6, (_) => _random.nextInt(10)).join();
}

class FakePairingDiscovery implements mdns.PairingDiscovery {
  final StreamController<PairingAdvertisement> _controller =
      StreamController<PairingAdvertisement>.broadcast();

  @override
  Stream<PairingAdvertisement> discover() => _controller.stream;

  void advertise(PairingAdvertisement advertisement) =>
      _controller.add(advertisement);

  Future<void> close() => _controller.close();
}

abstract interface class PairingCodePresenter {
  Future<void> show(String inviteUri);
}

abstract interface class PairingCodeScanner {
  Future<String?> scan();
}

void _validatePort(Object? value, String field) {
  if (value != null && (value is! int || value <= 0 || value > 65535)) {
    throw PairingValidationException('$field must be a valid port');
  }
}

String _string(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw PairingValidationException('$field must be non-empty');
  }
  return value;
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw PairingValidationException('$field must be non-empty');
  }
  return value;
}

int _int(Object? value, String field) {
  if (value is! int) {
    throw PairingValidationException('$field must be an integer');
  }
  return value;
}

String _code(Object? value) {
  final code = _string(value, 'shortCode');
  if (!RegExp(r'^\d{6}$').hasMatch(code)) {
    throw const PairingValidationException('shortCode must be six digits');
  }
  return code;
}

DateTime _date(Object? value, String field) {
  final text = _string(value, field);
  final date = DateTime.tryParse(text);
  if (date == null) throw PairingValidationException('$field must be ISO-8601');
  return date.toUtc();
}

DateTime _systemClock() => DateTime.now().toUtc();

void _rejectUnknown(Map<String, Object?> json, Set<String> allowed) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw PairingValidationException(
      'unknown invite fields: ${unknown.join(', ')}',
    );
  }
}

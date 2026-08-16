import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'pairing_protocol.dart';

class PairingAcceptance {
  const PairingAcceptance({
    required this.nonce,
    required this.shortCode,
    required this.deviceId,
    required this.publicKey,
    required this.displayName,
    required this.platform,
    required this.relayUrl,
    required this.relayTopic,
    this.lanHost,
    this.lanPort,
    this.certificateSha256,
    required this.proof,
    required this.createdAt,
  });

  final String nonce;
  final String shortCode;
  final String deviceId;
  final String publicKey;
  final String displayName;
  final String platform;
  final String relayUrl;
  final String relayTopic;
  final String? lanHost;
  final int? lanPort;
  final String? certificateSha256;
  final String proof;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'pairingAccepted',
    'version': 1,
    'nonce': nonce,
    'shortCode': shortCode,
    'deviceId': deviceId,
    'publicKey': publicKey,
    'displayName': displayName,
    'platform': platform,
    'relayUrl': relayUrl,
    'relayTopic': relayTopic,
    if (lanHost != null) 'lanHost': lanHost,
    if (lanPort != null) 'lanPort': lanPort,
    if (certificateSha256 != null) 'certificateSha256': certificateSha256,
    'proof': proof,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory PairingAcceptance.fromJson(Object? value) {
    final json = _map(value, 'acceptance');
    _rejectUnknown(json, const {
      'type',
      'version',
      'nonce',
      'shortCode',
      'deviceId',
      'publicKey',
      'displayName',
      'platform',
      'relayUrl',
      'relayTopic',
      'lanHost',
      'lanPort',
      'certificateSha256',
      'proof',
      'createdAt',
    });
    if (json['type'] != 'pairingAccepted' || json['version'] != 1) {
      throw const FormatException('unsupported pairing acceptance');
    }
    return PairingAcceptance(
      nonce: _required(json['nonce'], 'nonce'),
      shortCode: _required(json['shortCode'], 'shortCode'),
      deviceId: _required(json['deviceId'], 'deviceId'),
      publicKey: _required(json['publicKey'], 'publicKey'),
      displayName: _required(json['displayName'], 'displayName'),
      platform: _required(json['platform'], 'platform'),
      relayUrl: _required(json['relayUrl'], 'relayUrl'),
      relayTopic: _required(json['relayTopic'], 'relayTopic'),
      lanHost: _optionalString(json['lanHost'], 'lanHost'),
      lanPort: _optionalPort(json['lanPort'], 'lanPort'),
      certificateSha256: _optionalString(
        json['certificateSha256'],
        'certificateSha256',
      ),
      proof: _required(json['proof'], 'proof'),
      createdAt: _date(json['createdAt'], 'createdAt'),
    );
  }

  bool verify(PairingInvite invite) =>
      nonce == invite.nonce &&
      shortCode == invite.shortCode &&
      proof ==
          pairingProof(
            nonce: nonce,
            shortCode: shortCode,
            deviceId: deviceId,
            publicKey: publicKey,
          );
}

class PairingConfirmation {
  const PairingConfirmation({
    required this.nonce,
    required this.shortCode,
    required this.issuerDeviceId,
    required this.acceptorDeviceId,
    required this.proof,
  });

  final String nonce;
  final String shortCode;
  final String issuerDeviceId;
  final String acceptorDeviceId;
  final String proof;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'pairingConfirmed',
    'version': 1,
    'nonce': nonce,
    'shortCode': shortCode,
    'issuerDeviceId': issuerDeviceId,
    'acceptorDeviceId': acceptorDeviceId,
    'proof': proof,
  };

  factory PairingConfirmation.fromJson(Object? value) {
    final json = _map(value, 'confirmation');
    _rejectUnknown(json, const {
      'type',
      'version',
      'nonce',
      'shortCode',
      'issuerDeviceId',
      'acceptorDeviceId',
      'proof',
    });
    if (json['type'] != 'pairingConfirmed' || json['version'] != 1) {
      throw const FormatException('unsupported pairing confirmation');
    }
    return PairingConfirmation(
      nonce: _required(json['nonce'], 'nonce'),
      shortCode: _required(json['shortCode'], 'shortCode'),
      issuerDeviceId: _required(json['issuerDeviceId'], 'issuerDeviceId'),
      acceptorDeviceId: _required(json['acceptorDeviceId'], 'acceptorDeviceId'),
      proof: _required(json['proof'], 'proof'),
    );
  }
}

String pairingProof({
  required String nonce,
  required String shortCode,
  required String deviceId,
  required String publicKey,
}) => Hmac(
  sha256,
  utf8.encode(shortCode),
).convert(utf8.encode('$nonce|$deviceId|$publicKey')).toString();

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object');
  return Map<String, Object?>.from(value);
}

String _required(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

int? _optionalPort(Object? value, String field) {
  if (value == null) return null;
  if (value is! int || value <= 0 || value > 65535) {
    throw FormatException('$field must be a valid port');
  }
  return value;
}

DateTime _date(Object? value, String field) {
  final date = DateTime.tryParse(_required(value, field));
  if (date == null) throw FormatException('$field must be ISO-8601');
  return date.toUtc();
}

void _rejectUnknown(Map<String, Object?> json, Set<String> allowed) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('unknown pairing fields: ${unknown.join(', ')}');
  }
}

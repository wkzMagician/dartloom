import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

const messagingCapabilityVersion = 1;

class Packet {
  const Packet({
    required this.packetId,
    required this.recipientId,
    required this.ciphertext,
    required this.createdAt,
    this.senderId = '',
    this.nonce = const <int>[],
    this.mac = const <int>[],
    this.schemaVersion = messagingCapabilityVersion,
  });

  final String packetId;
  final String recipientId;
  final Uint8List ciphertext;
  final DateTime createdAt;
  final String senderId;
  final List<int> nonce;
  final List<int> mac;
  final int schemaVersion;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'packetId': packetId,
        'senderId': senderId,
        'recipientId': recipientId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'ciphertext': base64UrlEncode(ciphertext),
        'nonce': base64UrlEncode(nonce),
        'mac': base64UrlEncode(mac),
      };

  String encode() => jsonEncode(toJson());

  factory Packet.fromJson(Object? value) {
    if (value is! Map) {
      throw const PacketValidationException('packet must be an object');
    }
    final json = Map<String, Object?>.from(value);
    _rejectUnknown(json, const {
      'schemaVersion',
      'packetId',
      'senderId',
      'recipientId',
      'createdAt',
      'ciphertext',
      'nonce',
      'mac',
    });
    final version = json['schemaVersion'];
    if (version != messagingCapabilityVersion) {
      throw PacketValidationException('unsupported packet schema: $version');
    }
    return Packet(
      packetId: _requiredString(json['packetId'], 'packetId'),
      senderId: _requiredString(json['senderId'], 'senderId'),
      recipientId: _requiredString(json['recipientId'], 'recipientId'),
      createdAt: _date(json['createdAt'], 'createdAt'),
      ciphertext: _decodeBytes(json['ciphertext'], 'ciphertext'),
      nonce: _decodeBytes(json['nonce'], 'nonce'),
      mac: _decodeBytes(json['mac'], 'mac'),
      schemaVersion: version as int,
    );
  }

  factory Packet.decode(String value) {
    try {
      return Packet.fromJson(jsonDecode(value));
    } on FormatException catch (error) {
      throw PacketValidationException('invalid packet JSON: $error');
    } on TypeError catch (error) {
      throw PacketValidationException('invalid packet JSON: $error');
    }
  }
}

class PacketValidationException implements Exception {
  const PacketValidationException(this.message);

  final String message;

  @override
  String toString() => 'Invalid messaging packet: $message';
}

class PacketValidator {
  const PacketValidator({required this.recipientId, this.clock = _clock});

  final String recipientId;
  final DateTime Function() clock;

  void validate(Packet packet) {
    if (packet.schemaVersion != messagingCapabilityVersion) {
      throw PacketValidationException(
        'unsupported packet schema: ${packet.schemaVersion}',
      );
    }
    if (packet.packetId.isEmpty || packet.senderId.isEmpty) {
      throw const PacketValidationException(
        'packet identifiers must not be empty',
      );
    }
    if (packet.recipientId != recipientId) {
      throw const PacketValidationException('packet recipient mismatch');
    }
    if (packet.nonce.length != 12 || packet.mac.length != 16) {
      throw const PacketValidationException('invalid AES-GCM packet fields');
    }
    if (packet.ciphertext.isEmpty) {
      throw const PacketValidationException('ciphertext must not be empty');
    }
    if (packet.createdAt.isAfter(
      clock().toUtc().add(const Duration(minutes: 5)),
    )) {
      throw const PacketValidationException(
        'packet timestamp is too far in the future',
      );
    }
  }
}

abstract interface class MessagingConnection {
  Stream<Packet> get incoming;
  Future<void> send(Packet packet);
}

class MemoryMessagingConnection implements MessagingConnection {
  MemoryMessagingConnection();

  final StreamController<Packet> _incoming = StreamController.broadcast();
  final List<Packet> sent = [];

  @override
  Stream<Packet> get incoming => _incoming.stream;

  @override
  Future<void> send(Packet packet) async => sent.add(packet);

  void deliver(Packet packet) => _incoming.add(packet);

  Future<void> close() => _incoming.close();
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw PacketValidationException('$field must be a non-empty string');
  }
  return value;
}

Uint8List _decodeBytes(Object? value, String field) {
  if (value is! String) {
    throw PacketValidationException('$field must be base64url');
  }
  try {
    return Uint8List.fromList(base64Url.decode(value));
  } on FormatException {
    throw PacketValidationException('$field must be base64url');
  }
}

DateTime _date(Object? value, String field) {
  if (value is! String) {
    throw PacketValidationException('$field must be an ISO-8601 string');
  }
  final date = DateTime.tryParse(value);
  if (date == null) {
    throw PacketValidationException('$field must be an ISO-8601 string');
  }
  return date.toUtc();
}

DateTime _clock() => DateTime.now().toUtc();

void _rejectUnknown(Map<String, Object?> json, Set<String> allowed) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw PacketValidationException(
      'unknown packet fields: ${unknown.join(', ')}',
    );
  }
}

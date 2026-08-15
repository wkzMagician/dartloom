import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'packet_contracts.dart';

/// Generic X25519 + HKDF-SHA-256 + AES-256-GCM packet encryption.
///
/// This library only knows packet fields and device keys; it does not know
/// Pigeon Work or application payload types.
class PacketIdentity {
  PacketIdentity._(this.keyPair, this.publicKey);

  final SimpleKeyPair keyPair;
  final SimplePublicKey publicKey;

  static Future<PacketIdentity> generate() async {
    final keyPair = await X25519().newKeyPair();
    return PacketIdentity._(keyPair, await keyPair.extractPublicKey());
  }

  static Future<PacketIdentity> fromPrivateKeyBytes(List<int> bytes) async {
    if (bytes.length != 32) {
      throw ArgumentError.value(bytes.length, 'bytes', 'must contain 32 bytes');
    }
    final keyPair = await X25519().newKeyPairFromSeed(bytes);
    return PacketIdentity._(keyPair, await keyPair.extractPublicKey());
  }

  Future<List<int>> extractPrivateKeyBytes() =>
      keyPair.extractPrivateKeyBytes();
}

class PacketCrypto {
  PacketCrypto({Random? random}) : _random = random ?? Random.secure();

  final Random _random;
  final _keyExchange = X25519();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final _cipher = AesGcm.with256bits();

  Future<Packet> encrypt({
    required PacketIdentity sender,
    required SimplePublicKey recipientPublicKey,
    required String packetId,
    required String senderId,
    required String recipientId,
    required List<int> plaintext,
    DateTime? createdAt,
  }) async {
    final key = await _deriveKey(
      keyPair: sender.keyPair,
      remotePublicKey: recipientPublicKey,
      senderId: senderId,
      recipientId: recipientId,
      packetId: packetId,
    );
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => _random.nextInt(256)),
    );
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(packetId),
    );
    return Packet(
      packetId: packetId,
      senderId: senderId,
      recipientId: recipientId,
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
      ciphertext: Uint8List.fromList(box.cipherText),
      nonce: Uint8List.fromList(box.nonce),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  Future<Uint8List> decrypt({
    required PacketIdentity recipient,
    required SimplePublicKey senderPublicKey,
    required Packet packet,
  }) async {
    final key = await _deriveKey(
      keyPair: recipient.keyPair,
      remotePublicKey: senderPublicKey,
      senderId: packet.senderId,
      recipientId: packet.recipientId,
      packetId: packet.packetId,
    );
    try {
      final plaintext = await _cipher.decrypt(
        SecretBox(packet.ciphertext, nonce: packet.nonce, mac: Mac(packet.mac)),
        secretKey: key,
        aad: utf8.encode(packet.packetId),
      );
      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError {
      throw const PacketValidationException('packet authentication failed');
    }
  }

  Future<SecretKey> _deriveKey({
    required SimpleKeyPair keyPair,
    required SimplePublicKey remotePublicKey,
    required String senderId,
    required String recipientId,
    required String packetId,
  }) async {
    final shared = await _keyExchange.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: remotePublicKey,
    );
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('dartloom/messaging/v1/$senderId/$recipientId'),
      info: utf8.encode(packetId),
    );
  }
}

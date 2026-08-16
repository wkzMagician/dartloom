import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Minimal persistence contract used by the generic pairing identity store.
/// The host supplies this through its secure-settings capability.
abstract interface class PairingIdentityStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// Generic device identity material shared by pairing and packet transport.
class PairingDeviceIdentity {
  PairingDeviceIdentity({
    required this.deviceId,
    required List<int> privateKeyBytes,
    required List<int> publicKeyBytes,
  }) : privateKeyBytes = Uint8List.fromList(privateKeyBytes),
       publicKeyBytes = Uint8List.fromList(publicKeyBytes);

  final String deviceId;
  final Uint8List privateKeyBytes;
  final Uint8List publicKeyBytes;

  String get publicKey => base64UrlEncode(publicKeyBytes);
}

/// Loads or creates a stable device ID and X25519 key pair.
class PairingIdentityRepository {
  PairingIdentityRepository(
    this.store, {
    Random? random,
    this.deviceIdKey = 'device.id',
    this.privateKeyKey = 'device.x25519.private',
    this.publicKeyKey = 'device.x25519.public',
  }) : _random = random ?? Random.secure();

  final PairingIdentityStore store;
  final Random _random;
  final String deviceIdKey;
  final String privateKeyKey;
  final String publicKeyKey;

  Future<PairingDeviceIdentity> loadOrCreate() async {
    final storedId = await store.read(deviceIdKey);
    final storedPrivate = await store.read(privateKeyKey);
    final storedPublic = await store.read(publicKeyKey);
    if (storedId != null && storedId.isNotEmpty && storedPrivate != null) {
      try {
        final privateKey = _decodeKey(storedPrivate, privateKeyKey);
        final identity = await _fromPrivateKey(storedId, privateKey);
        if (storedPublic == null ||
            _sameBytes(
              _decodeKey(storedPublic, publicKeyKey),
              identity.publicKeyBytes,
            )) {
          if (storedPublic == null) {
            await store.write(publicKeyKey, identity.publicKey);
          }
          return identity;
        }
      } on Object {
        // Invalid or partially written identity material is replaced below.
      }
    }

    final keyPair = await X25519().newKeyPair();
    final privateKey = await keyPair.extractPrivateKeyBytes();
    final publicKey = (await keyPair.extractPublicKey()).bytes;
    final deviceId = _newDeviceId();
    await store.write(deviceIdKey, deviceId);
    await store.write(privateKeyKey, base64UrlEncode(privateKey));
    await store.write(publicKeyKey, base64UrlEncode(publicKey));
    return PairingDeviceIdentity(
      deviceId: deviceId,
      privateKeyBytes: privateKey,
      publicKeyBytes: publicKey,
    );
  }

  Future<PairingDeviceIdentity> _fromPrivateKey(
    String deviceId,
    List<int> privateKey,
  ) async {
    if (privateKey.length != 32) {
      throw const FormatException('X25519 private key must contain 32 bytes');
    }
    final keyPair = await X25519().newKeyPairFromSeed(privateKey);
    final publicKey = (await keyPair.extractPublicKey()).bytes;
    return PairingDeviceIdentity(
      deviceId: deviceId,
      privateKeyBytes: privateKey,
      publicKeyBytes: publicKey,
    );
  }

  List<int> _decodeKey(String value, String field) {
    try {
      return base64Url.decode(value);
    } on FormatException {
      throw FormatException('$field must be base64url');
    }
  }

  String _newDeviceId() =>
      'device-${List<int>.generate(16, (_) => _random.nextInt(256)).map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';
}

class MemoryPairingIdentityStore implements PairingIdentityStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

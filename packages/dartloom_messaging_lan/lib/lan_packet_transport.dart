import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartloom_messaging/dartloom_messaging.dart';

abstract interface class LanPacketSender implements PacketConnection {}

const _blobMagic = <int>[0x44, 0x4c, 0x4d, 0x42]; // DLMB
const _blobVersion = 1;

class LanBlobFrame {
  const LanBlobFrame({
    required this.channel,
    required this.objectId,
    required this.bytes,
  });

  final String channel;
  final String objectId;
  final Uint8List bytes;

  static bool matches(List<int> frame) =>
      frame.length >= 9 &&
      frame[4] == _blobMagic[0] &&
      frame[5] == _blobMagic[1] &&
      frame[6] == _blobMagic[2] &&
      frame[7] == _blobMagic[3];

  Uint8List encode() {
    final channelBytes = utf8.encode(channel);
    final objectIdBytes = utf8.encode(objectId);
    if (channelBytes.isEmpty || channelBytes.length > 0xffff) {
      throw ArgumentError.value(channel, 'channel', 'invalid LAN blob channel');
    }
    if (objectIdBytes.isEmpty || objectIdBytes.length > 0xffff) {
      throw ArgumentError.value(objectId, 'objectId', 'invalid LAN blob ID');
    }
    final payloadLength =
        4 +
        1 +
        2 +
        2 +
        4 +
        channelBytes.length +
        objectIdBytes.length +
        bytes.length;
    final frame = Uint8List(4 + payloadLength);
    final data = frame.buffer.asByteData();
    data.setUint32(0, payloadLength, Endian.big);
    frame.setRange(4, 8, _blobMagic);
    data.setUint8(8, _blobVersion);
    data.setUint16(9, channelBytes.length, Endian.big);
    data.setUint16(11, objectIdBytes.length, Endian.big);
    data.setUint32(13, bytes.length, Endian.big);
    var offset = 17;
    frame.setRange(offset, offset + channelBytes.length, channelBytes);
    offset += channelBytes.length;
    frame.setRange(offset, offset + objectIdBytes.length, objectIdBytes);
    offset += objectIdBytes.length;
    frame.setRange(offset, frame.length, bytes);
    return frame;
  }

  static LanBlobFrame decode(List<int> frame) {
    if (!matches(frame)) {
      throw const BlobStoreException('invalid LAN blob frame magic');
    }
    final bytes = Uint8List.fromList(frame);
    final data = bytes.buffer.asByteData();
    if (data.getUint8(8) != _blobVersion) {
      throw const BlobStoreException('unsupported LAN blob frame version');
    }
    final channelLength = data.getUint16(9, Endian.big);
    final objectIdLength = data.getUint16(11, Endian.big);
    final blobLength = data.getUint32(13, Endian.big);
    final expectedLength = 17 + channelLength + objectIdLength + blobLength;
    if (bytes.length != expectedLength) {
      throw const BlobStoreException('LAN blob frame length mismatch');
    }
    var offset = 17;
    final channel = utf8.decode(bytes.sublist(offset, offset + channelLength));
    offset += channelLength;
    final objectId = utf8.decode(
      bytes.sublist(offset, offset + objectIdLength),
    );
    offset += objectIdLength;
    return LanBlobFrame(
      channel: channel,
      objectId: objectId,
      bytes: Uint8List.fromList(bytes.sublist(offset)),
    );
  }
}

/// Receiver-side temporary blob repository. The bytes are already encrypted by
/// the messaging attachment protocol; this store never sees plaintext.
class MemoryLanBlobStore implements BlobStore {
  final Map<String, Uint8List> _values = <String, Uint8List>{};

  @override
  Future<BlobReference> put({
    required String channel,
    required String objectId,
    required Uint8List bytes,
  }) async {
    _validateBlobSegment(channel, 'channel');
    _validateBlobSegment(objectId, 'objectId');
    _values['$channel\u0000$objectId'] = Uint8List.fromList(bytes);
    return BlobReference(
      provider: 'lan',
      uri: Uri(scheme: 'lan-blob', host: channel, path: '/$objectId'),
      byteLength: bytes.length,
    );
  }

  @override
  Future<Uint8List> get(BlobReference reference) async {
    if (reference.provider != 'lan' || reference.uri.scheme != 'lan-blob') {
      throw const BlobStoreException('invalid LAN blob reference');
    }
    final channel = reference.uri.host;
    final segments = reference.uri.pathSegments;
    if (channel.isEmpty || segments.length != 1 || segments.single.isEmpty) {
      throw const BlobStoreException('invalid LAN blob reference path');
    }
    final value = _values['$channel\u0000${segments.single}'];
    if (value == null) throw const BlobStoreException('LAN blob not found');
    if (value.length != reference.byteLength) {
      throw const BlobStoreException('LAN blob length mismatch');
    }
    return Uint8List.fromList(value);
  }
}

/// Pushes encrypted blob bytes directly to a paired TLS endpoint and waits for
/// an acknowledgement before the corresponding control reference is sent.
class LanTlsBlobStore implements BlobStore {
  LanTlsBlobStore({
    required this.host,
    required this.port,
    required this.localStore,
    this.timeout = const Duration(seconds: 5),
    this.certificateSha256,
    Future<SecureSocket> Function(
      String host,
      int port, {
      Duration? timeout,
      bool Function(X509Certificate certificate)? onBadCertificate,
    })?
    connect,
  }) : _connect = connect ?? _connectSecure;

  final String host;
  final int port;
  final MemoryLanBlobStore localStore;
  final Duration timeout;
  final String? certificateSha256;
  final Future<SecureSocket> Function(
    String host,
    int port, {
    Duration? timeout,
    bool Function(X509Certificate certificate)? onBadCertificate,
  })
  _connect;

  @override
  Future<BlobReference> put({
    required String channel,
    required String objectId,
    required Uint8List bytes,
  }) async {
    _validateBlobSegment(channel, 'channel');
    _validateBlobSegment(objectId, 'objectId');
    final expectedFingerprint = certificateSha256?.toLowerCase();
    final socket = await _connect(
      host,
      port,
      timeout: timeout,
      onBadCertificate: expectedFingerprint == null
          ? null
          : (certificate) =>
                sha256.convert(certificate.der).toString().toLowerCase() ==
                expectedFingerprint,
    );
    try {
      if (expectedFingerprint != null &&
          socket.peerCertificate != null &&
          sha256
                  .convert(socket.peerCertificate!.der)
                  .toString()
                  .toLowerCase() !=
              expectedFingerprint) {
        throw const BlobStoreException('LAN TLS certificate pin mismatch');
      }
      socket.add(
        LanBlobFrame(
          channel: channel,
          objectId: objectId,
          bytes: bytes,
        ).encode(),
      );
      await socket.flush().timeout(timeout);
      final acknowledgement = await socket.first.timeout(timeout);
      if (acknowledgement.length != 1 || acknowledgement.single != 1) {
        throw const BlobStoreException('LAN blob was not acknowledged');
      }
      return BlobReference(
        provider: 'lan',
        uri: Uri(scheme: 'lan-blob', host: channel, path: '/$objectId'),
        byteLength: bytes.length,
      );
    } finally {
      await socket.close();
    }
  }

  @override
  Future<Uint8List> get(BlobReference reference) => localStore.get(reference);
}

class LanPacketFrame {
  const LanPacketFrame._();

  static Uint8List encode(Packet packet) {
    final body = utf8.encode(packet.encode());
    if (body.length > 0xffffffff) {
      throw ArgumentError('packet is too large for a LAN frame');
    }
    final bytes = Uint8List(4 + body.length)
      ..buffer.asByteData().setUint32(0, body.length, Endian.big);
    bytes.setRange(4, bytes.length, body);
    return bytes;
  }

  static Packet decode(List<int> frame) {
    if (frame.length < 4) {
      throw const PacketValidationException('short LAN frame');
    }
    final bytes = Uint8List.fromList(frame);
    final length = bytes.buffer.asByteData().getUint32(0, Endian.big);
    if (length != bytes.length - 4) {
      throw const PacketValidationException('LAN frame length mismatch');
    }
    return Packet.decode(utf8.decode(bytes.sublist(4)));
  }
}

/// Sends one length-prefixed encrypted Packet over a pinned TLS connection.
class LanTlsPacketConnection implements LanPacketSender {
  LanTlsPacketConnection({
    required this.host,
    required this.port,
    this.timeout = const Duration(seconds: 3),
    this.certificateSha256,
    Future<SecureSocket> Function(
      String host,
      int port, {
      Duration? timeout,
      bool Function(X509Certificate certificate)? onBadCertificate,
    })?
    connect,
  }) : _connect = connect ?? _connectSecure;

  final String host;
  final int port;
  final Duration timeout;
  final String? certificateSha256;
  final Future<SecureSocket> Function(
    String host,
    int port, {
    Duration? timeout,
    bool Function(X509Certificate certificate)? onBadCertificate,
  })
  _connect;

  @override
  Future<void> send(Packet packet) async {
    final socket = await _connect(
      host,
      port,
      timeout: timeout,
      onBadCertificate: certificateSha256 == null
          ? null
          : (certificate) => _matches(certificate),
    ).timeout(timeout);
    try {
      if (certificateSha256 != null &&
          (socket.peerCertificate == null ||
              !_matches(socket.peerCertificate!))) {
        throw const SocketException('LAN TLS certificate pin mismatch');
      }
      socket.add(LanPacketFrame.encode(packet));
      await socket.flush().timeout(timeout);
    } finally {
      await socket.close();
    }
  }

  bool _matches(X509Certificate certificate) =>
      sha256.convert(certificate.der).toString().toLowerCase() ==
      certificateSha256!.replaceAll(':', '').toLowerCase();
}

/// Minimal TLS listener counterpart for desktop LAN delivery.
class LanTlsPacketServer {
  LanTlsPacketServer({
    required this.securityContext,
    required this.onPacket,
    this.blobStore,
    this.host,
    this.port = 0,
    this.maxBlobBytes = 16 * 1024 * 1024,
  });

  final SecurityContext securityContext;
  final Future<void> Function(Packet packet) onPacket;
  final MemoryLanBlobStore? blobStore;
  final InternetAddress? host;
  final int port;
  final int maxBlobBytes;
  SecureServerSocket? _server;

  int? get boundPort => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    _server = await SecureServerSocket.bind(
      host ?? InternetAddress.anyIPv4,
      port,
      securityContext,
    );
    _server!.listen(_accept, onError: (_) {});
  }

  Future<void> _accept(SecureSocket socket) async {
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in socket) {
        bytes.add(chunk);
        final current = bytes.takeBytes();
        if (current.length < 4) {
          bytes.add(current);
          continue;
        }
        final length = Uint8List.fromList(current).buffer
            .asByteData()
            .getUint32(0, Endian.big);
        if (current.length < length + 4) {
          bytes.add(current);
          continue;
        }
        if (current.length != length + 4) {
          throw const PacketValidationException('LAN frame length mismatch');
        }
        if (LanBlobFrame.matches(current)) {
          final store = blobStore;
          if (store == null) {
            throw const BlobStoreException('LAN blob receiver is disabled');
          }
          final blob = LanBlobFrame.decode(current);
          if (blob.bytes.length > maxBlobBytes) {
            throw const BlobStoreException('LAN blob exceeds server limit');
          }
          await store.put(
            channel: blob.channel,
            objectId: blob.objectId,
            bytes: blob.bytes,
          );
          socket.add(const <int>[1]);
          await socket.flush();
        } else {
          await onPacket(LanPacketFrame.decode(current));
        }
        break;
      }
    } on Object {
      // A malformed or disconnected peer must not stop the listener.
    } finally {
      await socket.close();
    }
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close();
  }
}

void _validateBlobSegment(String value, String field) {
  if (value.isEmpty || value.contains(RegExp(r'[/\\\s\u0000]'))) {
    throw ArgumentError.value(value, field, 'must be an opaque path segment');
  }
}

Future<SecureSocket> _connectSecure(
  String host,
  int port, {
  Duration? timeout,
  bool Function(X509Certificate certificate)? onBadCertificate,
}) => SecureSocket.connect(
  host,
  port,
  timeout: timeout,
  onBadCertificate: onBadCertificate,
);

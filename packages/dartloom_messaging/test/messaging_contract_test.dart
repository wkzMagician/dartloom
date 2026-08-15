import 'dart:typed_data';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dartloom_messaging/dartloom_messaging.dart';
import 'package:test/test.dart';

void main() {
  test('memory connection transports generic packets', () async {
    final connection = MemoryMessagingConnection();
    final packet = Packet(
      packetId: 'packet-1',
      senderId: 'device-1',
      recipientId: 'device-2',
      ciphertext: Uint8List.fromList([1, 2]),
      createdAt: DateTime.utc(2026),
    );
    await connection.send(packet);
    expect(connection.sent.single.packetId, 'packet-1');
    expect(Packet.fromJson(packet.toJson()).recipientId, 'device-2');
    await connection.close();
  });

  test('rejects unknown Packet fields', () {
    final packet = Packet(
      packetId: 'packet-unknown',
      senderId: 'device-1',
      recipientId: 'device-2',
      ciphertext: Uint8List.fromList([1]),
      createdAt: DateTime.utc(2026),
    );
    expect(
      () => Packet.fromJson({...packet.toJson(), 'unexpected': true}),
      throwsA(isA<PacketValidationException>()),
    );
  });

  test(
    'generic packet crypto round trips and validates the envelope',
    () async {
      final sender = await PacketIdentity.generate();
      final recipient = await PacketIdentity.generate();
      final packet = await PacketCrypto().encrypt(
        sender: sender,
        recipientPublicKey: recipient.publicKey,
        packetId: 'packet-crypto',
        senderId: 'sender',
        recipientId: 'recipient',
        plaintext: utf8.encode('hello'),
      );
      PacketValidator(recipientId: 'recipient').validate(packet);
      expect(
        utf8.decode(
          await PacketCrypto().decrypt(
            recipient: recipient,
            senderPublicKey: sender.publicKey,
            packet: Packet.decode(packet.encode()),
          ),
        ),
        'hello',
      );
    },
  );

  test('generic attachment chunks authenticate independently', () async {
    final key = SecretKey(List<int>.filled(32, 9));
    final plaintext = Uint8List.fromList(
      List<int>.generate(513, (index) => index % 251),
    );
    const chunker = AttachmentChunker(chunkSize: 64);
    final manifest = chunker.manifest(
      messageId: 'message',
      attachmentId: 'attachment',
      plaintext: plaintext,
    );
    final chunks = await chunker.encryptAndSplit(
      manifest: manifest,
      plaintext: plaintext,
      key: key,
    );
    final reassembler = AttachmentReassembler(manifest);
    for (final chunk in chunks.reversed) {
      reassembler.add(chunk);
    }
    expect(await reassembler.decryptAndAssemble(key: key), plaintext);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:dartloom_singleton/dartloom_singleton.dart';
import 'package:dartloom_singleton_socket/dartloom_singleton_socket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late int port;

  setUp(() {
    port = 42000 + DateTime.now().microsecondsSinceEpoch % 1000;
  });

  test('first instance binds the deterministic loopback port', () async {
    final service = SocketSingleInstanceService(
      port: port,
      identity: 'test.singleton',
      exitHandler: (int _) async {},
    );
    expect(await service.acquirePrimary(), isTrue);
    expect(service.isPrimary, isTrue);
    expect(service.port, port);
    await service.dispose();
  });

  test('arguments delivered over the socket reach both consumers', () async {
    final service = SocketSingleInstanceService(
      port: port,
      identity: 'test.arguments',
      exitHandler: (int _) async {},
    );
    await service.acquirePrimary();
    final received = <List<String>>[];
    final handled = <List<String>>[];
    service.onSecondInstance.listen(received.add);
    await service.configure(
      SingleInstanceConfiguration(onArgs: (args) async => handled.add(args)),
    );

    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    socket.write(jsonEncode({
      'kind': 'args',
      'identity': 'test.arguments',
      'args': ['a', 'b'],
    }));
    await socket.flush();
    await socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(received, [
      ['a', 'b']
    ]);
    expect(handled, [
      ['a', 'b']
    ]);
    await service.dispose();
  });

  test('a second service cannot become primary on the same port', () async {
    final first = SocketSingleInstanceService(
      port: port,
      identity: 'test.duplicate',
      exitHandler: (int _) async {},
    );
    final second = SocketSingleInstanceService(
      port: port,
      identity: 'test.duplicate',
      exitHandler: (int _) async {},
    );
    expect(await first.acquirePrimary(), isTrue);
    expect(await second.acquirePrimary(), isFalse);
    await second.dispose();
    await first.dispose();
  });
}

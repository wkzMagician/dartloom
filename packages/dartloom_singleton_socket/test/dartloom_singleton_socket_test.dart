import 'dart:convert';
import 'dart:io';

import 'package:dartloom_singleton/dartloom_singleton.dart';
import 'package:dartloom_singleton_socket/dartloom_singleton_socket.dart';
import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeResident implements ResidentService {
  @override
  ResidentConfiguration configuration = const ResidentConfiguration();

  var restoreCount = 0;

  @override
  Future<void> initialize({
    required String iconPath,
    ResidentConfiguration configuration = const ResidentConfiguration(),
  }) async {}

  @override
  Future<void> configure(ResidentConfiguration configuration) async {
    this.configuration = configuration;
  }

  @override
  Future<void> restore() async => restoreCount++;

  @override
  Future<void> quit() async {}

  @override
  Future<void> dispose() async {}
}

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

  test('a duplicate does not skip the primary deterministic port', () async {
    final first = SocketSingleInstanceService(
      identity: 'test.deterministic-duplicate',
      exitHandler: (int _) async {},
    );
    final second = SocketSingleInstanceService(
      port: null,
      identity: 'test.deterministic-duplicate',
      exitHandler: (int _) async {},
    );
    expect(await first.acquirePrimary(), isTrue);
    expect(await second.acquirePrimary(), isFalse);
    expect(second.port, first.port);
    await second.dispose();
    await first.dispose();
  });

  test('resolves the resident service lazily for duplicate launches', () async {
    final resident = _FakeResident();
    final first = SocketSingleInstanceService(
      port: port,
      identity: 'test.lazy-resident',
      residentProvider: () => resident,
      exitHandler: (int _) async {},
    );
    final second = SocketSingleInstanceService(
      port: port,
      identity: 'test.lazy-resident',
      argumentSource: () => const [],
      exitHandler: (int _) async {},
    );
    expect(await first.acquirePrimary(), isTrue);
    await second.ensureSingleInstance();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(resident.restoreCount, 1);
    await second.dispose();
    await first.dispose();
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:dartloom_singleton/dartloom_singleton.dart';
import 'package:dartloom_singleton_filelock/dartloom_singleton_filelock.dart';
import 'package:flutter_test/flutter_test.dart';

String p(String a, String b) => a.endsWith(Platform.pathSeparator)
    ? '$a$b'
    : '$a${Platform.pathSeparator}$b';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('dartloom_singleton_');
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } on FileSystemException {
      // Already gone.
    }
  });

  test('first instance claims the primary role and advertises an endpoint',
      () async {
    final lock = p(temp.path, 's.lock');
    final endpoint = p(temp.path, 's.endpoint');
    final service = FileLockSingleInstanceService(
      lockFilePath: lock,
      endpointFilePath: endpoint,
      exitHandler: (int code) async {},
    );
    expect(await service.acquirePrimary(), isTrue);
    expect(service.isPrimary, isTrue);
    expect(File(lock).existsSync(), isTrue);
    expect(File(endpoint).existsSync(), isTrue);
    await service.dispose();
  });

  test(
      'arguments delivered over the endpoint reach onSecondInstance and onArgs',
      () async {
    final endpoint = p(temp.path, 's.endpoint');
    final lock = p(temp.path, 's.lock');
    final service = FileLockSingleInstanceService(
      lockFilePath: lock,
      endpointFilePath: endpoint,
      exitHandler: (int code) async {},
    );
    await service.acquirePrimary();

    final received = <List<String>>[];
    final handled = <List<String>>[];
    service.onSecondInstance.listen(received.add);
    await service.configure(
      SingleInstanceConfiguration(onArgs: (args) async => handled.add(args)),
    );

    final address = await File(endpoint).readAsString();
    final sep = address.lastIndexOf(':');
    final host = address.substring(0, sep);
    final port = int.parse(address.substring(sep + 1));

    final socket = await Socket.connect(host, port);
    socket.add(utf8.encode(jsonEncode(['a', 'b'])));
    socket.destroy();

    // Give the async listener a moment to process.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received, [
      ['a', 'b'],
    ]);
    expect(handled, [
      ['a', 'b'],
    ]);
    await service.dispose();
  });

  test('a second instance on the same lock file cannot become primary',
      () async {
    final lock = p(temp.path, 's.lock');
    final endpoint = p(temp.path, 's.endpoint');
    final first = FileLockSingleInstanceService(
      lockFilePath: lock,
      endpointFilePath: endpoint,
      exitHandler: (int code) async {},
    );
    expect(await first.acquirePrimary(), isTrue);

    final second = FileLockSingleInstanceService(
      lockFilePath: lock,
      endpointFilePath: endpoint,
      exitHandler: (int code) async {},
    );
    final claimed = await second.acquirePrimary();
    await first.dispose();
    // Depending on the platform's in-process lock semantics a second handle may
    // or may not report a conflict; when it does not, it is a test-environment
    // quirk (two independent open file descriptions) rather than a contract
    // failure. Real enforcement across processes is platform-guaranteed.
    expect(claimed, isFalse);
  });
}

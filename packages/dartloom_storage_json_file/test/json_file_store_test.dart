import 'dart:io';

import 'package:dartloom_storage_json_file/dartloom_storage_json_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists JSON values across store instances', () async {
    final directory = await Directory.systemTemp.createTemp('dartloom_json');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}data.json');
    final first = JsonFileStore(file);
    await first.write('config', {'theme': 'dark'});
    final second = JsonFileStore(file);
    expect(await second.read('config'), {'theme': 'dark'});
  });
}

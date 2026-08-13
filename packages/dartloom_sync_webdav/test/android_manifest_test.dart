import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android library manifest declares Internet access', () async {
    final manifest = await File(
      'android/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(
      manifest,
      contains('android.permission.INTERNET'),
      reason: 'WebDAV must work in Android release builds.',
    );
  });
}

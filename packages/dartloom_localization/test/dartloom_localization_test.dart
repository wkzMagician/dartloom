import 'package:dartloom_localization/dartloom_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ships English and Chinese locale defaults', () {
    expect(
      DartloomLocalizations.supportedLocales,
      containsAll(const [Locale('en'), Locale('zh')]),
    );
    expect(DartloomLocalizations.localizationsDelegates, hasLength(3));
  });
}

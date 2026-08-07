import 'package:dartloom_localization/dartloom_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class TestLocalizationService implements LocalizationService {
  @override
  List<LocalizationsDelegate<dynamic>> get localizationsDelegates => const [];
  @override
  List<Locale> get supportedLocales => const [Locale('en')];
}

void main() {
  test('localization contract is application-message agnostic', () {
    expect(TestLocalizationService().supportedLocales, const [Locale('en')]);
  });
}

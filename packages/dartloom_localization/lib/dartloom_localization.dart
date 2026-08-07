import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Default locale wiring for a Dartloom Flutter application.
///
/// This enables localized Material, Widgets, and Cupertino framework strings.
/// Application-owned messages should use Flutter's ARB-based `gen-l10n` flow.
abstract final class DartloomLocalizations {
  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
}

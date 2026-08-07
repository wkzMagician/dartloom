import 'package:dartloom_localization/dartloom_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

final class GenL10nLocalizationService implements LocalizationService {
  GenL10nLocalizationService({
    required this.supportedLocales,
    required LocalizationsDelegate<dynamic> applicationDelegate,
  }) : localizationsDelegates = [
          applicationDelegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ];

  @override
  final List<Locale> supportedLocales;
  @override
  final List<LocalizationsDelegate<dynamic>> localizationsDelegates;
}

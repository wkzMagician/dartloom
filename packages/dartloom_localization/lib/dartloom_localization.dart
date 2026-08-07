import 'package:flutter/widgets.dart';

abstract interface class LocalizationService {
  List<Locale> get supportedLocales;
  List<LocalizationsDelegate<dynamic>> get localizationsDelegates;
}

# dartloom_localization

Flutter localization defaults for Dartloom applications. It supplies English
and Chinese supported locales plus Flutter's Material, Widgets, and Cupertino
localization delegates.

Add it with `dartloom cap add localization`, then use its lists in `MaterialApp`:

```dart
MaterialApp(
  localizationsDelegates: DartloomLocalizations.localizationsDelegates,
  supportedLocales: DartloomLocalizations.supportedLocales,
)
```

For application messages, use Flutter's ARB-based localization generation.

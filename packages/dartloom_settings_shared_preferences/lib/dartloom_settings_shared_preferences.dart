import 'package:dartloom_settings/dartloom_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore([SharedPreferencesAsync? preferences])
      : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<Object?> read(String key) async => (await _preferences.getAll())[key];

  @override
  Future<void> remove(String key) => _preferences.remove(key);

  @override
  Future<void> write(String key, Object value) async {
    switch (value) {
      case bool value:
        await _preferences.setBool(key, value);
      case int value:
        await _preferences.setInt(key, value);
      case double value:
        await _preferences.setDouble(key, value);
      case String value:
        await _preferences.setString(key, value);
      case List<String> value:
        await _preferences.setStringList(key, value);
      default:
        throw ArgumentError.value(
            value, 'value', 'Unsupported settings value.');
    }
  }
}

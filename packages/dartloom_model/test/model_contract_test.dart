import 'package:dartloom_model/dartloom_model.dart';
import 'package:test/test.dart';

void main() {
  test('model configuration round-trips without credentials', () {
    for (final access in ModelAccess.values) {
      final original = ModelConnection(
        access: access,
        model: 'user-choice',
        endpoint: 'http://localhost:11434',
      );
      final restored = ModelConnection.fromJson(original.toJson());
      expect(restored.access, access);
      expect(restored.model, 'user-choice');
      expect(restored.endpoint, original.endpoint);
      expect(original.toJson().keys, isNot(contains('credential')));
    }
  });
}

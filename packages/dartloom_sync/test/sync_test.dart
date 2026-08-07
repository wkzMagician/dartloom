import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:test/test.dart';

void main() {
  test('noop engine gives a successful deterministic sync', () async {
    final result = await NoopSyncEngine().sync();
    expect(result.isSuccess, isTrue);
  });
}

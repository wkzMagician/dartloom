import 'package:dartloom_logging/dartloom_logging.dart';
import 'package:test/test.dart';

void main() {
  test('logger records errors with the originating exception', () {
    final logger = MemoryLogger();
    logger.error('failed', StateError('bad'));
    expect(logger.entries.single.error, isA<StateError>());
  });
}

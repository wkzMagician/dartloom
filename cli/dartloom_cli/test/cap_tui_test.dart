import 'package:dart_console/dart_console.dart';
import 'package:dartloom/src/commands/cap_tui.dart';
import 'package:test/test.dart';

void main() {
  test('maps cross-platform navigation and activation keys', () {
    expect(
      capTuiIntent(Key.control(ControlCharacter.arrowUp)),
      CapTuiIntent.up,
    );
    expect(
      capTuiIntent(Key.control(ControlCharacter.arrowDown)),
      CapTuiIntent.down,
    );
    expect(capTuiIntent(Key.printable(' ')), CapTuiIntent.activate);
    expect(
      capTuiIntent(Key.control(ControlCharacter.enter)),
      CapTuiIntent.enter,
    );
  });

  test('maps q, escape, and control-c to cancellation', () {
    expect(capTuiIntent(Key.printable('q')), CapTuiIntent.cancel);
    expect(
      capTuiIntent(Key.control(ControlCharacter.escape)),
      CapTuiIntent.cancel,
    );
    expect(
      capTuiIntent(Key.control(ControlCharacter.ctrlC)),
      CapTuiIntent.cancel,
    );
  });

  test('scripted movement wraps in both directions', () {
    var cursor = 0;
    for (final intent in [
      CapTuiIntent.up,
      CapTuiIntent.down,
      CapTuiIntent.down,
      CapTuiIntent.down,
    ]) {
      cursor = moveCapTuiCursor(cursor, 3, intent);
    }
    expect(cursor, 2);
  });
}

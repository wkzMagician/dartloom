import 'package:dartloom_resident/dartloom_resident.dart';
import 'package:flutter_test/flutter_test.dart';

final class TestResidentService implements ResidentService {
  bool initialized = false;
  @override
  ResidentConfiguration configuration = const ResidentConfiguration();

  @override
  Future<void> configure(ResidentConfiguration value) async =>
      configuration = value;

  @override
  Future<void> dispose() async => initialized = false;
  @override
  Future<void> initialize({
    required String iconPath,
    ResidentConfiguration configuration = const ResidentConfiguration(),
  }) async {
    initialized = true;
    this.configuration = configuration;
  }

  @override
  Future<void> quit() async {}
  @override
  Future<void> restore() async {}
}

void main() {
  test('resident lifecycle is platform neutral', () async {
    final service = TestResidentService();
    await service.initialize(iconPath: 'icon.ico');
    expect(service.initialized, isTrue);
    await service.dispose();
    expect(service.initialized, isFalse);
  });

  test('resident configuration stays adapter independent', () async {
    var selected = '';
    final service = TestResidentService();
    await service.initialize(
      iconPath: 'icon.ico',
      configuration: ResidentConfiguration(
        menu: const [
          ResidentMenuItem.action(id: 'open', label: 'Open'),
          ResidentMenuItem.separator(),
          ResidentMenuItem.action(id: 'quit', label: 'Quit completely'),
        ],
        leftClick: ResidentClickAction.showMenu,
        onMenuSelected: (id) => selected = id,
      ),
    );
    await service.configuration.onMenuSelected?.call('open');
    expect(selected, 'open');
    expect(service.configuration.leftClick, ResidentClickAction.showMenu);
  });
}

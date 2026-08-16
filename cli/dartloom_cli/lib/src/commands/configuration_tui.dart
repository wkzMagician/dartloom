import 'dart:io';

import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../packages/package_catalog.dart';

class ConfigurationTui {
  const ConfigurationTui();

  Future<DartloomConfig> select(
      {Set<TargetPlatform>? initialPlatforms,
      List<String>? initialPackages,
      required List<DartloomPackage> available}) async {
    final platforms = initialPlatforms ?? _platforms(available);
    final packages = initialPackages ?? _packages(available);
    stdout.writeln('Dartloom project configuration');
    stdout.writeln('Platforms: ${platforms.map((e) => e.name).join(', ')}');
    stdout.writeln(
        'Available packages: ${available.map((e) => e.name).join(', ')}');
    stdout.writeln(
        'Packages: ${packages.isEmpty ? 'Disabled' : packages.join(', ')}');
    if (stdin.hasTerminal) {
      stdout.write(
          'Press Enter to accept, or type platform names separated by commas: ');
      final platformInput = stdin.readLineSync();
      if (platformInput != null && platformInput.trim().isNotEmpty) {
        final selected = <TargetPlatform>{};
        for (final value in platformInput.split(',')) {
          try {
            selected.add(TargetPlatformName.parse(value.trim()));
          } on StateError {
            throw ConfigException('Unknown Flutter platform: ${value.trim()}.');
          }
        }
        if (selected.isEmpty) {
          throw ConfigException('Select at least one Flutter platform.');
        }
        stdout.write(
            'Type package names separated by commas, or press Enter for none: ');
        final packageInput = stdin.readLineSync();
        final selectedPackages =
            packageInput == null || packageInput.trim().isEmpty
                ? packages
                : packageInput
                    .split(',')
                    .map((value) => value.trim())
                    .where((value) => value.isNotEmpty)
                    .toList();
        return DartloomConfig(platforms: selected, packages: selectedPackages);
      }
    }
    return DartloomConfig(platforms: platforms, packages: packages);
  }

  Set<TargetPlatform> _platforms(List<DartloomPackage> available) =>
      {TargetPlatform.android, TargetPlatform.windows};

  List<String> _packages(List<DartloomPackage> available) => const [];
}

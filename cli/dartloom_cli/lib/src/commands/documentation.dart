import 'dart:io';

import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../packages/package_catalog.dart';

const _begin = '<!-- dartloom:begin -->';
const _end = '<!-- dartloom:end -->';

Future<String> updateAgents(
    File file, DartloomConfig config, PackageCatalog catalog) async {
  final existing = await file.exists()
      ? await file.readAsString()
      : '# Agent Instructions\n\n';
  final packages = await catalog.load(file.parent);
  final selected = <DartloomPackage>[];
  for (final name in config.packages) {
    final matches = packages.where((item) => item.name == name);
    final package = matches.isEmpty ? null : matches.first;
    if (package != null) selected.add(package);
  }
  final body = StringBuffer()
    ..writeln(_begin)
    ..writeln('## Dartloom packages')
    ..writeln()
    ..writeln(
        'Selected platforms: ${config.platforms.map((e) => _title(e.name)).join(', ')}')
    ..writeln();
  if (selected.isEmpty) {
    body.writeln('No optional Dartloom packages are selected.');
  } else {
    for (final package in selected) {
      body
        ..writeln('### ${package.displayName}')
        ..writeln()
        ..writeln('Package: `${package.name}`')
        ..writeln()
        ..writeln(
            '- Platforms: ${package.platforms.map((e) => _title(e.name)).join(', ')}')
        ..writeln('- Purpose: ${package.description}');
      if (package.exports.isNotEmpty) {
        body.writeln(
            '- Main API: ${package.exports.map((e) => e.symbol).join(', ')}');
      }
      body
        ..writeln('- Import:')
        ..writeln()
        ..writeln('  ```dart')
        ..writeln("  import 'package:${package.name}/${package.name}.dart';")
        ..writeln('  ```');
      body.writeln();
    }
  }
  body.writeln(_end);
  final start = existing.indexOf(_begin);
  final end = existing.indexOf(_end);
  if (start >= 0 && end >= start) {
    return '${existing.substring(0, start)}${body.toString().trimRight()}${existing.substring(end + _end.length)}';
  }
  return '${existing.trimRight()}\n\n${body.toString()}';
}

Future<void> updateDependencies(
    Directory project, DartloomConfig config) async {
  final file = File('${project.path}${Platform.pathSeparator}pubspec.yaml');
  if (!await file.exists()) {
    throw ConfigException('pubspec.yaml was not found in ${project.path}.');
  }
  var source = await file.readAsString();
  final lines = source.split('\n');
  final names = config.packages.toSet();
  final dependencyLines = <String>[];
  for (final name in names) {
    dependencyLines.add('  $name: ^1.0.0');
  }
  var dependencies = false;
  var inserted = false;
  final result = <String>[];
  for (final line in lines) {
    if (line == 'dependencies:') {
      dependencies = true;
      result.add(line);
      continue;
    }
    if (dependencies && line.isNotEmpty && !line.startsWith(' ')) {
      result.addAll(dependencyLines);
      inserted = true;
      dependencies = false;
    }
    if (dependencies && RegExp(r'^  dartloom_[a-z0-9_]+:').hasMatch(line)) {
      if (!names.any((name) => line.startsWith('  $name:'))) continue;
    }
    result.add(line);
  }
  if (dependencies && !inserted) result.addAll(dependencyLines);
  source = result.join('\n');
  await file.writeAsString(source.endsWith('\n') ? source : '$source\n');
}

String _title(String value) => value[0].toUpperCase() + value.substring(1);

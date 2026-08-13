import 'dart:io';

import '../build/artifact_packager.dart';
import '../build/build_target.dart';
import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../process/process_runner.dart';
import 'check_command.dart';
import 'command_support.dart';

class BuildCommand {
  BuildCommand(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader(),
        _packager = ArtifactPackager(runner);
  final ProcessRunner runner;
  final ConfigLoader _loader;
  final ArtifactPackager _packager;

  Future<void> run(Directory project, List<String> rawTargets) async {
    final config = await _loader.load(project);
    final targets = rawTargets.isEmpty
        ? config.platforms.map(BuildTarget.new).toList()
        : rawTargets.map(BuildTarget.parse).toList();
    for (final target in targets) {
      if (!config.platforms.contains(target.platform)) {
        throw CommandFailure(
            '${target.platform.name} is disabled in dartloom.yaml.');
      }
      if (!target.isSupportedOnHost) {
        throw CommandFailure(
            '${target.platform.name} cannot be built on this host.');
      }
    }
    await CheckCommand(runner).run(project);
    final version = _version(
        await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
            .readAsString());
    final dist = Directory('${project.path}${Platform.pathSeparator}dist');
    for (final target in targets) {
      await _buildOne(
        project,
        dist,
        config.app.packageName,
        version,
        target.platform,
      );
    }
  }

  Future<void> _buildOne(Directory project, Directory dist, String packageName,
      String version, TargetPlatform platform) async {
    final base = '$packageName-$version-${platform.name}';
    switch (platform) {
      case TargetPlatform.android:
        await withStableAndroidKotlinBuild(project, () async {
          await runRequired(runner, executableFor('flutter'),
              ['build', 'apk', '--release'], project);
          await _packager.copyFile(
              File(
                  '${project.path}${Platform.pathSeparator}build${Platform.pathSeparator}app${Platform.pathSeparator}outputs${Platform.pathSeparator}flutter-apk${Platform.pathSeparator}app-release.apk'),
              dist,
              '$base.apk');
          await runRequired(runner, executableFor('flutter'),
              ['build', 'appbundle', '--release'], project);
          await _packager.copyFile(
              File(
                  '${project.path}${Platform.pathSeparator}build${Platform.pathSeparator}app${Platform.pathSeparator}outputs${Platform.pathSeparator}bundle${Platform.pathSeparator}release${Platform.pathSeparator}app-release.aab'),
              dist,
              '$base.aab');
        });
      case TargetPlatform.windows:
        await runRequired(runner, executableFor('flutter'),
            ['build', 'windows', '--release'], project);
        await _packager.zipDirectory(
            Directory(
                '${project.path}${Platform.pathSeparator}build${Platform.pathSeparator}windows${Platform.pathSeparator}x64${Platform.pathSeparator}runner${Platform.pathSeparator}Release'),
            dist,
            '$base-x64.zip',
            project);
      case TargetPlatform.macos:
        await runRequired(runner, executableFor('flutter'),
            ['build', 'macos', '--release'], project);
        await _packager.zipDirectory(
            Directory(
                '${project.path}${Platform.pathSeparator}build${Platform.pathSeparator}macos${Platform.pathSeparator}Build${Platform.pathSeparator}Products${Platform.pathSeparator}Release'),
            dist,
            '$base.zip',
            project);
      case TargetPlatform.linux:
        await runRequired(runner, executableFor('flutter'),
            ['build', 'linux', '--release'], project);
        await _packager.zipDirectory(
            Directory(
                '${project.path}${Platform.pathSeparator}build${Platform.pathSeparator}linux${Platform.pathSeparator}x64${Platform.pathSeparator}release${Platform.pathSeparator}bundle'),
            dist,
            '$base-x64.zip',
            project);
      case TargetPlatform.web:
        await runRequired(runner, executableFor('flutter'),
            ['build', 'web', '--release'], project);
        await _packager.zipDirectory(
            Directory(
                '${project.path}${Platform.pathSeparator}build${Platform.pathSeparator}web'),
            dist,
            '$base.zip',
            project);
      case TargetPlatform.ios:
        throw CommandFailure('iOS packaging is outside Dartloom V0.1.');
    }
  }

  String _version(String pubspec) =>
      RegExp(r'^version:\s*([^+\s]+)', multiLine: true)
          .firstMatch(pubspec)
          ?.group(1) ??
      '0.1.0';
}

/// Temporarily disables Kotlin incremental compilation for reproducible
/// Android release builds, then restores the application-owned file exactly.
///
/// Kotlin's incremental cache cannot reliably relativize plugin sources when
/// the Pub cache and Flutter project are on different Windows volumes.
Future<T> withStableAndroidKotlinBuild<T>(
  Directory project,
  Future<T> Function() build,
) async {
  if (!Platform.isWindows) return build();
  final properties = File(
    '${project.path}${Platform.pathSeparator}android${Platform.pathSeparator}gradle.properties',
  );
  if (!await properties.exists()) return build();

  final original = await properties.readAsString();
  final setting = RegExp(r'^kotlin\.incremental=.*$', multiLine: true);
  final updated = setting.hasMatch(original)
      ? original.replaceFirst(setting, 'kotlin.incremental=false')
      : '${original.trimRight()}\nkotlin.incremental=false\n';
  if (updated == original) return build();

  await properties.writeAsString(updated);
  try {
    return await build();
  } finally {
    await properties.writeAsString(original);
  }
}

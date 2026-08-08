import 'dart:io';

import '../build/artifact_packager.dart';
import '../config/config_loader.dart';
import '../config/dartloom_config.dart';
import '../packaging/package_target.dart';
import '../process/process_runner.dart';
import 'build_command.dart';
import 'check_command.dart';
import 'command_support.dart';

class PackageCommand {
  PackageCommand(this.runner, {ConfigLoader? loader})
      : _loader = loader ?? const ConfigLoader(),
        _packager = ArtifactPackager(runner);

  final ProcessRunner runner;
  final ConfigLoader _loader;
  final ArtifactPackager _packager;

  Future<void> run(Directory project, String platform, String format) async {
    final target = PackageTarget.parse(platform, format);
    final config = await _loader.load(project);
    _validateHost(target, config);
    switch (target) {
      case PackageTarget.windowsZip:
        await BuildCommand(runner).run(project, ['windows']);
      case PackageTarget.windowsExe:
        await _packageWindowsExe(project, config);
      case PackageTarget.windowsMsix:
        await _packageWindowsMsix(project, config);
      case PackageTarget.linuxDeb:
        await _packageLinuxDeb(project, config);
      case PackageTarget.linuxRpm:
        await _packageLinuxRpm(project, config);
    }
  }

  void _validateHost(PackageTarget target, DartloomConfig config) {
    final expected = target.platform == 'windows'
        ? TargetPlatform.windows
        : TargetPlatform.linux;
    if (!config.platforms.contains(expected)) {
      throw CommandFailure('${target.platform} is disabled in dartloom.yaml.');
    }
    final supported =
        target.platform == 'windows' ? Platform.isWindows : Platform.isLinux;
    if (!supported) {
      throw CommandFailure(
        '${target.platform} packages must be built on ${target.platform}. Use the matching GitHub Actions runner for cross-platform releases.',
      );
    }
  }

  Future<void> _packageWindowsExe(
      Directory project, DartloomConfig config) async {
    await _ensureInnoSetup();
    await _checkAndBuild(project, ['windows']);
    final version = await _version(project);
    final release = Directory(
        '${project.path}${Platform.pathSeparator}build${Platform.pathSeparator}windows${Platform.pathSeparator}x64${Platform.pathSeparator}runner${Platform.pathSeparator}Release');
    final dist = await _dist(project);
    final baseName = '${config.app.name}-$version-windows-x64-setup';
    final script = File(
        '${project.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}dartloom${Platform.pathSeparator}windows.iss');
    await script.parent.create(recursive: true);
    await script.writeAsString('''[Setup]
AppName=${config.app.name}
AppVersion=$version
DefaultDirName={autopf}\\${config.app.name}
DefaultGroupName=${config.app.name}
OutputDir=${dist.path.replaceAll('\\', '/')}
OutputBaseFilename=$baseName
Compression=lzma
SolidCompression=yes

[Files]
Source: "${release.path.replaceAll('\\', '/')}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\\${config.app.name}"; Filename: "{app}\\${config.app.name}.exe"
''');
    await runRequired(runner, 'iscc', [script.path], project);
    stdout
        .writeln('Created ${dist.path}${Platform.pathSeparator}$baseName.exe');
  }

  Future<void> _ensureInnoSetup() async {
    final result = await Process.run('where.exe', ['iscc'], runInShell: false);
    if (result.exitCode != 0) {
      throw CommandFailure(
        'Windows EXE packaging requires Inno Setup. Install Inno Setup, '
        'add the directory containing iscc.exe to PATH, reopen the terminal, '
        'and verify with: where iscc',
      );
    }
  }

  Future<void> _packageWindowsMsix(
      Directory project, DartloomConfig config) async {
    await _ensureMsixDependency(project);
    await _checkAndBuild(project, ['windows']);
    final version = await _version(project);
    final dist = await _dist(project);
    final baseName = '${config.app.name}-$version-windows-x64';
    await runRequired(
      runner,
      executableFor('dart'),
      [
        'run',
        'msix:create',
        '--build-windows',
        'false',
        '--output-path',
        dist.path,
        '--output-name',
        baseName
      ],
      project,
    );
    stdout
        .writeln('Created ${dist.path}${Platform.pathSeparator}$baseName.msix');
  }

  Future<void> _ensureMsixDependency(Directory project) async {
    final pubspec =
        await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
            .readAsString();
    if (RegExp(r'^\s*msix\s*:', multiLine: true).hasMatch(pubspec)) return;
    stdout.writeln('Adding the msix development dependency.');
    await runRequired(
      runner,
      executableFor('flutter'),
      ['pub', 'add', '--dev', 'msix'],
      project,
    );
  }

  Future<void> _packageLinuxDeb(
      Directory project, DartloomConfig config) async {
    await _checkAndBuild(project, ['linux']);
    final version = await _version(project);
    final stage = await _linuxStage(project, config.app.name, version);
    final dist = await _dist(project);
    final control = Directory('${stage.path}${Platform.pathSeparator}DEBIAN');
    await control.create(recursive: true);
    await File('${control.path}${Platform.pathSeparator}control')
        .writeAsString('''Package: ${config.app.name}
Version: $version
Section: utils
Priority: optional
Architecture: amd64
Maintainer: ${config.app.organization}
Depends: libgtk-3-0
Description: ${config.app.description.isEmpty ? config.app.name : config.app.description}
''');
    final output = File(
        '${dist.path}${Platform.pathSeparator}${config.app.name}-$version-linux-amd64.deb');
    await runRequired(runner, 'dpkg-deb',
        ['--build', '--root-owner-group', stage.path, output.path], project);
    stdout.writeln('Created ${output.path}');
  }

  Future<void> _packageLinuxRpm(
      Directory project, DartloomConfig config) async {
    await _checkAndBuild(project, ['linux']);
    final version = await _version(project);
    final stage = await _linuxStage(project, config.app.name, version);
    final root = Directory(
        '${project.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}dartloom${Platform.pathSeparator}rpmbuild');
    final sources = Directory('${root.path}${Platform.pathSeparator}SOURCES');
    final specs = Directory('${root.path}${Platform.pathSeparator}SPECS');
    await sources.create(recursive: true);
    await specs.create(recursive: true);
    final archiveName = '${config.app.name}-$version';
    final source =
        File('${sources.path}${Platform.pathSeparator}$archiveName.tar.gz');
    final stageName = stage.path.split(Platform.pathSeparator).last;
    await runRequired(runner, 'tar',
        ['-czf', source.path, '-C', stage.parent.path, stageName], project);
    final spec =
        File('${specs.path}${Platform.pathSeparator}${config.app.name}.spec');
    await spec.writeAsString('''Name: ${config.app.name}
Version: $version
Release: 1%{?dist}
Summary: ${config.app.description.isEmpty ? config.app.name : config.app.description}
License: Proprietary
Requires: gtk3
Source0: $archiveName.tar.gz

%description
${config.app.description.isEmpty ? config.app.name : config.app.description}

%prep
%setup -q

%install
mkdir -p %{buildroot}
cp -a usr %{buildroot}/

%files
/usr/lib/${config.app.name}
/usr/bin/${config.app.name}
''');
    await runRequired(runner, 'rpmbuild',
        ['--define', '_topdir ${root.path}', '-bb', spec.path], project);
    final rpm = await _firstFile(root, '.rpm');
    final dist = await _dist(project);
    final output = await _packager.copyFile(
        rpm, dist, '${config.app.name}-$version-linux-x86_64.rpm');
    stdout.writeln('Created ${output.path}');
  }

  Future<void> _checkAndBuild(
      Directory project, List<String> buildArguments) async {
    await CheckCommand(runner).run(project);
    await runRequired(runner, executableFor('flutter'),
        ['build', ...buildArguments, '--release'], project);
  }

  Future<Directory> _linuxStage(
      Directory project, String app, String version) async {
    final root = Directory(
        '${project.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}dartloom${Platform.pathSeparator}packages${Platform.pathSeparator}$app-$version');
    if (await root.exists()) await root.delete(recursive: true);
    final bundle = Directory(
        '${project.path}${Platform.pathSeparator}build${Platform.pathSeparator}linux${Platform.pathSeparator}x64${Platform.pathSeparator}release${Platform.pathSeparator}bundle');
    final appDirectory = Directory(
        '${root.path}${Platform.pathSeparator}usr${Platform.pathSeparator}lib${Platform.pathSeparator}$app');
    await _copyDirectory(bundle, appDirectory);
    final bin = Directory(
        '${root.path}${Platform.pathSeparator}usr${Platform.pathSeparator}bin');
    await bin.create(recursive: true);
    final launcher = File('${bin.path}${Platform.pathSeparator}$app');
    await launcher.writeAsString('#!/bin/sh\nexec /usr/lib/$app/$app "\$@"\n');
    await runRequired(runner, 'chmod', ['755', launcher.path], project);
    return root;
  }

  Future<Directory> _dist(Directory project) async {
    final dist = Directory('${project.path}${Platform.pathSeparator}dist');
    await dist.create(recursive: true);
    return dist;
  }

  Future<String> _version(Directory project) async {
    final pubspec =
        await File('${project.path}${Platform.pathSeparator}pubspec.yaml')
            .readAsString();
    return RegExp(r'^version:\s*([^+\s]+)', multiLine: true)
            .firstMatch(pubspec)
            ?.group(1) ??
        '0.1.0';
  }

  Future<File> _firstFile(Directory directory, String extension) async {
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && entity.path.endsWith(extension)) return entity;
    }
    throw CommandFailure('Expected $extension artifact was not produced.');
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity
        in source.list(recursive: true, followLinks: false)) {
      final relative = entity.path.substring(source.path.length + 1);
      final target = '${destination.path}${Platform.pathSeparator}$relative';
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
  }
}

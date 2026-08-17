import '../config/dartloom_config.dart';

String windowsInstaller() =>
    '; Generic Windows installer entry point for Dartloom projects.\n'
    '#define MyAppName "Dartloom App"\n'
    '#define MyAppVersion "0.0.0"\n'
    '#define MyAppExeName "app.exe"\n'
    '[Setup]\n'
    'AppName={#MyAppName}\n'
    'AppVersion={#MyAppVersion}\n'
    'DefaultDirName={autopf}\\{#MyAppName}\n'
    'OutputDir=..\\dist\n'
    'OutputBaseFilename={#MyAppName}-{#MyAppVersion}-windows-x64-setup\n'
    'Compression=lzma2\n'
    'SolidCompression=yes\n'
    'ArchitecturesAllowed=x64compatible\n'
    'ArchitecturesInstallIn64BitMode=x64compatible\n'
    '[Files]\n'
    'Source: "..\\build\\windows\\x64\\runner\\Release\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs\n'
    '[Icons]\n'
    'Name: "{autoprograms}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"\n';

String cloudBuildWorkflow() => r'''name: Dartloom Cloud Build

on:
  workflow_dispatch:
    inputs:
      platform: { required: true, type: string }
      git_ref: { required: true, type: string }
      mode: { required: true, default: release, type: string }

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        platform: [windows, linux, macos, android, ios, web]
    if: ${{ inputs.platform == 'all' || inputs.platform == matrix.platform }}
    runs-on: ${{ matrix.platform == 'windows' && 'windows-latest' || matrix.platform == 'macos' && 'macos-latest' || 'ubuntu-latest' }}
    steps:
      - uses: actions/checkout@v4
        with: { ref: ${{ inputs.git_ref }} }
      - uses: subosito/flutter-action@v2
        with: { channel: stable }
      - run: flutter pub get
      - shell: bash
        run: |
          case "${{ matrix.platform }}" in
            android) flutter build apk --${{ inputs.mode }} ;;
            ios) flutter build ios --${{ inputs.mode }} --no-codesign ;;
            *) flutter build ${{ matrix.platform }} --${{ inputs.mode }} ;;
          esac
      - shell: bash
        run: |
          mkdir -p dartloom-artifact
          printf '{"schema_version":1,"platform":"%s","commit":"%s","files":[]}' "${{ matrix.platform }}" "${{ github.sha }}" > dartloom-artifact/dartloom-build.json
      - uses: actions/upload-artifact@v4
        with: { name: dartloom-${{ matrix.platform }}, path: dartloom-artifact }
''';

String ciWorkflow() => '''name: CI

on:
  push:
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze
      - run: flutter test
''';

String releaseWorkflow(DartloomConfig config) {
  final jobs = <String>[];
  for (final platform in config.platforms) {
    jobs.add(_releaseJob(platform));
  }
  final needs = config.platforms.map((platform) => platform.name).join(', ');
  return '''name: Release

on:
  push:
    branches: [main]
    tags: ['v*']
  workflow_dispatch:

permissions:
  contents: write

jobs:
${jobs.join('\n')}
  release:
    needs: [$needs]
    if: \${{ startsWith(github.ref, 'refs/tags/v') && !failure() && !cancelled() }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
      - uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          files: '**/*'
''';
}

String _releaseJob(TargetPlatform platform) {
  final runner = switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.linux ||
    TargetPlatform.web =>
      'ubuntu-latest',
    TargetPlatform.ios || TargetPlatform.macos => 'macos-latest',
    TargetPlatform.windows => 'windows-latest',
  };
  final commands = switch (platform) {
    TargetPlatform.android => [
        'flutter build apk --release',
        'flutter build appbundle --release',
      ],
    TargetPlatform.ios => ['flutter build ipa --release --no-codesign'],
    TargetPlatform.macos => ['flutter build macos --release'],
    TargetPlatform.windows => [
        'flutter build windows --release',
        'choco install innosetup --no-progress -y',
        'iscc /DMyAppVersion=%VERSION% installer\\windows.iss',
      ],
    TargetPlatform.linux => ['flutter build linux --release'],
    TargetPlatform.web => ['flutter build web --release'],
  };
  final artifactPath = switch (platform) {
    TargetPlatform.android => 'build/app/outputs/**',
    TargetPlatform.ios => 'build/ios/ipa/**',
    TargetPlatform.macos => 'build/macos/Build/Products/Release/**',
    TargetPlatform.windows => 'dist/*.exe',
    TargetPlatform.linux => 'build/linux/**/release/**',
    TargetPlatform.web => 'build/web/**',
  };
  return '''  ${platform.name}:
    runs-on: $runner
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
${commands.map((command) => '      - run: $command').join('\n')}
      - uses: actions/upload-artifact@v4
        with:
          name: ${platform.name}
          path: $artifactPath
''';
}

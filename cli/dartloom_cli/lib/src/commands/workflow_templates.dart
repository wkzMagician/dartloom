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
  matrix:
    runs-on: ubuntu-latest
    outputs:
      platforms: ${{ steps.set-matrix.outputs.platforms }}
    steps:
      - id: set-matrix
        run: |
          if [ "${{ inputs.platform }}" = "all" ]; then
            echo 'platforms=["windows","linux","macos","android","ios","web"]' >> "$GITHUB_OUTPUT"
          else
            echo "platforms=[\"${{ inputs.platform }}\"]" >> "$GITHUB_OUTPUT"
          fi

  build:
    needs: matrix
    strategy:
      fail-fast: false
      matrix:
        platform: ${{ fromJSON(needs.matrix.outputs.platforms) }}
    runs-on: ${{ matrix.platform == 'windows' && 'windows-latest' || (matrix.platform == 'macos' || matrix.platform == 'ios') && 'macos-latest' || 'ubuntu-latest' }}
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ inputs.git_ref }}
      - name: Install Linux build dependencies
        if: ${{ matrix.platform == 'linux' }}
        run: |
          sudo apt-get update
          sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.47.0'
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
        with:
          name: dartloom-${{ matrix.platform }}
          path: dartloom-artifact
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
          flutter-version: '3.47.0'
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
          files: |
            android/**/*.apk
            android/**/*.aab
            ios/**/*.ipa
            windows/**/*.exe
            linux/**/release/bundle/**
            macos/**/Release/*.app/**
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
        'iscc /DMyAppVersion=\${{ github.ref_name }} installer\\windows.iss',
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
  final linuxDependencies = platform == TargetPlatform.linux
      ? '''      - name: Install Linux build dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
'''
      : '';
  return '''  ${platform.name}:
    runs-on: $runner
    steps:
      - uses: actions/checkout@v4
${linuxDependencies}      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.47.0'
      - run: flutter pub get
${commands.map((command) => '      - run: $command').join('\n')}
      - uses: actions/upload-artifact@v4
        with:
          name: ${platform.name}
          path: $artifactPath
''';
}

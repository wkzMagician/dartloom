import '../config/dartloom_config.dart';

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
    TargetPlatform.android || TargetPlatform.linux || TargetPlatform.web =>
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
    TargetPlatform.windows => ['flutter build windows --release'],
    TargetPlatform.linux => ['flutter build linux --release'],
    TargetPlatform.web => ['flutter build web --release'],
  };
  final artifactPath = switch (platform) {
    TargetPlatform.android => 'build/app/outputs/**',
    TargetPlatform.ios => 'build/ios/ipa/**',
    TargetPlatform.macos => 'build/macos/Build/Products/Release/**',
    TargetPlatform.windows => 'build/windows/**/Release/**',
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

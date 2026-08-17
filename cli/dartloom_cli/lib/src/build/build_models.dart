import 'dart:io';

enum BuildMode { debug, profile, release }

enum BuildStatus { queued, running, succeeded, failed, cancelled }

extension BuildModeName on BuildMode {
  static BuildMode parse(String value) => BuildMode.values.firstWhere(
        (mode) => mode.name == value.toLowerCase(),
        orElse: () => throw FormatException('Unknown build mode: $value'),
      );
}

class BuildPlatform {
  static const values = ['windows', 'linux', 'macos', 'android', 'ios', 'web'];
  static String parse(String value) {
    final normalized = value.toLowerCase();
    if (!values.contains(normalized)) {
      throw FormatException('Unknown build platform: $value');
    }
    return normalized;
  }
}

class BuildRequest {
  const BuildRequest({required this.platform, required this.gitRef, this.mode = BuildMode.release, this.release = false});
  final String platform;
  final String gitRef;
  final BuildMode mode;
  final bool release;
}

class Artifact {
  const Artifact({required this.id, required this.name, required this.downloadUrl});
  final int id;
  final String name;
  final String downloadUrl;
}

class BuildResult {
  const BuildResult({required this.runId, required this.platform, required this.artifacts});
  final String runId;
  final String platform;
  final List<Artifact> artifacts;
}

abstract interface class CloudBuildBackend {
  Future<String> trigger(BuildRequest request);
  Future<BuildStatus> status(String runId);
  Future<List<Artifact>> artifacts(String runId);
  Future<void> download(Artifact artifact, Directory target);
  String runUrl(String runId);
}

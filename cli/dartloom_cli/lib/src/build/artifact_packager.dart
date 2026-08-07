import 'dart:io';

import '../commands/command_support.dart';
import '../process/process_runner.dart';

class ArtifactPackager {
  const ArtifactPackager(this.runner);
  final ProcessRunner runner;

  Future<File> copyFile(File source, Directory dist, String name) async {
    await dist.create(recursive: true);
    return source.copy('${dist.path}${Platform.pathSeparator}$name');
  }

  Future<File> zipDirectory(Directory source, Directory dist, String name,
      Directory workingDirectory) async {
    await dist.create(recursive: true);
    final output = File('${dist.path}${Platform.pathSeparator}$name');
    if (Platform.isWindows) {
      await runRequired(
          runner,
          'powershell',
          [
            '-NoProfile',
            '-Command',
            "Compress-Archive -Path '${source.path}\\*' -DestinationPath '${output.path}' -Force"
          ],
          workingDirectory);
    } else {
      await runRequired(runner, 'zip', ['-r', output.path, '.'], source);
    }
    return output;
  }
}

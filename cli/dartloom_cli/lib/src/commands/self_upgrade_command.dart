import 'dart:io';

import '../process/process_runner.dart';

const dartloomGitUrl = 'https://github.com/wkzMagician/dartloom.git';

/// Updates the installed Dartloom executable after this process exits.
class SelfUpgradeCommand {
  const SelfUpgradeCommand(this.runner);

  final ProcessRunner runner;

  Future<void> run(Directory workingDirectory) async {
    if (Platform.isWindows) {
      await runner.startDetached(
        'powershell',
        [
          '-NoProfile',
          '-WindowStyle',
          'Hidden',
          '-Command',
          'Start-Sleep -Milliseconds 750; dart install --overwrite $dartloomGitUrl',
        ],
        workingDirectory: workingDirectory.path,
      );
    } else {
      await runner.startDetached(
        'sh',
        ['-c', 'sleep 1; dart install --overwrite $dartloomGitUrl'],
        workingDirectory: workingDirectory.path,
      );
    }
    stdout.writeln(
        'Dartloom update started. Run dartloom again after it completes.');
  }
}

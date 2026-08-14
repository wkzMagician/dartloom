import 'dart:io';

import '../process/process_runner.dart';

const dartloomGitUrl = 'https://github.com/wkzMagician/dartloom.git';

String dartloomUpgradeInstallCommand() {
  if (Platform.environment['DARTLOOM_UPDATE_SOURCE'] == 'git') {
    return 'dart install --overwrite $dartloomGitUrl --git-path cli/dartloom_cli';
  }
  return 'dart install --overwrite dartloom';
}

/// Updates the installed Dartloom executable after this process exits.
class SelfUpgradeCommand {
  const SelfUpgradeCommand(this.runner);

  final ProcessRunner runner;

  Future<void> run(Directory workingDirectory) async {
    final installCommand = dartloomUpgradeInstallCommand();
    if (Platform.isWindows) {
      await runner.startDetached(
        'powershell',
        [
          '-NoProfile',
          '-WindowStyle',
          'Hidden',
          '-Command',
          'Start-Sleep -Milliseconds 750; $installCommand',
        ],
        workingDirectory: workingDirectory.path,
      );
    } else {
      await runner.startDetached(
        'sh',
        ['-c', 'sleep 1; $installCommand'],
        workingDirectory: workingDirectory.path,
      );
    }
    stdout.writeln(
        'Dartloom self-update started. Run dartloom again after it completes.');
  }
}

import 'dart:io';

import '../process/process_runner.dart';
import 'command_support.dart';

class CheckCommand {
  const CheckCommand(this.runner);
  final ProcessRunner runner;

  Future<void> run(Directory project) async {
    stdout.writeln('Dartloom Check');
    await runRequired(runner, executableFor('dart'),
        ['format', '--output=none', '--set-exit-if-changed', '.'], project);
    stdout.writeln('Format      OK');
    await runRequired(runner, executableFor('flutter'), ['analyze'], project);
    stdout.writeln('Analyze     OK');
    await runRequired(runner, executableFor('flutter'), ['test'], project);
    stdout.writeln('Tests       OK\n\nProject healthy.');
  }
}

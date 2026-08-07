import 'package:dartloom_autostart/dartloom_autostart.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

final class LaunchAtStartupService implements AutostartService {
  LaunchAtStartupService({
    required String appName,
    required String appPath,
    required String packageName,
  }) {
    launchAtStartup.setup(
      appName: appName,
      appPath: appPath,
      packageName: packageName,
    );
  }

  @override
  Future<void> disable() => launchAtStartup.disable();
  @override
  Future<void> enable() => launchAtStartup.enable();
  @override
  Future<bool> isEnabled() => launchAtStartup.isEnabled();
}

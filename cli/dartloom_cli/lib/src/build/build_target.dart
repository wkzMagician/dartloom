import 'dart:io';

import '../config/dartloom_config.dart';

class BuildTarget {
  const BuildTarget(this.platform);
  final TargetPlatform platform;

  static BuildTarget parse(String value) =>
      BuildTarget(TargetPlatformName.parse(value));

  bool get isSupportedOnHost => switch (platform) {
        TargetPlatform.windows => Platform.isWindows,
        TargetPlatform.macos || TargetPlatform.ios => Platform.isMacOS,
        TargetPlatform.linux => Platform.isLinux,
        TargetPlatform.android || TargetPlatform.web => true,
      };
}

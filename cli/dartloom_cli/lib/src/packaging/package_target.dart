enum PackageTarget {
  windowsExe('windows', 'exe'),
  windowsZip('windows', 'zip'),
  windowsMsix('windows', 'msix'),
  linuxDeb('linux', 'deb'),
  linuxRpm('linux', 'rpm');

  const PackageTarget(this.platform, this.format);

  final String platform;
  final String format;

  static PackageTarget parse(String platform, String format) =>
      PackageTarget.values.firstWhere(
        (item) => item.platform == platform && item.format == format,
        orElse: () => throw ArgumentError.value(
          '$platform $format',
          'package target',
          'Supported targets: windows exe|zip|msix, linux deb|rpm',
        ),
      );
}

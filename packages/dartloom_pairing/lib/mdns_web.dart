import 'pairing_contracts.dart';

abstract interface class PairingDiscovery {
  Stream<PairingAdvertisement> discover();
}

class MdnsPairingAdvertiser {
  MdnsPairingAdvertiser({
    required this.deviceId,
    required this.displayName,
    required this.platform,
    required this.fingerprint,
    required this.port,
    required this.serviceType,
  });

  final String deviceId;
  final String displayName;
  final String platform;
  final String fingerprint;
  final int port;
  final String serviceType;

  bool get isRunning => false;
  Future<void> start() => _unsupported();
  Future<void> stop() async {}
}

class MdnsPairingDiscovery implements PairingDiscovery {
  MdnsPairingDiscovery({
    required this.serviceName,
    this.lookupTimeout = const Duration(seconds: 3),
  });

  final String serviceName;
  final Duration lookupTimeout;

  @override
  Stream<PairingAdvertisement> discover() async* {
    throw UnsupportedError('mDNS pairing is unavailable in browser builds.');
  }
}

Future<void> _unsupported() => Future.error(
  UnsupportedError('mDNS pairing is unavailable in browser builds.'),
);

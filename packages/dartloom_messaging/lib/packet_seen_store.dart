/// In-memory Packet ID deduplication with bounded retention.
class SeenPacketStore {
  SeenPacketStore({
    this.retention = const Duration(days: 7),
    this.clock = _systemClock,
  });

  final Duration retention;
  final DateTime Function() clock;
  final Map<String, DateTime> _seen = {};

  bool contains(String packetId) {
    _removeExpired();
    return _seen.containsKey(packetId);
  }

  bool remember(String packetId) {
    _removeExpired();
    if (_seen.containsKey(packetId)) return false;
    _seen[packetId] = clock().toUtc();
    return true;
  }

  int get length {
    _removeExpired();
    return _seen.length;
  }

  void _removeExpired() {
    final cutoff = clock().toUtc().subtract(retention);
    _seen.removeWhere((_, seenAt) => seenAt.isBefore(cutoff));
  }
}

DateTime _systemClock() => DateTime.now().toUtc();

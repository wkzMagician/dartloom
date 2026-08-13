import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:flutter/widgets.dart';

final class FlutterSyncRuntimeSignals
    with WidgetsBindingObserver
    implements SyncRuntimeSignals {
  FlutterSyncRuntimeSignals({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final StreamController<void> _resumed = StreamController.broadcast();
  final StreamController<void> _connectivityRestored =
      StreamController.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _online = true;

  @override
  Stream<void> get resumed => _resumed.stream;
  @override
  Stream<void> get connectivityRestored => _connectivityRestored.stream;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    final current = await _connectivity.checkConnectivity();
    _online = current.any((value) => value != ConnectivityResult.none);
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((values) {
      final online = values.any((value) => value != ConnectivityResult.none);
      if (online && !_online) _connectivityRestored.add(null);
      _online = online;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumed.add(null);
      unawaited(_refreshConnectivity());
    }
  }

  Future<void> _refreshConnectivity() async {
    final values = await _connectivity.checkConnectivity();
    final online = values.any((value) => value != ConnectivityResult.none);
    if (online && !_online) _connectivityRestored.add(null);
    _online = online;
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _connectivitySubscription?.cancel();
    await _resumed.close();
    await _connectivityRestored.close();
  }
}

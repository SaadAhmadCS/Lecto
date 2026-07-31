import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Monitors network connectivity status.
///
/// Used across the app to determine offline/online behavior.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isConnected = true;

  bool get isConnected => _isConnected;
  bool get isOffline => !_isConnected;

  Stream<bool> get onConnectivityChanged => _connectivity
      .onConnectivityChanged
      .map((results) =>
          !results.contains(ConnectivityResult.none));

  Future<void> initialize() async {
    final results = await _connectivity.checkConnectivity();
    _isConnected =
        !results.contains(ConnectivityResult.none);

    _subscription =
        _connectivity.onConnectivityChanged.listen((results) {
      _isConnected =
          !results.contains(ConnectivityResult.none);
    });
  }

  Future<bool> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    _isConnected =
        !results.contains(ConnectivityResult.none);
    return _isConnected;
  }

  void dispose() {
    _subscription?.cancel();
  }
}

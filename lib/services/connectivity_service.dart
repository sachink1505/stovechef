import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  final _connectivity = Connectivity();

  /// Emits true when at least one connectivity type is available.
  Stream<bool> get isOnline => _connectivity.onConnectivityChanged.map(
        (results) => results.any((r) => r != ConnectivityResult.none),
      );

  /// One-time check — returns true if any network interface is up.
  Future<bool> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }
}

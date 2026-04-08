class AppException implements Exception {
  final String message;
  final String? code;

  const AppException(this.message, {this.code});

  @override
  String toString() => code != null ? 'AppException[$code]: $message' : 'AppException: $message';
}

/// A user-facing API error. [message] is always a ready-to-show Arabic string.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.isNetwork = false});

  /// Arabic, user-facing.
  final String message;

  /// HTTP status if the server responded; `null` for network/transport errors.
  final int? statusCode;

  /// True when the request never reached the server (offline, timeout, DNS).
  final bool isNetwork;

  @override
  String toString() => 'ApiException($statusCode, $message)';
}

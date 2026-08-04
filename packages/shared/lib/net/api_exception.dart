/// A user-facing API error. [message] is always a ready-to-show Arabic string.
class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.isNetwork = false,
    this.code,
    this.details = const {},
  });

  /// Arabic, user-facing.
  final String message;

  /// HTTP status if the server responded; `null` for network/transport errors.
  final int? statusCode;

  /// True when the request never reached the server (offline, timeout, DNS).
  final bool isNetwork;

  /// The backend's machine-readable error code, when it sent one (e.g.
  /// `TRIP_PRICE_OUT_OF_RANGE`). [message] is always showable on its own — this
  /// is for the caller that can do BETTER than the generic text, such as
  /// re-rendering numbers the API sent in Western digits as Arabic-Indic.
  final String? code;

  /// The rest of the error body, so a caller matching on [code] can read the
  /// fields that came with it (e.g. `minPricePerSeat`). Empty unless the server
  /// returned a JSON object.
  final Map<String, dynamic> details;

  /// The `int` at [key] in [details], or null if absent / not a number.
  int? detailInt(String key) {
    final value = details[key];
    return value is num ? value.toInt() : null;
  }

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';
}

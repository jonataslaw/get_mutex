/// Exception thrown when a timeout is exceeded.
class TimeoutException implements Exception {
  /// Description of the cause of the timeout.
  final String? message;

  /// The duration that was exceeded.
  final Duration? duration;

  TimeoutException(this.message, [this.duration]);

  @override
  String toString() {
    String result = "TimeoutException";
    if (duration != null) result = "TimeoutException after $duration";
    if (message != null) result = "$result: $message";
    return result;
  }
}

/// Exception thrown when a lock acquisition is cancelled.
class CancellationException implements Exception {
  final String message;
  CancellationException(this.message);

  @override
  String toString() => 'CancellationException: $message';
}

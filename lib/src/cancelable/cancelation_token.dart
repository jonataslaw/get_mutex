import 'dart:async';

/// A token that can be used to signal cancellation.
class CancellationToken {
  bool _isCancelled = false;
  final Completer<void> _completer = Completer<void>();

  /// Whether the token has been cancelled.
  bool get isCancelled => _isCancelled;

  /// A future that completes when the token is cancelled.
  Future<void> get whenCancelled => _completer.future;

  /// Cancels the token.
  void cancel() {
    if (!_isCancelled) {
      _isCancelled = true;
      _completer.complete();
    }
  }
}

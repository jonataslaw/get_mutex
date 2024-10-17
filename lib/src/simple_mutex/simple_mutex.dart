import 'dart:async';

import '../cancelable/cancelation_token.dart';
import '../exceptions/index.dart';
import '../utils/utils.dart';
import 'simple_mutex_interface.dart';

/// A simple non-reentrant mutex implementation.
class SimpleMutex extends SimpleMutexInterface {
  bool _isLocked = false;
  Completer<void>? _currentOwner;

  @override
  Future<T> protect<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) async {
    if (_isLocked) {
      if (_currentOwner != null &&
          identical(_currentOwner, Zone.current[#owner])) {
        throw ReentrantMutexError();
      }
      await configureQueue(
          cancellationToken: cancellationToken, timeout: timeout);
    } else {
      _isLocked = true;
      _currentOwner = Completer<void>();
    }

    try {
      return await runZoned(
        () => executeCancellableAction(action, cancellationToken, timeout),
        zoneValues: {#owner: _currentOwner},
      );
    } finally {
      if (isQueueNotEmpty()) {
        final nextCompleter = removeFirstItemOfQueue();
        _currentOwner = nextCompleter;
        nextCompleter.complete();
      } else {
        _isLocked = false;
        _currentOwner = null;
      }
    }
  }

  bool isHeldByCurrent() =>
      _isLocked && identical(_currentOwner, Zone.current[#owner]);

  @override
  bool isLocked() => _isLocked;
}

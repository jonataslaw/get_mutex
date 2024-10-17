import 'dart:async';

import '../cancelable/cancelation_token.dart';
import '../utils/utils.dart';
import 'simple_mutex_interface.dart';

/// A simple reentrant mutex implementation.
///
/// This mutex allows the same thread (Zone) to acquire the lock multiple times.
class SimpleReentrantMutex extends SimpleMutexInterface {
  int _lockCount = 0;
  Zone? _currentZone;

  @override
  Future<T> protect<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) async {
    final currentZone = Zone.current;

    if (isHeldByCurrent()) {
      // Reentrant acquisition
      _lockCount++;
      try {
        return await executeCancellableAction(
            action, cancellationToken, timeout);
      } finally {
        _lockCount--;
        if (_lockCount == 0) {
          _currentZone = null;
          _processNextInQueue(currentZone);
        }
      }
    } else {
      if (_currentZone != null) {
        await configureQueue(
            cancellationToken: cancellationToken, timeout: timeout);
      } else {
        _currentZone = currentZone;
        _lockCount = 1;
      }
      try {
        return await executeCancellableAction(
            action, cancellationToken, timeout);
      } finally {
        _lockCount--;
        if (_lockCount == 0) {
          _currentZone = null;
          _processNextInQueue(currentZone);
        }
      }
    }
  }

  void _processNextInQueue(Zone currentZone) {
    if (isQueueNotEmpty()) {
      final nextCompleter = removeFirstItemOfQueue();
      _currentZone = currentZone;
      _lockCount = 1;
      nextCompleter.complete();
    }
  }

  /// Checks if the current Zone holds the lock.
  bool isHeldByCurrent() => _currentZone == Zone.current;

  @override
  bool isLocked() => _lockCount > 0;
}

import '../cancelable/cancelation_token.dart';

/// Interface for mutex implementations supporting read-write locks.
abstract interface class MutexInterface {
  /// Executes [action] within a read lock.
  Future<T> protectRead<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  });

  /// Executes [action] within a write lock.
  Future<T> protectWrite<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  });

  /// Attempts to acquire the lock without waiting.
  Future<T?> tryLock<T>(Future<T> Function() action);

  /// Checks if the mutex is currently locked.
  bool isLocked();

  /// Checks if the mutex is currently write-locked.
  bool isWriteLocked();

  /// Checks if the mutex is currently read-locked.
  bool isReadLocked();
}

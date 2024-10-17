import 'dart:async';

import '../cancelable/cancelation_token.dart';
import '../utils/utils.dart';
import 'lock_policy.dart';
import 'mutex_interface.dart';
import 'read_write_mutex.dart';

/// A reentrant mutex implementation supporting read-write locks.
class Mutex implements MutexInterface {
  final RawReadWriteMutex _mutex;
  static final _taskIdKey = Object();
  int _nextTaskId = 0;
  Object? _ownerTaskId;
  int _recursiveCount = 0;
  bool _isWriteLock = false;
  final LockPolicy lockPolicy;

  Mutex({this.lockPolicy = LockPolicy.fair})
      : _mutex = RawReadWriteMutex(lockPolicy: lockPolicy);

  Object _newTaskId() => _nextTaskId++;

  /// Protects a critical section with a write lock.
  Future<T> protect<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) {
    return protectWrite(action,
        cancellationToken: cancellationToken, timeout: timeout);
  }

  @override
  Future<T> protectRead<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) {
    return _protectInternal(action,
        isWrite: false, cancellationToken: cancellationToken, timeout: timeout);
  }

  @override
  Future<T> protectWrite<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) {
    return _protectInternal(action,
        isWrite: true, cancellationToken: cancellationToken, timeout: timeout);
  }

  Future<T> _protectInternal<T>(
    Future<T> Function() action, {
    required bool isWrite,
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) {
    var currentTaskId = Zone.current[_taskIdKey];
    if (currentTaskId == null) {
      currentTaskId = _newTaskId();
      return Zone.current.fork(zoneValues: {_taskIdKey: currentTaskId}).run(() {
        return _protectInternalWithTaskId(action, currentTaskId, isWrite,
            cancellationToken: cancellationToken, timeout: timeout);
      });
    } else {
      return _protectInternalWithTaskId(action, currentTaskId, isWrite,
          cancellationToken: cancellationToken, timeout: timeout);
    }
  }

  Future<T> _protectInternalWithTaskId<T>(
    Future<T> Function() action,
    Object currentTaskId,
    bool isWrite, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) async {
    if (_ownerTaskId == currentTaskId) {
      // Reentrant call
      if (_isWriteLock || !isWrite) {
        _recursiveCount++;
        return _manageCancelableAction(action, cancellationToken, timeout);
      } else {
        // Trying to acquire a write lock while holding a read lock
        throw StateError('Cannot upgrade from read lock to write lock');
      }
    } else {
      return await (isWrite ? _mutex.protectWrite : _mutex.protectRead)(
        () async {
          _ownerTaskId = currentTaskId;
          _recursiveCount = 1;
          _isWriteLock = isWrite;

          return await _manageCancelableAction<T>(
              action, cancellationToken, timeout);
        },
        cancellationToken: cancellationToken,
        timeout: timeout,
      );
    }
  }

  Future<T> _manageCancelableAction<T>(
    Future<T> Function() action,
    CancellationToken? cancellationToken,
    Duration? timeout,
  ) async {
    try {
      return await executeCancellableAction(action, cancellationToken, timeout);
    } finally {
      _recursiveCount--;
      if (_recursiveCount == 0) {
        _ownerTaskId = null;
        _isWriteLock = false;
      }
    }
  }

  @override
  Future<T?> tryLock<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) {
    var currentTaskId = Zone.current[_taskIdKey];
    if (currentTaskId == null) {
      currentTaskId = _newTaskId();
      return Zone.current.fork(zoneValues: {_taskIdKey: currentTaskId}).run(() {
        return _tryLockInternal(action, currentTaskId,
            cancellationToken: cancellationToken, timeout: timeout);
      });
    } else {
      return _tryLockInternal(action, currentTaskId,
          cancellationToken: cancellationToken, timeout: timeout);
    }
  }

  Future<T?> _tryLockInternal<T>(
    Future<T> Function() action,
    Object currentTaskId, {
    required CancellationToken? cancellationToken,
    required Duration? timeout,
  }) async {
    if (_ownerTaskId == currentTaskId) {
      // Reentrant call
      _recursiveCount++;
      return await _manageCancelableAction(action, cancellationToken, timeout);
    } else {
      // Try to acquire the mutex
      final result = await _mutex.tryLock(() async {
        _ownerTaskId = currentTaskId;
        _recursiveCount = 1;
        _isWriteLock = true;
        return await _manageCancelableAction(
            action, cancellationToken, timeout);
      });
      return result;
    }
  }

  @override
  bool isLocked() => _mutex.isLocked();

  @override
  bool isWriteLocked() => _isWriteLock;

  @override
  bool isReadLocked() => _mutex.isReadLocked();
}

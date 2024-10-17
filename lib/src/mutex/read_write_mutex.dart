import 'dart:async';

import '../cancelable/cancelation_token.dart';
import '../utils/utils.dart';
import 'lock_policy.dart';

/// A RawReadWriteMutex implementation that allows multiple readers or a single writer.
///
/// This mutex supports different lock policies to manage the order of lock acquisition:
/// - `LockPolicy.fair`: Grants locks in the order they were requested.
/// - `LockPolicy.readersFirst`: Prefers granting read locks over write locks.
/// - `LockPolicy.writersFirst`: Prefers granting write locks over read locks.
class RawReadWriteMutex {
  final LockPolicy lockPolicy;
  int _activeReaders = 0;
  Completer<void>? _activeWriter;

  static final _queue = <_LockRequest>[];

  RawReadWriteMutex({this.lockPolicy = LockPolicy.fair});

  /// Attempts to acquire a write lock without waiting.
  bool tryAcquireWrite() {
    if (_activeWriter != null || _activeReaders > 0) {
      return false;
    }
    _activeWriter = Completer<void>();
    return true;
  }

  /// Acquires a read lock.
  Future<void> acquireRead({
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) {
    final completer = Completer<void>();
    final request = _LockRequest(isRead: true, completer: completer);

    _queue.add(request);
    _processQueue();

    handleCancellationAndTimeout<void>(
      completer,
      cancellationToken: cancellationToken,
      timeout: timeout,
      onCancelledOrTimedOut: () {
        _queue.remove(request);
        _processQueue();
      },
      operationName: 'Lock acquisition',
    );

    return completer.future;
  }

  /// Releases a read lock.
  void releaseRead() {
    _activeReaders--;
    _processQueue();
  }

  /// Acquires a write lock.
  Future<void> acquireWrite({
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) {
    final completer = Completer<void>();
    final request = _LockRequest(isRead: false, completer: completer);

    _queue.add(request);
    _processQueue();

    handleCancellationAndTimeout<void>(
      completer,
      cancellationToken: cancellationToken,
      timeout: timeout,
      onCancelledOrTimedOut: () {
        _queue.remove(request);
        _processQueue();
      },
      operationName: 'Lock acquisition',
    );

    return completer.future;
  }

  /// Releases a write lock.
  void releaseWrite() {
    _activeWriter = null;
    _processQueue();
  }

  /// Processes the lock request queue based on the lock policy.
  void _processQueue() {
    if (_activeWriter != null) return;

    bool writerWaiting = _queue.any((request) => !request.isRead);

    switch (lockPolicy) {
      case LockPolicy.readersFirst:
        _processReadersFirst(writerWaiting);
        break;
      case LockPolicy.writersFirst:
        _processWritersFirst(writerWaiting);
        break;
      case LockPolicy.fair:
      default:
        _processFair();
    }
  }

  /// Processes the queue in a fair manner.
  void _processFair() {
    if (_activeWriter != null || _queue.isEmpty) return;

    final request = _queue.first;
    if (request.isGranted) return;

    if (request.isRead) {
      _grantReadLocks();
    } else if (_activeReaders == 0) {
      _grantWriteLock(request);
    }
  }

  /// Processes the queue preferring readers.
  void _processReadersFirst(bool writerWaiting) {
    if (_activeWriter != null || _queue.isEmpty) return;

    if (_activeReaders > 0 || !writerWaiting) {
      _grantReadLocks();
    } else if (_activeReaders == 0 && !_queue.first.isRead) {
      _grantWriteLock(_queue.first);
    }
  }

  /// Processes the queue preferring writers.
  void _processWritersFirst(bool writerWaiting) {
    if (_activeWriter != null || _queue.isEmpty) return;

    final request = _queue.first;
    if (request.isGranted) return;

    if (_activeReaders == 0 && !request.isRead) {
      _grantWriteLock(request);
    } else if (!writerWaiting) {
      _grantReadLocks();
    }
  }

  /// Grants read locks to all consecutive read requests at the front of the queue.
  void _grantReadLocks() {
    while (_queue.isNotEmpty && _queue.first.isRead) {
      final readerRequest = _queue.removeAt(0);
      _activeReaders++;
      readerRequest.isGranted = true;
      readerRequest.completer.complete();
    }
  }

  /// Grants a write lock to the given request.
  void _grantWriteLock(_LockRequest request) {
    _queue.removeAt(0);
    _activeWriter = Completer<void>();
    request.isGranted = true;
    request.completer.complete();
  }

  /// Executes [action] within a read lock.
  Future<T> protectRead<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) async {
    await acquireRead(cancellationToken: cancellationToken, timeout: timeout);
    try {
      return await executeCancellableAction(action, cancellationToken, timeout);
    } finally {
      releaseRead();
    }
  }

  /// Executes [action] within a write lock.
  Future<T> protectWrite<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) async {
    await acquireWrite(cancellationToken: cancellationToken, timeout: timeout);
    try {
      return await executeCancellableAction(action, cancellationToken, timeout);
    } finally {
      releaseWrite();
    }
  }

  Future<T?> tryLock<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) async {
    if (!tryAcquireWrite()) {
      return null;
    }
    try {
      return await executeCancellableAction(action, cancellationToken, timeout);
    } finally {
      releaseWrite();
    }
  }

  /// Checks if the mutex is currently write-locked.
  bool isWriteLocked() => _activeWriter != null;

  /// Checks if the mutex is currently read-locked.
  bool isReadLocked() => _activeReaders > 0;

  /// Checks if the mutex is currently locked (either read or write).
  bool isLocked() => isWriteLocked() || isReadLocked();
}

/// Represents a lock request in the queue.
class _LockRequest {
  final bool isRead;
  final Completer<void> completer;
  bool isGranted = false;

  _LockRequest({
    required this.isRead,
    required this.completer,
  });
}

import 'dart:async';
import 'dart:collection';

import '../cancelable/cancelation_token.dart';
import '../utils/utils.dart';

/// Base interface for simple mutex implementations.
abstract class SimpleMutexInterface {
  /// Executes the provided [action] within a protected context.
  ///
  /// This method ensures mutual exclusion for the duration of the [action].
  ///
  /// Parameters:
  /// - [action]: The asynchronous function to be executed under mutex protection.
  /// - [cancellationToken]: Optional token to cancel the operation.
  /// - [timeout]: Optional duration after which the operation times out.
  ///
  /// Returns a Future that completes with the result of [action].
  Future<T> protect<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  });

  /// Checks if the mutex is currently locked.
  bool isLocked();

  // Queue to manage waiting threads
  static final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  /// Configures the queue for waiting threads.
  ///
  /// This method is called when a thread needs to wait for the mutex.
  /// It adds a new completer to the queue and sets up cancellation and timeout handlers.
  Future<void> configureQueue({
    required CancellationToken? cancellationToken,
    required Duration? timeout,
  }) async {
    final completer = Completer<void>();
    _waitQueue.add(completer);

    handleCancellationAndTimeout<void>(
      completer,
      cancellationToken: cancellationToken,
      timeout: timeout,
      onCancelledOrTimedOut: () {
        _waitQueue.remove(completer);
      },
      operationName: 'Lock acquisition',
    );

    await completer.future;
  }

  /// Checks if the wait queue is not empty.
  bool isQueueNotEmpty() => _waitQueue.isNotEmpty;

  /// Removes and returns the first item from the wait queue.
  Completer<void> removeFirstItemOfQueue() => _waitQueue.removeFirst();
}

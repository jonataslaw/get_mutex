import 'dart:async';

import '../exceptions/index.dart';
import '../cancelable/cancelation_token.dart';

/// Executes an asynchronous action that can be cancelled or timed out.
///
/// This method wraps the provided [action] in a completer and sets up
/// cancellation and timeout handlers.
Future<T> executeCancellableAction<T>(
  Future<T> Function() action,
  CancellationToken? cancellationToken,
  Duration? timeout,
) {
  final completer = Completer<T>();

  action().then((result) {
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }).catchError((error) {
    if (!completer.isCompleted) {
      completer.completeError(error);
    }
  });

  handleCancellationAndTimeout<T>(
    completer,
    cancellationToken: cancellationToken,
    timeout: timeout,
    operationName: 'Operation',
  );

  return completer.future;
}

/// Handles cancellation and timeout for a given operation.
///
/// This method sets up listeners for cancellation and timeout events,
/// completing the provided [completer] with an error if either occurs.
void handleCancellationAndTimeout<T>(
  Completer<T> completer, {
  CancellationToken? cancellationToken,
  Duration? timeout,
  void Function()? onCancelledOrTimedOut,
  required String operationName,
}) {
  if (cancellationToken != null) {
    cancellationToken.whenCancelled.then((_) {
      if (!completer.isCompleted) {
        onCancelledOrTimedOut?.call();
        completer.completeError(
          CancellationException('$operationName cancelled'),
        );
      }
    });
  }

  if (timeout != null) {
    Future.delayed(timeout).then((_) {
      if (!completer.isCompleted) {
        onCancelledOrTimedOut?.call();
        completer.completeError(
          TimeoutException('$operationName timed out after $timeout'),
        );
      }
    });
  }
}

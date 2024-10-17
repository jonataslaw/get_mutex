class ReentrantMutexError implements Exception {
  ReentrantMutexError();

  @override
  String toString() {
    final initialMessage =
        'ReentrantMutexError: Reentrant lock attempt detected';

    return '$initialMessage\nTo fix it, remove the reentrant `mutex.protec(() {})` call, or replace your current SimpleMutex class with a `SimpleReentrantMutex`';
  }
}

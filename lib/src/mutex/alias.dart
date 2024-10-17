import '../simple_mutex/simple_mutex.dart';
import '../simple_mutex/simple_reentrant_mutex.dart';
import 'lock_policy.dart';
import 'mutex.dart';
import 'read_write_mutex.dart';

class GetMutex {
  static Mutex mutex({LockPolicy lockPolicy = LockPolicy.fair}) {
    return Mutex(lockPolicy: lockPolicy);
  }

  static SimpleMutex simpleMutex() {
    return SimpleMutex();
  }

  static SimpleReentrantMutex simpleReentrantMutex() {
    return SimpleReentrantMutex();
  }

  static RawReadWriteMutex rawReadWriteMutex(
      {LockPolicy lockPolicy = LockPolicy.fair}) {
    return RawReadWriteMutex(lockPolicy: lockPolicy);
  }
}

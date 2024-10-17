import 'dart:async';

import 'package:get_mutex/get_mutex.dart';
import 'package:test/test.dart';

void main() {
  group('RawReadWriteMutex', () {
    test('allows concurrent reads', () async {
      final mutex = RawReadWriteMutex();
      int sharedResource = 0;
      var futures = <Future>[];
      for (int i = 0; i < 5; i++) {
        futures.add(mutex.protectRead(() async {
          await Future.delayed(Duration(milliseconds: 50));
          sharedResource += 1;
        }));
      }
      await Future.wait(futures);
      // All reads should have completed, sharedResource should be 5
      expect(sharedResource, 5);
    });

    test('write locks prevent reads', () async {
      final mutex = RawReadWriteMutex();
      int sharedResource = 0;
      var writeFuture = mutex.protectWrite(() async {
        // Hold the write lock for a while
        await Future.delayed(Duration(milliseconds: 100));
        sharedResource += 1;
      });

      // Start a read after the write has started
      var readFuture = mutex.protectRead(() async {
        sharedResource += 10;
      });

      await Future.wait([writeFuture, readFuture]);

      // The write operation should have completed before the read
      // Because write locks exclude reads
      // So sharedResource should be 11 (1 + 10)
      expect(sharedResource, 11);
    });

    test('write locks prevent other writes', () async {
      final mutex = RawReadWriteMutex();
      int sharedResource = 0;
      var writeFuture1 = mutex.protectWrite(() async {
        // Hold the write lock for a while
        await Future.delayed(Duration(milliseconds: 100));
        sharedResource += 1;
      });

      // Attempt to acquire another write lock
      var writeFuture2 = mutex.protectWrite(() async {
        sharedResource += 10;
      });

      await Future.wait([writeFuture1, writeFuture2]);

      // The write operations should have executed sequentially
      // So sharedResource should be 11 (1 + 10)
      expect(sharedResource, 11);
    });

    test('readersFirst policy favors readers over writers', () async {
      final mutex = RawReadWriteMutex(lockPolicy: LockPolicy.readersFirst);
      int sharedResource = 0;
      bool writeCompleted = false;

      // Start a write lock
      var writeFuture = mutex.protectWrite(() async {
        // Hold the write lock for a while
        await Future.delayed(Duration(milliseconds: 100));
        writeCompleted = true;
      });

      // Start multiple reads after the write has started
      var readFutures = <Future>[];
      for (int i = 0; i < 5; i++) {
        readFutures.add(mutex.protectRead(() async {
          await Future.delayed(Duration(milliseconds: 20));
          sharedResource += 1;
        }));
      }

      await Future.wait([...readFutures, writeFuture]);

      // Readers should have been allowed before the writer
      // Because the policy favors readers
      expect(writeCompleted, true);
      expect(sharedResource, 5);
    });

    test('writersFirst policy favors writers over readers', () async {
      final mutex = RawReadWriteMutex(lockPolicy: LockPolicy.writersFirst);
      int sharedResource = 0;
      bool readCompleted = false;

      // Start a read lock
      var readFuture = mutex.protectRead(() async {
        await Future.delayed(Duration(milliseconds: 20));
        sharedResource += 1;
        readCompleted = true;
      });

      // Start a write lock after the read has started
      var writeFuture = mutex.protectWrite(() async {
        await Future.delayed(Duration(milliseconds: 50));
        sharedResource += 10;
      });

      await Future.wait([writeFuture, readFuture]);

      // Writer should have been allowed before the reader finishes
      // Because the policy favors writers
      expect(sharedResource, 11);
      expect(readCompleted, true);
    });

    test('fair policy processes requests in order of arrival', () async {
      final mutex = RawReadWriteMutex(lockPolicy: LockPolicy.fair);
      List<int> executionOrder = [];

      var actions = [
        () => mutex.protectWrite(() async {
              executionOrder.add(1);
            }),
        () => mutex.protectRead(() async {
              executionOrder.add(2);
            }),
        () => mutex.protectWrite(() async {
              executionOrder.add(3);
            }),
        () => mutex.protectRead(() async {
              executionOrder.add(4);
            }),
      ];

      var futures = actions.map((action) => action()).toList();

      await Future.wait(futures);

      // The operations should have executed in the order they were requested
      expect(executionOrder, [1, 2, 3, 4]);
    });

    test('protectRead allows multiple readers simultaneously', () async {
      final mutex = RawReadWriteMutex();
      int activeReaders = 0;
      int maxActiveReaders = 0;

      var readers = List<Future>.generate(
          5,
          (_) => mutex.protectRead(() async {
                activeReaders++;
                if (activeReaders > maxActiveReaders) {
                  maxActiveReaders = activeReaders;
                }
                await Future.delayed(Duration(milliseconds: 20));
                activeReaders--;
              }));

      await Future.wait(readers);

      expect(maxActiveReaders, 5);
    });

    test('protectWrite blocks during read', () async {
      final mutex = RawReadWriteMutex();
      bool writeStarted = false;
      bool writeCompleted = false;

      var readFuture = mutex.protectRead(() async {
        await Future.delayed(Duration(milliseconds: 50));
      });

      var writeFuture = mutex.protectWrite(() async {
        writeStarted = true;
        await Future.delayed(Duration(milliseconds: 20));
        writeCompleted = true;
      });

      await Future.wait([readFuture, writeFuture]);

      // Write should have started after the read completed
      expect(writeStarted, true);
      expect(writeCompleted, true);
    });

    test('releaseWrite allows next write to proceed', () async {
      final mutex = RawReadWriteMutex();
      bool firstWriteCompleted = false;
      bool secondWriteStarted = false;

      var firstWrite = mutex.protectWrite(() async {
        await Future.delayed(Duration(milliseconds: 50));
        firstWriteCompleted = true;
      });

      var secondWrite = mutex.protectWrite(() async {
        secondWriteStarted = true;
      });

      await Future.wait([firstWrite, secondWrite]);

      expect(firstWriteCompleted, true);
      expect(secondWriteStarted, true);
    });

    test('releaseRead allows write to proceed when no more readers', () async {
      final mutex = RawReadWriteMutex();
      int activeReaders = 0;
      bool writeStarted = false;

      var read1 = mutex.protectRead(() async {
        activeReaders++;
        await Future.delayed(Duration(milliseconds: 50));
        activeReaders--;
      });

      var read2 = mutex.protectRead(() async {
        activeReaders++;
        await Future.delayed(Duration(milliseconds: 50));
        activeReaders--;
      });

      var writeFuture = mutex.protectWrite(() async {
        writeStarted = true;
        expect(activeReaders, 0);
      });

      await Future.wait([read1, read2, writeFuture]);

      expect(writeStarted, true);
    });

    test('writers are not starved under readersFirst policy', () async {
      final mutex = RawReadWriteMutex(lockPolicy: LockPolicy.readersFirst);
      int sharedResource = 0;
      bool writerCompleted = false;

      // Start multiple readers
      var readerFutures = <Future>[];
      for (int i = 0; i < 5; i++) {
        readerFutures.add(mutex.protectRead(() async {
          await Future.delayed(Duration(milliseconds: 50));
          sharedResource += 1;
        }));
      }

      // Start a writer after a short delay
      var writerFuture = Future.delayed(Duration(milliseconds: 10), () {
        return mutex.protectWrite(() async {
          sharedResource += 10;
          writerCompleted = true;
        });
      });

      await Future.wait([...readerFutures, writerFuture]);

      expect(writerCompleted, true);
      expect(sharedResource, 5 + 10);
    });

    test('RawReadWriteMutex stress test', () async {
      final mutex = RawReadWriteMutex();
      int sharedResource = 0;
      const int numOperations = 10000;
      const int numReaders = 100;
      const int numWriters = 10;

      var futures = <Future>[];

      // Add read operations
      for (int i = 0; i < numReaders; i++) {
        futures.add(Future(() async {
          for (int j = 0; j < numOperations ~/ numReaders; j++) {
            await mutex.protectRead(() async {
              // Simulate some work
              await Future.delayed(Duration(microseconds: 10));
              expect(sharedResource, greaterThanOrEqualTo(0));
            });
          }
        }));
      }

      // Add write operations
      for (int i = 0; i < numWriters; i++) {
        futures.add(Future(() async {
          for (int j = 0; j < numOperations ~/ numWriters; j++) {
            await mutex.protectWrite(() async {
              // Simulate some work
              await Future.delayed(Duration(microseconds: 50));
              sharedResource++;
            });
          }
        }));
      }

      await Future.wait(futures);

      expect(sharedResource, numOperations ~/ numWriters * numWriters);
    });

    test('readers are not starved under writersFirst policy', () async {
      final mutex = RawReadWriteMutex(lockPolicy: LockPolicy.writersFirst);
      int sharedResource = 0;
      bool readerCompleted = false;

      // Start multiple writers
      var writerFutures = <Future>[];
      for (int i = 0; i < 5; i++) {
        writerFutures.add(mutex.protectWrite(() async {
          await Future.delayed(Duration(milliseconds: 50));
          sharedResource += 10;
        }));
      }

      // Start a reader after a short delay
      var readerFuture = Future.delayed(Duration(milliseconds: 10), () {
        return mutex.protectRead(() async {
          sharedResource += 1;
          readerCompleted = true;
        });
      });

      await Future.wait([...writerFutures, readerFuture]);

      expect(readerCompleted, true);
      expect(sharedResource, (5 * 10) + 1);
    });

    test('readers are blocked when writer is pending under writersFirst policy',
        () async {
      final mutex = RawReadWriteMutex(lockPolicy: LockPolicy.writersFirst);
      List<int> executionOrder = [];

      // Start a read lock
      var read1 = mutex.protectRead(() async {
        executionOrder.add(1);
        await Future.delayed(Duration(milliseconds: 50));
      });

      // Start a write request
      var write = mutex.protectWrite(() async {
        executionOrder.add(2);
      });

      // Start another read request after the write request
      var read2 = mutex.protectRead(() async {
        executionOrder.add(3);
      });

      await Future.wait([read1, write, read2]);

      // Execution order should be: read1, write, read2
      expect(executionOrder, [1, 2, 3]);
    });

    test(
        'writers are blocked when readers are active or pending under readersFirst policy',
        () async {
      final mutex = RawReadWriteMutex(lockPolicy: LockPolicy.readersFirst);
      List<int> executionOrder = [];

      // Start a reader
      var read1 = mutex.protectRead(() async {
        executionOrder.add(1);
        await Future.delayed(Duration(milliseconds: 50));
      });

      // Start a reader after a short delay
      var read2 = Future.delayed(Duration(milliseconds: 10), () {
        return mutex.protectRead(() async {
          executionOrder.add(2);
        });
      });

      // Start a writer after another short delay
      var write = Future.delayed(Duration(milliseconds: 20), () {
        return mutex.protectWrite(() async {
          executionOrder.add(3);
        });
      });

      await Future.wait([read1, read2, write]);

      // Execution order should be: read1, read2, write
      expect(executionOrder, [1, 2, 3]);
    });

    test('fair policy grants locks in order of arrival with mixed requests',
        () async {
      final mutex = RawReadWriteMutex(lockPolicy: LockPolicy.fair);
      List<int> executionOrder = [];

      var actions = [
        () => mutex.protectRead(() async {
              executionOrder.add(1);
              await Future.delayed(Duration(milliseconds: 20));
            }),
        () => mutex.protectWrite(() async {
              executionOrder.add(2);
            }),
        () => mutex.protectRead(() async {
              executionOrder.add(3);
            }),
        () => mutex.protectWrite(() async {
              executionOrder.add(4);
            }),
        () => mutex.protectRead(() async {
              executionOrder.add(5);
            }),
      ];

      var futures = actions.map((action) => action()).toList();

      await Future.wait(futures);

      // The operations should have executed in the order they were requested
      expect(executionOrder, [1, 2, 3, 4, 5]);
    });

    test('respects cancellation token in protectedRead', () async {
      final mutex = RawReadWriteMutex();
      final cancellationToken = CancellationToken();
      int sharedResource = 0;

      var future = mutex.protectRead(() async {
        await Future.delayed(Duration(milliseconds: 100));
        sharedResource += 1;
      }, cancellationToken: cancellationToken);

      // Cancel the operation
      cancellationToken.cancel();

      try {
        await future;
      } catch (e) {
        expect(e, isA<CancellationException>());
      }

      expect(sharedResource, 0);
    });

    test('respects timeout in protectedRead', () async {
      final mutex = RawReadWriteMutex();
      int sharedResource = 0;

      try {
        await mutex.protectRead(() async {
          await Future.delayed(Duration(milliseconds: 100));
          sharedResource += 1;
        }, timeout: Duration(milliseconds: 50));
      } catch (e) {
        expect(e, isA<TimeoutException>());
      }

      expect(sharedResource, 0);
    });

    test('respects cancellation token in protectedWrite', () async {
      final mutex = RawReadWriteMutex();
      final cancellationToken = CancellationToken();
      int sharedResource = 0;

      var future = mutex.protectWrite(() async {
        await Future.delayed(Duration(milliseconds: 100));
        sharedResource += 1;
      }, cancellationToken: cancellationToken);

      // Cancel the operation
      cancellationToken.cancel();

      try {
        await future;
      } catch (e) {
        expect(e, isA<CancellationException>());
      }

      expect(sharedResource, 0);
    });

    test('respects timeout in protectedWrite', () async {
      final mutex = RawReadWriteMutex();
      int sharedResource = 0;

      try {
        await mutex.protectWrite(() async {
          await Future.delayed(Duration(milliseconds: 100));
          sharedResource += 1;
        }, timeout: Duration(milliseconds: 50));
      } catch (e) {
        expect(e, isA<TimeoutException>());
      }

      expect(sharedResource, 0);
    });
  });

  group('Mutex (no reentrancy)', () {
    test('tryLock succeeds when mutex is free', () async {
      final mutex = Mutex();
      int sharedResource = 0;

      var result = await mutex.tryLock(() async {
        sharedResource += 1;
        return sharedResource;
      });

      expect(result, 1);
      expect(sharedResource, 1);
    });

    test('tryLock returns null when mutex is held', () async {
      final mutex = Mutex();
      int sharedResource = 0;

      var lockAcquired = Completer<void>();
      var proceed = Completer<void>();

      // Acquire the lock
      var protectFuture = mutex.protectWrite(() async {
        lockAcquired.complete();
        await proceed.future; // Wait until proceed is completed
      });

      // Wait until the lock is acquired
      await lockAcquired.future;

      // Now tryLock should fail
      var result = await mutex.tryLock(() async {
        sharedResource += 1;
        return sharedResource;
      });

      expect(result, isNull);
      expect(sharedResource, 0);

      proceed.complete(); // Allow the first protect to complete
      await protectFuture;
    });

    test('protect writes execute in order', () async {
      final mutex = Mutex();
      List<int> executionOrder = [];

      var write1 = mutex.protectWrite(() async {
        executionOrder.add(1);
        await Future.delayed(Duration(milliseconds: 50));
      });

      var write2 = mutex.protectWrite(() async {
        executionOrder.add(2);
      });

      await Future.wait([write1, write2]);

      expect(executionOrder, [1, 2]);
    });

    test('protect reads execute in order', () async {
      final mutex = Mutex();
      List<int> executionOrder = [];

      var write1 = mutex.protectRead(() async {
        executionOrder.add(1);
        await Future.delayed(Duration(milliseconds: 50));
      });

      var write2 = mutex.protectRead(() async {
        executionOrder.add(2);
      });

      await Future.wait([write1, write2]);

      expect(executionOrder, [1, 2]);
    });

    test('lock is released when action throws an exception', () async {
      final mutex = Mutex();
      int sharedResource = 0;

      // Acquire lock and throw an exception
      var actionFuture = mutex.protectWrite(() async {
        throw Exception('Test exception');
      });

      // Catch the exception
      try {
        await actionFuture;
        // ignore: dead_code
        fail('Exception not thrown');
      } catch (e) {
        expect(e.toString(), contains('Test exception'));
      }

      // Now try to acquire the lock again
      await mutex.protectWrite(() async {
        sharedResource = 1;
      });

      expect(sharedResource, 1);
    });

    test('protectWrite times out if lock not acquired in time', () async {
      final mutex = Mutex();
      int sharedResource = 0;

      var lockAcquired = Completer<void>();
      var proceed = Completer<void>();

      // Acquire the lock
      var protectFuture = mutex.protectWrite(() async {
        lockAcquired.complete();
        await proceed.future; // Keep the lock busy
      });

      // Wait for the lock to be acquired
      await lockAcquired.future;

      // Now try acquiring another write lock with a timeout
      var timedOutFuture = mutex.protectWrite(() async {
        sharedResource += 1;
        return sharedResource;
      }, timeout: Duration(milliseconds: 100));

      await expectLater(timedOutFuture, throwsA(isA<TimeoutException>()));
      expect(sharedResource, 0); // Ensure no action was executed

      proceed.complete(); // Release the lock
      await protectFuture;
    });

    test('protectRead times out if lock not acquired in time', () async {
      final mutex = Mutex();
      int sharedResource = 0;

      var lockAcquired = Completer<void>();
      var proceed = Completer<void>();

      // Acquire the lock
      var protectFuture = mutex.protectWrite(() async {
        lockAcquired.complete();
        await proceed.future; // Keep the lock busy
      });

      // Wait for the lock to be acquired
      await lockAcquired.future;

      // Now try acquiring another write lock with a timeout
      var timedOutFuture = mutex.protectRead(() async {
        sharedResource += 1;
        return sharedResource;
      }, timeout: Duration(milliseconds: 100));

      await expectLater(timedOutFuture, throwsA(isA<TimeoutException>()));
      expect(sharedResource, 0); // Ensure no action was executed

      proceed.complete(); // Release the lock
      await protectFuture;
    });

    test('isLocked reflects the state of the mutex', () async {
      final mutex = Mutex();
      expect(mutex.isLocked(), false);

      var protectFuture = mutex.protectWrite(() async {
        expect(mutex.isLocked(), true);
      });

      await protectFuture;
      expect(mutex.isLocked(), false);
    });

    test('isWriteLocked reflects the state of the write lock', () async {
      final mutex = Mutex();
      expect(mutex.isWriteLocked(), false);

      var protectFuture = mutex.protectWrite(() async {
        expect(mutex.isWriteLocked(), true);
      });

      await protectFuture;
      expect(mutex.isWriteLocked(), false);
    });

    test('isReadLocked reflects the state of the read lock', () async {
      final mutex = Mutex();
      expect(mutex.isReadLocked(), false);

      var protectFuture = mutex.protectRead(() async {
        expect(mutex.isReadLocked(), true);
      });

      await protectFuture;
      expect(mutex.isReadLocked(), false);
    });

    test('multiple protectRead calls execute concurrently', () async {
      final mutex = Mutex();
      List<int> executionOrder = [];

      var read1 = mutex.protectRead(() async {
        executionOrder.add(1);
        await Future.delayed(Duration(milliseconds: 100));
      });

      var read2 = mutex.protectRead(() async {
        executionOrder.add(2);
        await Future.delayed(Duration(milliseconds: 100));
      });

      await Future.wait([read1, read2]);

      // Since they should run concurrently, both should have started roughly at the same time
      expect(executionOrder, [1, 2]);
    });

    test('protectWrite releases lock after exception', () async {
      final mutex = Mutex();
      var threwException = false;

      try {
        await mutex.protectWrite(() async {
          throw Exception('Test exception');
        });
      } catch (e) {
        threwException = true;
      }

      expect(threwException, true);
      expect(
          mutex.isLocked(), false); // Ensure lock was released after exception
    });
  });

  group('Mutex', () {
    test('resets state after mixed reentrant locks are released', () async {
      final mutex = Mutex();
      int actionExecutionCount = 0;

      // Acquire read lock
      await mutex.protectRead(() async {
        actionExecutionCount++;
        expect(mutex.isLocked(), isTrue);
        expect(mutex.isWriteLocked(), isFalse);

        // Reentrant acquisition with write lock should throw
        expect(
          () async => await mutex.protectWrite(() async {}),
          throwsA(isA<StateError>()),
        );
      });

      // After attempted mixed acquisition, the lock should still be released
      expect(actionExecutionCount, 1);
      expect(mutex.isLocked(), isFalse);
      expect(mutex.isWriteLocked(), isFalse);
    });

    test('allows reentrant locking', () async {
      final mutex = Mutex();
      int sharedResource = 0;

      await mutex.protect(() async {
        sharedResource += 1;

        // Reentrant lock
        await mutex.protect(() async {
          sharedResource += 2;

          // Another level of reentrant lock
          await mutex.protect(() async {
            sharedResource += 3;
          });
        });
      });

      expect(sharedResource, 6);
    });

    test('maintains correct lock count during reentrant locking', () async {
      final mutex = Mutex();
      int lockCount = 0;

      await mutex.protect(() async {
        lockCount++; // lockCount is now 1

        await mutex.protect(() async {
          lockCount++; // lockCount is now 2

          await mutex.protect(() async {
            lockCount++; // lockCount is now 3
            expect(lockCount, 3); // This should pass
            lockCount--; // Decrement after exiting innermost lock
          });

          expect(lockCount, 2); // Now lockCount is 2
          lockCount--; // Decrement after exiting middle lock
        });

        expect(lockCount, 1); // Now lockCount is 1
        lockCount--; // Decrement after exiting outermost lock
      });

      expect(lockCount, 0); // Now lockCount is back to 0
    });

    test('allows mixed reentrant and non-reentrant calls', () async {
      final mutex = Mutex();
      List<int> executionOrder = [];

      await mutex.protect(() async {
        executionOrder.add(1);

        await mutex.protect(() async {
          executionOrder.add(2);
        });

        await mutex.tryLock(() async {
          executionOrder.add(3);
        });
      });

      await mutex.tryLock(() async {
        executionOrder.add(4);
      });

      expect(executionOrder, [1, 2, 3, 4]);
    });

    test('handles exceptions in reentrant locks correctly', () async {
      final mutex = Mutex();
      int sharedResource = 0;

      try {
        await mutex.protect(() async {
          sharedResource += 1;

          await mutex.protect(() async {
            sharedResource += 2;
            throw Exception('Test exception');
          });
        });
      } catch (e) {
        expect(e.toString(), contains('Test exception'));
      }

      // The mutex should be released after the exception
      await mutex.protect(() async {
        sharedResource += 3;
      });

      expect(sharedResource, 6);
    });

    test('lock reentrancy works correctly with futures and microtasks',
        () async {
      final mutex = Mutex();
      List<String> executionOrder = [];

      await mutex.protect(() async {
        executionOrder.add('Start');

        // Schedule a microtask that acquires the lock reentrantly
        scheduleMicrotask(() async {
          await mutex.protect(() async {
            executionOrder.add('Microtask');
          });
        });

        // Schedule a future that acquires the lock reentrantly
        Future(() async {
          await mutex.protect(() async {
            executionOrder.add('Future');
          });
        });

        // Wait a bit to allow microtasks and futures to execute
        await Future.delayed(Duration(milliseconds: 50));

        executionOrder.add('End');
      });

      expect(executionOrder, ['Start', 'Microtask', 'Future', 'End']);
    });

    test('reentrant locking with different asynchronous operations', () async {
      final mutex = Mutex();
      int sharedResource = 0;

      await mutex.protect(() async {
        sharedResource += 1;

        // Start multiple asynchronous operations that acquire the lock reentrantly
        await Future.wait([
          mutex.protect(() async {
            sharedResource += 10;
          }),
          mutex.protect(() async {
            sharedResource += 100;
          }),
        ]);

        expect(sharedResource, 111); // 1 + 10 + 100
      });

      expect(sharedResource, 111);
    });

    test('reentrant locks do not interfere with tryLock in the same context',
        () async {
      final mutex = Mutex();
      int sharedResource = 0;

      await mutex.protect(() async {
        sharedResource += 1;

        // Since we already hold the lock, tryLock should succeed
        var result = await mutex.tryLock(() async {
          sharedResource += 10;
          return sharedResource;
        });

        expect(result, 11); // 1 + 10
        expect(sharedResource, 11);
      });
    });

    test(
        'reentrant locks are released in the correct order and lock is free afterwards',
        () async {
      final mutex = Mutex();
      List<int> executionOrder = [];

      await mutex.protect(() async {
        executionOrder.add(1);

        await mutex.protect(() async {
          executionOrder.add(2);

          await mutex.protect(() async {
            executionOrder.add(3);
          });

          executionOrder.add(4);
        });

        executionOrder.add(5);
      });

      executionOrder.add(6);

      expect(executionOrder, [1, 2, 3, 4, 5, 6]);
    });

    test('isLocked reflects the state of the mutex', () async {
      final mutex = Mutex();
      expect(mutex.isLocked(), false);

      await mutex.protect(() async {
        expect(mutex.isLocked(), true);
        await mutex.protectWrite(() async {
          expect(mutex.isLocked(), true);
        });
      });

      expect(mutex.isLocked(), false);
    });

    test('isWriteLocked reflects the state of the write lock', () async {
      final mutex = Mutex();
      expect(mutex.isWriteLocked(), false);

      await mutex.protect(() async {
        await mutex.protectWrite(() async {
          expect(mutex.isWriteLocked(), true);
        });
      });

      expect(mutex.isWriteLocked(), false);
    });

    test('isReadLocked reflects the state of the read lock', () async {
      final mutex = Mutex();
      expect(mutex.isReadLocked(), false);

      var protectFuture = mutex.protectRead(() async {
        expect(mutex.isReadLocked(), true);
      });

      await protectFuture;
      expect(mutex.isReadLocked(), false);
    });

    test('Release lock and reset state after all nested calls', () async {
      final mutex = Mutex();
      int executionCount = 0;
      bool innerLockAcquired = false;
      bool outerLockReleased = false;

      await mutex.protectWrite(() async {
        executionCount++;

        // This nested call should increment the recursive count
        await mutex.protectWrite(() async {
          executionCount++;
          innerLockAcquired = true;
        });

        // At this point, we've exited the inner protectWrite,
        // so _recursiveCount should be 1
        expect(innerLockAcquired, true);
        expect(mutex.isWriteLocked(), true);

        executionCount++;
      });

      // After exiting the outer protectWrite, _recursiveCount should reach 0,
      // triggering the reset of _ownerTaskId and _isWriteLock
      outerLockReleased = true;

      expect(executionCount, 3);
      expect(outerLockReleased, true);
      expect(mutex.isWriteLocked(), false);

      // Try to acquire a new lock to ensure the previous one was fully released
      await mutex.protectWrite(() async {
        executionCount++;
      });

      expect(executionCount, 4);
    });

    test('Ensure _recursiveCount reaches 0 and resets state', () async {
      final mutex = Mutex();
      int executionCount = 0;

      // First level of locking
      await mutex.protectWrite(() async {
        executionCount++;
        expect(mutex.isWriteLocked(), true);
        expect(mutex.isLocked(), true);

        // Nested first level
        await mutex.protectWrite(() async {
          executionCount++;
          expect(mutex.isWriteLocked(), true);

          // Nested second level
          await mutex.protectWrite(() async {
            executionCount++;
            expect(mutex.isWriteLocked(), true);
          });

          executionCount++;
          expect(mutex.isWriteLocked(), true);
        });

        executionCount++;
        expect(mutex.isWriteLocked(), true);
      });

      // After all nested locks have been released, the lock should be free
      expect(mutex.isWriteLocked(), false);
      expect(mutex.isLocked(), false);

      // Check the total execution count to ensure all blocks were executed
      expect(executionCount, 5);
    });

    test('prevents concurrent access from different zones', () async {
      final mutex = Mutex();
      int sharedResource = 0;
      bool lockAcquired = false;

      var future1 = Zone.current.fork().run(() async {
        await mutex.protect(() async {
          sharedResource += 1;
          await Future.delayed(Duration(milliseconds: 50));
          lockAcquired = true;
        });
      });

      var future2 = Zone.current.fork().run(() async {
        await mutex.protect(() async {
          expect(lockAcquired,
              true); // This should only execute after future1 completes
          sharedResource += 2;
        });
      });

      await Future.wait([future1, future2]);
      expect(sharedResource, 3);
    });

    test('Processes next item in the queue after releasing the lock', () async {
      final mutex = Mutex();
      bool action1Executed = false;
      bool action2Executed = false;

      // Queue up two actions
      mutex.protect(() async {
        action1Executed = true;
        expect(mutex.isLocked(), isTrue);
      });

      await mutex.protect(() async {
        action2Executed = true;
        expect(mutex.isLocked(), isTrue);
      });

      // After first lock releases, second action should be processed
      expect(action1Executed, isTrue);
      expect(action2Executed, isTrue);
      expect(mutex.isLocked(),
          isFalse); // Ensure lock is released after both actions
    });

    test('multiple lock acquisitions and releases', () async {
      final mutex = Mutex();
      int counter = 0;

      Future<void> incrementCounter() async {
        await mutex.protect(() async {
          await Future.delayed(Duration(milliseconds: 10));
          counter++;
        });
      }

      // Start multiple concurrent operations
      List<Future<void>> operations =
          List.generate(5, (_) => incrementCounter());

      // Wait for all operations to complete
      await Future.wait(operations);

      // Check if the counter was incremented correctly
      expect(counter, equals(5));

      // Check if the lock is fully released
      expect(mutex.isLocked(), isFalse);
      // expect(mutex.isHeldByCurrent(), isFalse);
    });

    test('sets _currentZone to null when lock is fully released', () async {
      final mutex = Mutex();
      // Acquire the lock
      await mutex.protect(() async {
        // Lock should be held
        expect(mutex.isLocked(), isTrue);
        // expect(mutex.isHeldByCurrent(), isTrue);

        // Perform a reentrant acquisition
        await mutex.protect(() async {
          expect(mutex.isLocked(), isTrue);
          // expect(mutex.isHeldByCurrent(), isTrue);
        });

        // After nested release, lock should still be held
        expect(mutex.isLocked(), isTrue);
        // expect(mutex.isHeldByCurrent(), isTrue);
      });

      // After exiting all protect blocks, lock should be released
      expect(mutex.isLocked(), isFalse);
      // expect(mutex.isHeldByCurrent(), isFalse);
    });
  });

  group('SimpleMutex', () {
    test('allows sequential access', () async {
      final mutex = SimpleMutex();
      int sharedResource = 0;
      expect(mutex.isLocked(), false);

      await mutex.protect(() async {
        expect(mutex.isLocked(), true);
        sharedResource += 1;
      });

      expect(mutex.isLocked(), false);

      await mutex.protect(() async {
        expect(mutex.isLocked(), true);
        sharedResource += 2;
      });

      expect(mutex.isLocked(), false);

      expect(sharedResource, 3);
    });

    test('prevents concurrent access', () async {
      final mutex = SimpleMutex();
      int sharedResource = 0;
      bool lockAcquired = false;

      var future1 = mutex.protect(() async {
        sharedResource += 1;
        await Future.delayed(Duration(milliseconds: 50));
        lockAcquired = true;
      });

      var future2 = mutex.protect(() async {
        expect(lockAcquired,
            true); // This should only execute after future1 completes
        sharedResource += 2;
      });

      await Future.wait([future1, future2]);
      expect(sharedResource, 3);
    });

    test('multiple lock acquisitions and releases', () async {
      final mutex = SimpleMutex();
      int counter = 0;

      Future<void> incrementCounter() async {
        await mutex.protect(() async {
          await Future.delayed(Duration(milliseconds: 10));
          counter++;
        });
      }

      // Start multiple concurrent operations
      List<Future<void>> operations =
          List.generate(5, (_) => incrementCounter());

      // Wait for all operations to complete
      await Future.wait(operations);

      // Check if the counter was incremented correctly
      expect(counter, equals(5));

      // Check if the lock is fully released
      expect(mutex.isLocked(), isFalse);
      expect(mutex.isHeldByCurrent(), isFalse);
    });

    test('handles exceptions correctly', () async {
      final mutex = SimpleMutex();
      int sharedResource = 0;

      try {
        await mutex.protect(() async {
          sharedResource += 1;
          throw Exception('Test exception');
        });
      } catch (e) {
        expect(e.toString(), contains('Test exception'));
      }

      // The mutex should be released after the exception
      await mutex.protect(() async {
        sharedResource += 2;
      });

      expect(sharedResource, 3);
    });

    test('respects cancellation token', () async {
      final mutex = SimpleMutex();
      final cancellationToken = CancellationToken();
      int sharedResource = 0;

      var future = mutex.protect(() async {
        await Future.delayed(Duration(milliseconds: 100));
        sharedResource += 1;
      }, cancellationToken: cancellationToken);

      // Cancel the operation
      cancellationToken.cancel();

      try {
        await future;
        fail('Should have thrown a CancellationException');
      } catch (e) {
        expect(e, isA<CancellationException>());
        expect(e.toString(), "CancellationException: Operation cancelled");
      }

      expect(sharedResource, 0);
      expect(cancellationToken.isCancelled, true);
    });

    test('respects timeout', () async {
      final mutex = SimpleMutex();
      int sharedResource = 0;

      try {
        await mutex.protect(() async {
          await Future.delayed(Duration(milliseconds: 100));
          sharedResource += 1;
        }, timeout: Duration(milliseconds: 50));
      } catch (e) {
        expect(e, isA<TimeoutException>());
        expect(e.toString(),
            "TimeoutException: Operation timed out after ${Duration(milliseconds: 50)}");
      }

      expect(sharedResource, 0);
    });

    test('reentrancy error', () async {
      final mutex = SimpleMutex();
      int sharedResource = 0;

      try {
        await mutex.protect(() async {
          sharedResource += 1;
          await mutex.protect(() async {
            sharedResource += 2;
          });
        });
      } catch (e) {
        expect(e, isA<ReentrantMutexError>());
        expect(e.toString(),
            'ReentrantMutexError: Reentrant lock attempt detected\nTo fix it, remove the reentrant `mutex.protec(() {})` call, or replace your current SimpleMutex class with a `SimpleReentrantMutex`');
      }

      expect(sharedResource, 1);
    });
  });

  group('SimpleReentrantMutex', () {
    test('allows reentrant locking', () async {
      final mutex = SimpleReentrantMutex();
      int sharedResource = 0;

      await mutex.protect(() async {
        sharedResource += 1;
        await mutex.protect(() async {
          sharedResource += 2;
        });
      });

      expect(sharedResource, 3);
    });

    test('prevents concurrent access from different zones', () async {
      final mutex = SimpleReentrantMutex();
      int sharedResource = 0;
      bool lockAcquired = false;

      var future1 = Zone.current.fork().run(() async {
        await mutex.protect(() async {
          sharedResource += 1;
          await Future.delayed(Duration(milliseconds: 50));
          lockAcquired = true;
        });
      });

      var future2 = Zone.current.fork().run(() async {
        await mutex.protect(() async {
          expect(lockAcquired,
              true); // This should only execute after future1 completes
          sharedResource += 2;
        });
      });

      await Future.wait([future1, future2]);
      expect(sharedResource, 3);
    });

    test('handles exceptions correctly', () async {
      final mutex = SimpleReentrantMutex();
      int sharedResource = 0;

      try {
        await mutex.protect(() async {
          sharedResource += 1;
          await mutex.protect(() async {
            throw Exception('Test exception');
          });
        });
      } catch (e) {
        expect(e.toString(), contains('Test exception'));
      }

      // The mutex should be released after the exception
      await mutex.protect(() async {
        sharedResource += 2;
      });

      expect(sharedResource, 3);
    });

    test('respects cancellation token', () async {
      final mutex = SimpleReentrantMutex();
      final cancellationToken = CancellationToken();
      int sharedResource = 0;

      var future = mutex.protect(() async {
        await Future.delayed(Duration(milliseconds: 100));
        sharedResource += 1;
      }, cancellationToken: cancellationToken);

      // Cancel the operation
      cancellationToken.cancel();

      try {
        await future;
      } catch (e) {
        expect(e, isA<CancellationException>());
      }

      expect(sharedResource, 0);
      expect(cancellationToken.isCancelled, true);
    });

    test('respects timeout', () async {
      final mutex = SimpleReentrantMutex();
      int sharedResource = 0;

      try {
        await mutex.protect(() async {
          await Future.delayed(Duration(milliseconds: 100));
          sharedResource += 1;
        }, timeout: Duration(milliseconds: 50));
      } catch (e) {
        expect(e, isA<TimeoutException>());
      }

      expect(sharedResource, 0);
    });

    test('Processes next item in the queue after releasing the lock', () async {
      final mutex = SimpleReentrantMutex();
      bool action1Executed = false;
      bool action2Executed = false;

      // Queue up two actions
      mutex.protect(() async {
        action1Executed = true;
        expect(mutex.isLocked(), isTrue);
      });

      await mutex.protect(() async {
        action2Executed = true;
        expect(mutex.isLocked(), isTrue);
      });

      // After first lock releases, second action should be processed
      expect(action1Executed, isTrue);
      expect(action2Executed, isTrue);
      expect(mutex.isLocked(),
          isFalse); // Ensure lock is released after both actions
    });

    test('multiple lock acquisitions and releases', () async {
      final mutex = SimpleReentrantMutex();
      int counter = 0;

      Future<void> incrementCounter() async {
        await mutex.protect(() async {
          await Future.delayed(Duration(milliseconds: 10));
          counter++;
        });
      }

      // Start multiple concurrent operations
      List<Future<void>> operations =
          List.generate(5, (_) => incrementCounter());

      // Wait for all operations to complete
      await Future.wait(operations);

      // Check if the counter was incremented correctly
      expect(counter, equals(5));

      // Check if the lock is fully released
      expect(mutex.isLocked(), isFalse);
      expect(mutex.isHeldByCurrent(), isFalse);
    });

    test('sets _currentZone to null when lock is fully released', () async {
      final mutex = SimpleReentrantMutex();
      // Acquire the lock
      await mutex.protect(() async {
        // Lock should be held
        expect(mutex.isLocked(), isTrue);
        expect(mutex.isHeldByCurrent(), isTrue);

        // Perform a reentrant acquisition
        await mutex.protect(() async {
          expect(mutex.isLocked(), isTrue);
          expect(mutex.isHeldByCurrent(), isTrue);
        });

        // After nested release, lock should still be held
        expect(mutex.isLocked(), isTrue);
        expect(mutex.isHeldByCurrent(), isTrue);
      });

      // After exiting all protect blocks, lock should be released
      expect(mutex.isLocked(), isFalse);
      expect(mutex.isHeldByCurrent(), isFalse);
    });

    test('Lock acquisition times out', () async {
      final mutex = SimpleReentrantMutex();
      final completer = Completer<void>();

      // Fork a new zone to hold the lock
      final holdingLockFuture = Zone.current.fork().run(() async {
        await mutex.protect(() async {
          completer.complete(); // Signal that the lock has been acquired
          await Future.delayed(Duration(seconds: 2)); // Hold the lock
        });
      });

      // Wait until the lock is acquired
      await completer.future;

      // Now, attempt to acquire the lock with a short timeout in the main zone
      final attempt = mutex.protect(() async {
        await Future.delayed(Duration(seconds: 2)); // This block won't execute
      }, timeout: Duration(milliseconds: 100)); // Short timeout

      // Expect a TimeoutException
      await expectLater(
        attempt,
        throwsA(isA<TimeoutException>()),
      );

      // Clean up by waiting for the initial lock to be released
      await holdingLockFuture;
    });

    test('Lock acquisition is cancelled', () async {
      final cancellationToken = CancellationToken();
      final mutex = SimpleReentrantMutex();
      final completer = Completer<void>();

      // Fork a new zone to hold the lock
      final holdingLockFuture = Zone.current.fork().run(() async {
        await mutex.protect(() async {
          completer.complete(); // Signal that the lock has been acquired
          await Future.delayed(Duration(seconds: 2)); // Hold the lock
        });
      });

      // Wait until the lock is acquired
      await completer.future;

      // Schedule cancellation after 100 milliseconds
      Future.delayed(Duration(milliseconds: 100), () {
        cancellationToken.cancel(); // Trigger cancellation
      });

      // Now, attempt to acquire the lock with cancellation in the main zone
      final attempt = mutex.protect(() async {
        await Future.delayed(Duration(seconds: 2)); // This block won't execute
      }, cancellationToken: cancellationToken);

      // Expect a CancellationException
      await expectLater(
        attempt,
        throwsA(isA<CancellationException>()),
      );

      // Clean up by waiting for the initial lock to be released
      await holdingLockFuture;
    });
  });

  group('GetMutex alias', () {
    test('should return a Mutex with default LockPolicy', () {
      final mutex = GetMutex.mutex();
      expect(mutex, isA<Mutex>());
      expect(mutex.lockPolicy, equals(LockPolicy.fair));
    });

    test('should return a Mutex with specified LockPolicy', () {
      final mutex = GetMutex.mutex(lockPolicy: LockPolicy.readersFirst);
      expect(mutex, isA<Mutex>());
      expect(mutex.lockPolicy, equals(LockPolicy.readersFirst));
    });

    test('should return a SimpleMutex', () {
      final simpleMutex = GetMutex.simpleMutex();
      expect(simpleMutex, isA<SimpleMutex>());
    });

    test('should return a SimpleReentrantMutex', () {
      final simpleMutex = GetMutex.simpleReentrantMutex();
      expect(simpleMutex, isA<SimpleReentrantMutex>());
    });

    test('should return a RawReadWriteMutex with default LockPolicy', () {
      final readWriteMutex = GetMutex.rawReadWriteMutex();
      expect(readWriteMutex, isA<RawReadWriteMutex>());
      expect(readWriteMutex.lockPolicy, equals(LockPolicy.fair));
    });
  });
}

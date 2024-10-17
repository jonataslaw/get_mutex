# GetMutex: Bulletproof Concurrency for Dart

[![Pub Version](https://img.shields.io/pub/v/get_mutex.svg)](https://pub.dev/packages/get_mutex)
[![codecov](https://codecov.io/gh/jonataslaw/get_mutex/graph/badge.svg?token=50GQ1E62P4)](https://codecov.io/gh/jonataslaw/get_mutex)

🔒 **GetMutex** is your solution for robust, efficient, and deadlock-free synchronization in Dart. Concurrency made simple, without sacrificing performance.

## Why GetMutex?

In the world of concurrent programming, race conditions can wreak havoc on your code, leading to unpredictable outcomes. GetMutex is here to eliminate those risks while offering:

- 🚀 **High Performance**: Outperforms naive `await`-based solutions by up to 2x in our benchmarks.
- 🛡️ **Reliable Protection**: Locks down your critical sections with precision, ensuring data integrity.
- 🧠 **Simple API**: User-friendly, intuitive API that makes concurrency less daunting.
- 🔬 **100% Test Coverage**: We take your data's safety seriously, and it shows.

Let’s dive into a real-world example to illustrate why GetMutex is indispensable.

## The Bank Account Problem: A Case of Concurrent Chaos

Imagine you're building a banking app. Without proper synchronization, concurrent transfers can lead to financial discrepancies. Here’s what happens without GetMutex:

### Without Synchronization (Prone to Race Conditions)

Imagine you're building a banking app. Without proper synchronization, you're one concurrent transfer away from a financial disaster. Let's see what happens without GetMutex:

```dart
import 'dart:async';

class BankAccount {
  final String accountNumber;
  double balance;

  BankAccount(this.accountNumber, this.balance);

  Future<bool> transfer(BankAccount targetAccount, double amount) async {
    if (amount > balance) {
      return false; // Insufficient funds
    }

    await Future.delayed(Duration(milliseconds: 50)); // Simulating processing time

    balance -= amount;

    await Future.delayed(Duration(milliseconds: 50)); // Simulate some delay

    targetAccount.balance += amount;

    return true;
  }
}

void main() async {
  final accountA = BankAccount('Account A', 1000);
  final accountB = BankAccount('Account B', 500);

  // Simulate multiple concurrent transfers
  final transfers = [
    accountA.transfer(accountB, 200), // Account A: $800, Account B: $700
    accountA.transfer(accountB, 300), // Account A: $500, Account B: $1000
    accountB.transfer(accountA, 100), // Account A: $600, Account B: $900
    accountB.transfer(accountA, 700), // Account A: $1300, Account B: $200
  ];

  final results = await Future.wait(transfers);

  print('Transfer Results:');
  for (var result in results) {
    print(result ? 'Transfer succeeded' : 'Transfer failed');
  }
  // Possible Output:
  // Transfer succeeded
  // Transfer succeeded
  // Transfer succeeded
  // Transfer failed

  print('Final Balances:');
  print('${accountA.accountNumber}: \$${accountA.balance}');
  print('${accountB.accountNumber}: \$${accountB.balance}');
  // Possible Output:
  // Account A: $600.0
  // Account B: $900.0
}
```

### The Problem

You might expect the final balances to be:

- Account A: $1300.0
- Account B: $200.0

But due to race conditions, you could end up with:

- Account A: $600.0
- Account B: $900.0

Money has been created out of thin air! 💸 This is because multiple transfers are happening concurrently without proper synchronization.

### The "Await" Solution (Spoiler: It's Slow)

You might think, "I'll just use `await` before each operation!" Sure, it works, but at what cost?

```dart
void main() async {
  final accountA = BankAccount('Account A', 1000);
  final accountB = BankAccount('Account B', 500);

  final clockWatch = Stopwatch()..start();
  await accountA.transfer(accountB, 200);
  await accountA.transfer(accountB, 300);
  await accountB.transfer(accountA, 100);
  await accountB.transfer(accountA, 700);
  clockWatch.stop();
  print('Elapsed time using await: ${clockWatch.elapsedMilliseconds} ms');
  // Output: Elapsed time using await: 209 ms
}
```

### Enter GetMutex: Safe and Swift

Now, let's see how GetMutex handles this with grace and speed:

```dart
import 'package:get_mutex/get_mutex.dart';

class BankAccount {
  final String accountNumber;
  double balance;
  final mutex = Mutex();

  BankAccount(this.accountNumber, this.balance);

  Future<bool> transfer(BankAccount targetAccount, double amount) async {
    return await mutex.protectWrite(() async {
      if (amount > balance) return false;
      balance -= amount;
      await targetAccount.deposit(amount);
      return true;
    });
  }

  Future<void> deposit(double amount) async => balance += amount;
}

void main() async {
  final accountA = BankAccount('Account A', 1000);
  final accountB = BankAccount('Account B', 500);

  final transfers = [
    accountA.transfer(accountB, 200),
    accountA.transfer(accountB, 300),
    accountB.transfer(accountA, 100),
    accountB.transfer(accountA, 700),
  ];

  final clockWatch = Stopwatch()..start();
  await Future.wait(transfers);
  clockWatch.stop();
  print('Elapsed time using mutex: ${clockWatch.elapsedMilliseconds} ms');
  // Output: Elapsed time using mutex: 107 ms

  print('Final Balances:');
  print('${accountA.accountNumber}: \$${accountA.balance}'); // Account A: $1300.0
  print('${accountB.accountNumber}: \$${accountB.balance}'); // Account B: $200.0
}
```

With GetMutex, not only are your accounts safe and your transfers atomic, but you're also doing it in half the time! 🚀

## Features That'll Make You Smile

- 🔄 **Simple and Reentrant Mutexes**: Lock it once, lock it twice, we've got you covered.
- 📚 **Read-Write Locks**: Because sometimes, sharing is caring (and performant).
- ⏱️ **Timeouts and Cancellation**: Because even mutexes shouldn't wait forever.
- 🎛️ **Flexible Policies**: Fair, readers-first, or writers-first – you're in control.

## Getting Started

1. Add GetMutex to your `pubspec.yaml`:

   ```yaml
   dependencies:
     get_mutex: ^1.0.0
   ```

2. Run: `dart pub get`

3. Import and enjoy:

   ```dart
   import 'package:get_mutex/get_mutex.dart';

   final mutex = Mutex();
   await mutex.protectWrite(() {
     // Your critical section here
     print('Writing safely!');
   });
   ```

## Advanced Usage

GetMutex grows with your needs. Need more control? We've got you covered:

```dart
final mutex = Mutex();

// Optimize for multiple readers
await mutex.protectRead(() => print('Reading in parallel'));

// Ensure exclusive access for writers
await mutex.protectWrite(() => print('Writing exclusively'));

// Set a timeout to avoid deadlocks
await mutex.protectWrite(() => longOperation(), timeout: Duration(seconds: 5));

// Use cancellation for more control
final token = CancellationToken();
await mutex.protectWrite(() => cancelableOperation(), cancellationToken: token);
```

We also support raw read-write locks for fine-grained control over your shared resources, but with the same ease of use (however, we recommend using `Mutex` for most cases, RawReadWriteMutex is more low-level, and HAVE NO SUPPORT for reentrant locks):

```dart
final rwMutex = RawReadWriteMutex();

await rwMutex.protectRead(() => print('Reading in parallel'));
await rwMutex.protectWrite(() => print('Writing exclusively'));


Future<T> myCustomProtectWrite<T>(
    Future<T> Function() action, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) async {
    await rwMutex.acquireWrite(cancellationToken: cancellationToken, timeout: timeout);
    try {
      return await action();
    } finally {
      rwMutex.releaseWrite();
    }
}
```

Do you want keep it simple? We have a SimpleMutex/SimpleReentrantMutex for you:

```dart
final simpleMutex = SimpleMutex();
await simpleMutex.protect(() => print('Simple Mutex'));
```

```dart
final simpleReentrantMutex = SimpleReentrantMutex();
await simpleReentrantMutex.protect(() {
  print('Simple Reentrant Mutex');
  simpleReentrantMutex.protect(() => print('Reentrant Mutex inside'));
});
```

For sake of simplicity, we have an `alias` GetMutex class that has all available mutexes:

```dart
final mutex = GetMutex.mutex();
await mutex.protectWrite(() => print('Writing safely!'));

final rwMutex = GetMutex.rawReadWriteMutex();
await rwMutex.protectRead(() => print('Reading in parallel'));

final simpleMutex = GetMutex.simpleMutex();
await simpleMutex.protect(() => print('Simple Mutex'));

final simpleReentrantMutex = GetMutex.simpleReentrantMutex();
await simpleReentrantMutex.protect(() {
  print('Simple Reentrant Mutex');
  simpleReentrantMutex.protect(() => print('Reentrant Mutex inside'));
});
```

- 🐛 Found a bug? Open an [issue](https://github.com/yourusername/get_mutex/issues).
- 💡 Have an idea? Submit a [pull request](https://github.com/yourusername/get_mutex/pulls).
- 🤔 Questions? Start a [discussion](https://github.com/yourusername/get_mutex/discussions).

## License

GetMutex is released under the MIT License. See the [LICENSE](LICENSE) file for details.

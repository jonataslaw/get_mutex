import 'dart:async';

import 'package:get_mutex/get_mutex.dart';
import 'package:test/test.dart';

class BankAccount {
  final String accountNumber;
  double balance;
  final mutex = Mutex();

  BankAccount(this.accountNumber, this.balance);

  Future<bool> transferWithMutex(
      BankAccount targetAccount, double amount) async {
    return mutex.protectWrite(() => transfer(targetAccount, amount));
  }

  Future<bool> transfer(BankAccount targetAccount, double amount) async {
    bool sufficientFunds = false;
    sufficientFunds = amount <= balance;
    if (sufficientFunds) {
      balance -= amount;
    }

    if (!sufficientFunds) {
      return false; // Insufficient funds
    }

    await Future.delayed(
        Duration(milliseconds: 50)); // Simulating processing time

    await targetAccount.deposit(amount);

    return true;
  }

  Future<void> deposit(double amount) async {
    balance += amount;
  }
}

void main() async {
  test('concurrent transfers', () async {
    final accountA = BankAccount('Account A', 1000);
    final accountB = BankAccount('Account B', 500);

    final clockWatch = Stopwatch()..start();
    await accountA.transfer(accountB, 200);
    await accountA.transfer(accountB, 300);
    await accountB.transfer(accountA, 100);
    await accountB.transfer(accountA, 700);
    clockWatch.stop();
    print('Elapsed time using await: ${clockWatch.elapsedMilliseconds} ms');

    final accountA2 = BankAccount('Account A', 1000);
    final accountB2 = BankAccount('Account B', 500);

    // Simulate multiple concurrent transfers
    final transfers = [
      accountA2.transferWithMutex(accountB2, 200),
      accountA2.transferWithMutex(accountB2, 300),
      accountB2.transferWithMutex(accountA2, 100),
      accountB2.transferWithMutex(accountA2, 700),
    ];

    final clockWatch2 = Stopwatch()..start();

    await Future.wait(transfers);
    clockWatch2.stop();
    print('Elapsed time using mutex: ${clockWatch2.elapsedMilliseconds} ms');
  });
}

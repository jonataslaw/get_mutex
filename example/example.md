```dart
void main(){
    final mutex = Mutex();
    final executionOrder = <int>[];
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

        if(executionOrder.toString() == [1, 2, 3, 4, 5, 6].toString()) {
            print('All good!');
        } else {
            throw Exception('Fail :('); // This will never happen
        }
      }
```

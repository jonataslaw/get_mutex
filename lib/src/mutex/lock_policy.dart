/// Lock policies to manage the order of lock acquisition:
/// - `LockPolicy.fair`: Grants locks in the order they were requested.
/// - `LockPolicy.readersFirst`: Prefers granting read locks over write locks.
/// - `LockPolicy.writersFirst`: Prefers granting write locks over read locks.
enum LockPolicy {
  readersFirst,
  writersFirst,
  fair, // Neutral
}

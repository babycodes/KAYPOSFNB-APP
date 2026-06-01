void main() {
  final lastSyncStr = '2026-06-01T19:37:00.000Z';
  final dt = DateTime.parse(lastSyncStr).toLocal();
  print(dt.toString()); // default toString() replaces T with space
  print(dt.toIso8601String().replaceFirst('T', ' '));
}

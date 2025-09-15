import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:flutter/widgets.dart';

class ServerSyncManager extends StatelessWidget {
  final dynamic retryStrategy;
  final Duration fetchInterval;
  final OnFetch onFetch;
  final OnSend onSend;
  final Widget child;

  const ServerSyncManager({
    super.key,
    required this.retryStrategy,
    required this.fetchInterval,
    required this.onFetch,
    required this.onSend,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Sync logic will be added later
    return child;
  }
}

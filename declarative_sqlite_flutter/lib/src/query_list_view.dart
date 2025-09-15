import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:declarative_sqlite_flutter/src/work_order.dart';
import 'package:flutter/material.dart';

class _MockWorkOrder implements IWorkOrder {
  @override
  final String id;
  @override
  final String customerId;
  double total = 0;

  _MockWorkOrder(this.id, this.customerId);

  @override
  Future<void> setTotal(double Function(IWorkOrder r) reducer) async {
    // Simulate async operation
    await Future.delayed(const Duration(milliseconds: 50));
    // In a real implementation, this would update the database
    // and the change would be reflected in the query result.
    // For this mock, we'll just update the local state.
    // Note: this mock implementation detail won't be used in the final code.
  }
}

class QueryListView<T> extends StatelessWidget {
  final void Function(QueryBuilder query) query;
  final Widget Function(BuildContext context) loadingBuilder;
  final Widget Function(BuildContext context, Object error) errorBuilder;
  final Widget Function(BuildContext context, T record) itemBuilder;

  const QueryListView({
    super.key,
    required this.query,
    required this.loadingBuilder,
    required this.errorBuilder,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // For now, returning a placeholder.
    // In the future, this will execute the query and build the list.
    if (T == IWorkOrder) {
      final items = [
        _MockWorkOrder('1', 'customer-1'),
        _MockWorkOrder('2', 'customer-2'),
      ];
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) =>
            itemBuilder(context, items[index] as T),
      );
    }
    return loadingBuilder(context);
  }
}

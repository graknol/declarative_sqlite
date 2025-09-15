abstract class IWorkOrder {
  String get id;
  String get customerId;

  Future<void> setTotal(double Function(IWorkOrder r) reducer);
}

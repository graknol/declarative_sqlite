/// OrderLine model representing individual items within an order
class OrderLine {
  final String id;
  final String orderId;
  final String itemCode;
  final String itemName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  const OrderLine({
    required this.id,
    required this.orderId,
    required this.itemCode,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  
  /// Create OrderLine from database map
  factory OrderLine.fromMap(Map<String, dynamic> map) {
    return OrderLine(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      itemCode: map['item_code'] as String,
      itemName: map['item_name'] as String,
      quantity: map['quantity'] as int,
      unitPrice: (map['unit_price'] as num).toDouble(),
      lineTotal: (map['line_total'] as num).toDouble(),
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
  
  /// Convert OrderLine to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_id': orderId,
      'item_code': itemCode,
      'item_name': itemName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'line_total': lineTotal,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
  
  /// Get status color for UI
  OrderLineStatusColor get statusColor {
    switch (status.toLowerCase()) {
      case 'pending':
        return OrderLineStatusColor.pending;
      case 'in_progress':
        return OrderLineStatusColor.inProgress;
      case 'completed':
        return OrderLineStatusColor.completed;
      case 'cancelled':
        return OrderLineStatusColor.cancelled;
      default:
        return OrderLineStatusColor.pending;
    }
  }
  
  /// Calculate line total (for validation)
  double get calculatedTotal => quantity * unitPrice;
  
  /// Check if calculated total matches stored total
  bool get isValidTotal => (calculatedTotal - lineTotal).abs() < 0.01;
  
  @override
  String toString() {
    return 'OrderLine{id: $id, itemCode: $itemCode, quantity: $quantity}';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OrderLine && other.id == id;
  }
  
  @override
  int get hashCode => id.hashCode;
}

/// Status color enumeration for order lines
enum OrderLineStatusColor {
  pending,
  inProgress,
  completed,
  cancelled,
}
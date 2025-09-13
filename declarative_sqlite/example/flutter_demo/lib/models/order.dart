/// Order model representing a work order in the shop floor system
class Order {
  final String id;
  final String orderNumber;
  final String customerName;
  final String status;
  final double totalAmount;
  final String priority;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? dueDate;
  final String? description;
  
  const Order({
    required this.id,
    required this.orderNumber,
    required this.customerName,
    required this.status,
    required this.totalAmount,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    this.dueDate,
    this.description,
  });
  
  /// Create Order from database map
  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['id'] as String,
      orderNumber: map['order_number'] as String,
      customerName: map['customer_name'] as String,
      status: map['status'] as String,
      totalAmount: (map['total_amount'] as num).toDouble(),
      priority: map['priority'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      dueDate: map['due_date'] != null ? DateTime.parse(map['due_date'] as String) : null,
      description: map['description'] as String?,
    );
  }
  
  /// Convert Order to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_number': orderNumber,
      'customer_name': customerName,
      'status': status,
      'total_amount': totalAmount,
      'priority': priority,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'description': description,
    };
  }
  
  /// Get status color for UI
  OrderStatusColor get statusColor {
    switch (status.toLowerCase()) {
      case 'pending':
        return OrderStatusColor.pending;
      case 'in_progress':
        return OrderStatusColor.inProgress;
      case 'completed':
        return OrderStatusColor.completed;
      case 'cancelled':
        return OrderStatusColor.cancelled;
      default:
        return OrderStatusColor.pending;
    }
  }
  
  /// Get priority color for UI
  OrderPriorityColor get priorityColor {
    switch (priority.toLowerCase()) {
      case 'high':
        return OrderPriorityColor.high;
      case 'medium':
        return OrderPriorityColor.medium;
      case 'low':
        return OrderPriorityColor.low;
      default:
        return OrderPriorityColor.medium;
    }
  }
  
  /// Check if order is overdue
  bool get isOverdue {
    if (dueDate == null) return false;
    return DateTime.now().isAfter(dueDate!) && status != 'completed';
  }
  
  @override
  String toString() {
    return 'Order{id: $id, orderNumber: $orderNumber, status: $status}';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Order && other.id == id;
  }
  
  @override
  int get hashCode => id.hashCode;
}

/// Status color enumeration for UI consistency
enum OrderStatusColor {
  pending,
  inProgress,
  completed,
  cancelled,
}

/// Priority color enumeration for UI consistency
enum OrderPriorityColor {
  high,
  medium,
  low,
}
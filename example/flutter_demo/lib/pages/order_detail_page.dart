import 'package:flutter/material.dart';
import '../models/database_service.dart';
import '../models/order.dart';
import '../models/order_line.dart';
import '../models/note.dart';
import '../widgets/order_line_card.dart';
import '../widgets/note_card.dart';
import '../widgets/add_note_dialog.dart';

/// Detailed view of an order showing order lines and notes
class OrderDetailPage extends StatefulWidget {
  final Order order;
  
  const OrderDetailPage({
    Key? key,
    required this.order,
  }) : super(key: key);
  
  @override
  _OrderDetailPageState createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> 
    with SingleTickerProviderStateMixin {
  final DatabaseService _dbService = DatabaseService.instance;
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadOrderDetails();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _loadOrderDetails() async {
    await Future.wait([
      _dbService.getOrderLines(widget.order.id),
      _dbService.getOrderNotes(widget.order.id),
    ]);
  }
  
  Future<void> _updateOrderStatus(String newStatus) async {
    await _dbService.updateOrderStatus(widget.order.id, newStatus);
    setState(() {}); // Refresh the UI
  }
  
  void _showAddNoteDialog() {
    showDialog(
      context: context,
      builder: (context) => AddNoteDialog(
        orderId: widget.order.id,
        onNoteAdded: () {
          // Note will be automatically reflected through the stream
        },
      ),
    );
  }
  
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
  
  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.order.orderNumber),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            onSelected: _updateOrderStatus,
            itemBuilder: (context) => [
              PopupMenuItem(value: 'pending', child: Text('Mark as Pending')),
              PopupMenuItem(value: 'in_progress', child: Text('Mark as In Progress')),
              PopupMenuItem(value: 'completed', child: Text('Mark as Completed')),
              PopupMenuItem(value: 'cancelled', child: Text('Mark as Cancelled')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Order summary header
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.order.customerName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(widget.order.status),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        widget.order.status.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.priority_high, size: 16),
                    SizedBox(width: 4),
                    Text(
                      widget.order.priority.toUpperCase(),
                      style: TextStyle(
                        color: _getPriorityColor(widget.order.priority),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Spacer(),
                    Icon(Icons.attach_money, size: 16),
                    Text(
                      '\$${widget.order.totalAmount.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (widget.order.dueDate != null) ...[
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 16,
                        color: widget.order.isOverdue ? Colors.red : null,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Due: ${widget.order.dueDate!.day}/${widget.order.dueDate!.month}/${widget.order.dueDate!.year}',
                        style: TextStyle(
                          color: widget.order.isOverdue ? Colors.red : null,
                          fontWeight: widget.order.isOverdue ? FontWeight.bold : null,
                        ),
                      ),
                      if (widget.order.isOverdue) ...[
                        SizedBox(width: 8),
                        Text(
                          'OVERDUE',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                if (widget.order.description != null) ...[
                  SizedBox(height: 8),
                  Text(
                    widget.order.description!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          
          // Tab bar
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: 'Order Lines'),
              Tab(text: 'Notes'),
            ],
          ),
          
          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOrderLinesTab(),
                _buildNotesTab(),
              ],
            ),
          ),
        ],
      ),
      
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton(
              onPressed: _showAddNoteDialog,
              tooltip: 'Add Note',
              child: Icon(Icons.add),
            )
          : null,
    );
  }
  
  Widget _buildOrderLinesTab() {
    return StreamBuilder<List<OrderLine>>(
      stream: _dbService.orderLineUpdates,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildOrderLinesLoader();
        }
        
        if (snapshot.hasError) {
          return _buildErrorState('Error loading order lines', snapshot.error.toString());
        }
        
        final orderLines = snapshot.data ?? [];
        
        if (orderLines.isEmpty) {
          return _buildEmptyOrderLines();
        }
        
        return RefreshIndicator(
          onRefresh: () => _dbService.getOrderLines(widget.order.id),
          child: ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: orderLines.length,
            itemBuilder: (context, index) {
              final orderLine = orderLines[index];
              return Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: OrderLineCard(orderLine: orderLine),
              );
            },
          ),
        );
      },
    );
  }
  
  Widget _buildNotesTab() {
    return StreamBuilder<List<Note>>(
      stream: _dbService.noteUpdates,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildNotesLoader();
        }
        
        if (snapshot.hasError) {
          return _buildErrorState('Error loading notes', snapshot.error.toString());
        }
        
        final notes = snapshot.data ?? [];
        
        if (notes.isEmpty) {
          return _buildEmptyNotes();
        }
        
        return RefreshIndicator(
          onRefresh: () => _dbService.getOrderNotes(widget.order.id),
          child: ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: NoteCard(note: note),
              );
            },
          ),
        );
      },
    );
  }
  
  Widget _buildOrderLinesLoader() {
    return FutureBuilder<List<OrderLine>>(
      future: _dbService.getOrderLines(widget.order.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading order lines...'),
              ],
            ),
          );
        }
        return SizedBox.shrink();
      },
    );
  }
  
  Widget _buildNotesLoader() {
    return FutureBuilder<List<Note>>(
      future: _dbService.getOrderNotes(widget.order.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading notes...'),
              ],
            ),
          );
        }
        return SizedBox.shrink();
      },
    );
  }
  
  Widget _buildErrorState(String title, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: 8),
          Text(
            error,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadOrderDetails,
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyOrderLines() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          SizedBox(height: 16),
          Text(
            'No order lines',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: 8),
          Text(
            'This order has no line items yet',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyNotes() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.note_add_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          SizedBox(height: 16),
          Text(
            'No notes yet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: 8),
          Text(
            'Add notes to track progress and collaborate',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showAddNoteDialog,
            icon: Icon(Icons.add),
            label: Text('Add First Note'),
          ),
        ],
      ),
    );
  }
}
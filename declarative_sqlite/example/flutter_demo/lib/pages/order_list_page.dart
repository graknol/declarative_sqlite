import 'package:flutter/material.dart';
import '../models/database_service.dart';
import '../models/order.dart';
import '../widgets/order_card.dart';
import '../widgets/order_filter_bar.dart';
import 'order_detail_page.dart';

/// Main page displaying list of orders with filtering and reactive updates
class OrderListPage extends StatefulWidget {
  @override
  _OrderListPageState createState() => _OrderListPageState();
}

class _OrderListPageState extends State<OrderListPage> {
  final DatabaseService _dbService = DatabaseService.instance;
  final TextEditingController _searchController = TextEditingController();
  
  String? _statusFilter;
  String? _priorityFilter;
  String _searchQuery = '';
  
  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  // No longer needed - streams update automatically!
  // Future<void> _refreshOrders() async { ... }
  
  void _onFilterChanged({String? status, String? priority}) {
    setState(() {
      _statusFilter = status;
      _priorityFilter = priority;
    });
    // No need to manually refresh - the stream will automatically update!
  }
  
  void _navigateToOrderDetail(Order order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OrderDetailPage(order: order),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Shop Floor Orders'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search orders...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.background,
              ),
            ),
          ),
          
          // Filter bar
          OrderFilterBar(
            statusFilter: _statusFilter,
            priorityFilter: _priorityFilter,
            onFilterChanged: _onFilterChanged,
          ),
          
          // Orders list with sophisticated dependency-based reactive updates
          Expanded(
            child: StreamBuilder<List<Order>>(
              stream: _dbService.watchOrders(
                statusFilter: _statusFilter,
                priorityFilter: _priorityFilter,
                searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildInitialLoader();
                }
                
                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }
                
                final orders = snapshot.data ?? [];
                
                if (orders.isEmpty) {
                  return _buildEmptyState();
                }
                
                return RefreshIndicator(
                  onRefresh: () async {
                    // Manual refresh is now optional - streams auto-update!
                    // This is here for user gesture only
                  },
                  child: ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: OrderCard(
                          order: order,
                          onTap: () => _navigateToOrderDetail(order),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      
      floatingActionButton: FloatingActionButton(
        onPressed: _refreshOrders,
        tooltip: 'Refresh Orders',
        child: Icon(Icons.refresh),
      ),
    );
  }
  
  Widget _buildInitialLoader() {
    return FutureBuilder<List<Order>>(
      future: _dbService.getOrders(
        statusFilter: _statusFilter,
        priorityFilter: _priorityFilter,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading orders...'),
              ],
            ),
          );
        }
        
        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error.toString());
        }
        
        // This should trigger the stream and won't be shown for long
        return SizedBox.shrink();
      },
    );
  }
  
  Widget _buildErrorState(String error) {
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
            'Error loading orders',
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
            onPressed: _refreshOrders,
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          SizedBox(height: 16),
          Text(
            'No orders found',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: 8),
          Text(
            'Try adjusting your filters or search query',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _statusFilter = null;
                _priorityFilter = null;
                _searchController.clear();
              });
              _refreshOrders();
            },
            child: Text('Clear Filters'),
          ),
        ],
      ),
    );
  }
}
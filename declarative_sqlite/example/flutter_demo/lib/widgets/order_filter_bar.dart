import 'package:flutter/material.dart';

/// Filter bar widget for filtering orders by status and priority
class OrderFilterBar extends StatelessWidget {
  final String? statusFilter;
  final String? priorityFilter;
  final Function({String? status, String? priority}) onFilterChanged;
  
  const OrderFilterBar({
    Key? key,
    this.statusFilter,
    this.priorityFilter,
    required this.onFilterChanged,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filters',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          
          // Filter chips row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Status filters
                Text('Status: ', style: Theme.of(context).textTheme.bodySmall),
                SizedBox(width: 8),
                
                _buildFilterChip(
                  context,
                  label: 'All',
                  isSelected: statusFilter == null,
                  onTap: () => onFilterChanged(status: null, priority: priorityFilter),
                ),
                
                _buildFilterChip(
                  context,
                  label: 'Pending',
                  isSelected: statusFilter == 'pending',
                  onTap: () => onFilterChanged(status: 'pending', priority: priorityFilter),
                  color: Colors.orange,
                ),
                
                _buildFilterChip(
                  context,
                  label: 'In Progress',
                  isSelected: statusFilter == 'in_progress',
                  onTap: () => onFilterChanged(status: 'in_progress', priority: priorityFilter),
                  color: Colors.blue,
                ),
                
                _buildFilterChip(
                  context,
                  label: 'Completed',
                  isSelected: statusFilter == 'completed',
                  onTap: () => onFilterChanged(status: 'completed', priority: priorityFilter),
                  color: Colors.green,
                ),
                
                SizedBox(width: 16),
                
                // Priority filters
                Text('Priority: ', style: Theme.of(context).textTheme.bodySmall),
                SizedBox(width: 8),
                
                _buildFilterChip(
                  context,
                  label: 'All',
                  isSelected: priorityFilter == null,
                  onTap: () => onFilterChanged(status: statusFilter, priority: null),
                ),
                
                _buildFilterChip(
                  context,
                  label: 'High',
                  isSelected: priorityFilter == 'high',
                  onTap: () => onFilterChanged(status: statusFilter, priority: 'high'),
                  color: Colors.red,
                ),
                
                _buildFilterChip(
                  context,
                  label: 'Medium',
                  isSelected: priorityFilter == 'medium',
                  onTap: () => onFilterChanged(status: statusFilter, priority: 'medium'),
                  color: Colors.orange,
                ),
                
                _buildFilterChip(
                  context,
                  label: 'Low',
                  isSelected: priorityFilter == 'low',
                  onTap: () => onFilterChanged(status: statusFilter, priority: 'low'),
                  color: Colors.green,
                ),
              ],
            ),
          ),
          
          // Active filters summary
          if (statusFilter != null || priorityFilter != null) ...[
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.filter_list, size: 16),
                SizedBox(width: 4),
                Text(
                  'Active filters: ${_getActiveFiltersText()}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
                Spacer(),
                TextButton(
                  onPressed: () => onFilterChanged(status: null, priority: null),
                  child: Text('Clear All'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size(0, 32),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildFilterChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        onSelected: (_) => onTap(),
        backgroundColor: color?.withOpacity(0.1),
        selectedColor: color?.withOpacity(0.3) ?? Theme.of(context).primaryColor.withOpacity(0.3),
        checkmarkColor: isSelected ? (color ?? Theme.of(context).primaryColor) : null,
        side: color != null 
            ? BorderSide(color: color.withOpacity(0.5))
            : null,
      ),
    );
  }
  
  String _getActiveFiltersText() {
    final filters = <String>[];
    
    if (statusFilter != null) {
      filters.add('Status: $statusFilter');
    }
    
    if (priorityFilter != null) {
      filters.add('Priority: $priorityFilter');
    }
    
    return filters.join(', ');
  }
}
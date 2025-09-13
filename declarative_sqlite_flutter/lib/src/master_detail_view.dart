import 'package:flutter/material.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'reactive_list_view.dart';

/// A widget that provides a master-detail view pattern for database-driven content.
/// 
/// This widget displays a list of master records and shows related detail records
/// when a master record is selected.
class MasterDetailView extends StatefulWidget {
  /// The data access instance for database operations
  final DataAccess dataAccess;
  
  /// Name of the master table
  final String masterTable;
  
  /// Name of the detail table
  final String detailTable;
  
  /// Name of the relationship between master and detail tables
  final String? relationship;
  
  /// Column name in detail table that references master table (if no relationship defined)
  final String? foreignKeyColumn;
  
  /// Column name in master table that is referenced (if no relationship defined)
  final String? primaryKeyColumn;
  
  /// Builder for master list items
  final Widget Function(BuildContext context, Map<String, dynamic> item) masterBuilder;
  
  /// Builder for detail list items
  final Widget Function(BuildContext context, Map<String, dynamic> item) detailBuilder;
  
  /// Optional WHERE clause for master records
  final String? masterWhere;
  
  /// Optional WHERE clause arguments for master records
  final List<dynamic>? masterWhereArgs;
  
  /// Optional ORDER BY clause for master records
  final String? masterOrderBy;
  
  /// Optional WHERE clause for detail records
  final String? detailWhere;
  
  /// Optional WHERE clause arguments for detail records
  final List<dynamic>? detailWhereArgs;
  
  /// Optional ORDER BY clause for detail records
  final String? detailOrderBy;
  
  /// Widget to display when no master record is selected
  final Widget? noSelectionWidget;
  
  /// Widget to display when no detail records exist for selected master
  final Widget? noDetailWidget;
  
  /// Title for the master section
  final String? masterTitle;
  
  /// Title for the detail section
  final String? detailTitle;
  
  /// Whether to show the master and detail in a split view (tablet) or separate pages (phone)
  final bool adaptiveLayout;
  
  /// Breakpoint width for adaptive layout
  final double layoutBreakpoint;

  const MasterDetailView({
    super.key,
    required this.dataAccess,
    required this.masterTable,
    required this.detailTable,
    required this.masterBuilder,
    required this.detailBuilder,
    this.relationship,
    this.foreignKeyColumn,
    this.primaryKeyColumn,
    this.masterWhere,
    this.masterWhereArgs,
    this.masterOrderBy,
    this.detailWhere,
    this.detailWhereArgs,
    this.detailOrderBy,
    this.noSelectionWidget,
    this.noDetailWidget,
    this.masterTitle,
    this.detailTitle,
    this.adaptiveLayout = true,
    this.layoutBreakpoint = 600,
  }) : assert(
         relationship != null || (foreignKeyColumn != null && primaryKeyColumn != null),
         'Either relationship or foreignKeyColumn+primaryKeyColumn must be provided',
       );

  @override
  State<MasterDetailView> createState() => _MasterDetailViewState();
}

class _MasterDetailViewState extends State<MasterDetailView> {
  Map<String, dynamic>? _selectedMaster;

  void _selectMaster(Map<String, dynamic> master) {
    setState(() {
      _selectedMaster = master;
    });
  }

  Future<List<Map<String, dynamic>>> _getDetailRecords() async {
    if (_selectedMaster == null) return [];

    if (widget.relationship != null) {
      // Use relationship-based query
      return await widget.dataAccess.getRelated(
        widget.masterTable,
        widget.detailTable,
        _selectedMaster![widget.primaryKeyColumn ?? 'id'],
        relationshipName: widget.relationship,
      );
    } else {
      // Use foreign key-based query
      final masterKey = _selectedMaster![widget.primaryKeyColumn ?? 'id'];
      final detailWhere = widget.detailWhere != null
          ? '${widget.foreignKeyColumn} = ? AND (${widget.detailWhere})'
          : '${widget.foreignKeyColumn} = ?';
      final detailWhereArgs = widget.detailWhere != null
          ? [masterKey, ...?widget.detailWhereArgs]
          : [masterKey];

      return await widget.dataAccess.getAllWhere(
        widget.detailTable,
        where: detailWhere,
        whereArgs: detailWhereArgs,
        orderBy: widget.detailOrderBy,
      );
    }
  }

  Widget _buildMasterView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.masterTitle != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              widget.masterTitle!,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        Expanded(
          child: ReactiveListView(
            dataAccess: widget.dataAccess,
            tableName: widget.masterTable,
            where: widget.masterWhere,
            whereArgs: widget.masterWhereArgs,
            orderBy: widget.masterOrderBy,
            itemBuilder: (context, item) {
              final isSelected = _selectedMaster != null &&
                  _selectedMaster![widget.primaryKeyColumn ?? 'id'] ==
                      item[widget.primaryKeyColumn ?? 'id'];

              return Card(
                elevation: isSelected ? 8 : 1,
                color: isSelected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: InkWell(
                  onTap: () => _selectMaster(item),
                  child: widget.masterBuilder(context, item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDetailView() {
    if (_selectedMaster == null) {
      return widget.noSelectionWidget ??
          const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.touch_app, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Select an item to view details',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.detailTitle != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              widget.detailTitle!,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _getDetailRecords(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(height: 8),
                      Text('Error: ${snapshot.error}'),
                    ],
                  ),
                );
              }

              final details = snapshot.data ?? [];

              if (details.isEmpty) {
                return widget.noDetailWidget ??
                    const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No details found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    );
              }

              return ListView.builder(
                itemCount: details.length,
                itemBuilder: (context, index) {
                  return widget.detailBuilder(context, details[index]);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSplitView = widget.adaptiveLayout && screenWidth >= widget.layoutBreakpoint;

    if (isSplitView) {
      // Split view for tablets/desktop
      return Row(
        children: [
          Expanded(
            flex: 1,
            child: _buildMasterView(),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 2,
            child: _buildDetailView(),
          ),
        ],
      );
    } else {
      // Single view for phones - show detail as a separate page
      if (_selectedMaster != null) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.detailTitle ?? 'Details'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  _selectedMaster = null;
                });
              },
            ),
          ),
          body: _buildDetailView(),
        );
      } else {
        return _buildMasterView();
      }
    }
  }
}

/// A simplified master-detail view for common use cases.
class SimpleMasterDetailView extends StatelessWidget {
  /// The data access instance
  final DataAccess dataAccess;
  
  /// Master table name
  final String masterTable;
  
  /// Detail table name  
  final String detailTable;
  
  /// Foreign key column in detail table
  final String foreignKeyColumn;
  
  /// Title function for master items
  final String Function(Map<String, dynamic> item) masterTitle;
  
  /// Subtitle function for master items (optional)
  final String Function(Map<String, dynamic> item)? masterSubtitle;
  
  /// Title function for detail items
  final String Function(Map<String, dynamic> item) detailTitle;
  
  /// Subtitle function for detail items (optional)
  final String Function(Map<String, dynamic> item)? detailSubtitle;
  
  /// Section titles
  final String? masterSectionTitle;
  final String? detailSectionTitle;

  const SimpleMasterDetailView({
    super.key,
    required this.dataAccess,
    required this.masterTable,
    required this.detailTable,
    required this.foreignKeyColumn,
    required this.masterTitle,
    required this.detailTitle,
    this.masterSubtitle,
    this.detailSubtitle,
    this.masterSectionTitle,
    this.detailSectionTitle,
  });

  @override
  Widget build(BuildContext context) {
    return MasterDetailView(
      dataAccess: dataAccess,
      masterTable: masterTable,
      detailTable: detailTable,
      foreignKeyColumn: foreignKeyColumn,
      primaryKeyColumn: 'id',
      masterTitle: masterSectionTitle,
      detailTitle: detailSectionTitle,
      masterBuilder: (context, item) {
        return ListTile(
          title: Text(masterTitle(item)),
          subtitle: masterSubtitle != null ? Text(masterSubtitle!(item)) : null,
          trailing: const Icon(Icons.arrow_forward_ios),
        );
      },
      detailBuilder: (context, item) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            title: Text(detailTitle(item)),
            subtitle: detailSubtitle != null ? Text(detailSubtitle!(item)) : null,
          ),
        );
      },
    );
  }
}
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';

/// Example showcasing the enhanced AutoForm family with reactive features
class EnhancedAutoFormExample extends StatefulWidget {
  const EnhancedAutoFormExample({super.key});

  @override
  State<EnhancedAutoFormExample> createState() => _EnhancedAutoFormExampleState();
}

class _EnhancedAutoFormExampleState extends State<EnhancedAutoFormExample> {
  late DataAccess dataAccess;

  @override
  void initState() {
    super.initState();
    _setupDatabase();
  }

  Future<void> _setupDatabase() async {
    // Initialize database with sample schema
    final schema = SchemaBuilder()
        .table('customers', (table) => table
            .autoIncrementPrimaryKey('id')
            .text('name', (col) => col.notNull())
            .text('email', (col) => col.unique())
            .text('phone')
            .text('customer_type') // 'standard', 'premium'
            .real('credit_limit'))
        .table('orders', (table) => table
            .autoIncrementPrimaryKey('id')
            .integer('customer_id', (col) => col.notNull().foreignKey('customers', 'id'))
            .text('product_name', (col) => col.notNull())
            .integer('quantity', (col) => col.defaultValue(1))
            .real('unit_price', (col) => col.notNull())
            .real('total_amount') // Computed field
            .text('status', (col) => col.defaultValue('PENDING'))
            .text('notes')
            .timestamp('created_at', (col) => col.defaultCurrentTimestamp()));

    // Setup in-memory database for demo
    final database = await openDatabase(':memory:');
    final migrator = SchemaMigrator();
    await migrator.migrate(database, schema);

    dataAccess = DataAccess(database: database, schema: schema);

    // Insert sample data
    await _insertSampleData();
    
    setState(() {});
  }

  Future<void> _insertSampleData() async {
    // Insert customers
    await dataAccess.insert('customers', {
      'name': 'John Doe',
      'email': 'john@example.com',
      'phone': '+1234567890',
      'customer_type': 'premium',
      'credit_limit': 5000.0,
    });

    await dataAccess.insert('customers', {
      'name': 'Jane Smith',
      'email': 'jane@example.com',
      'phone': '+0987654321',
      'customer_type': 'standard',
      'credit_limit': 2000.0,
    });

    // Insert orders
    await dataAccess.insert('orders', {
      'customer_id': 1,
      'product_name': 'Widget Pro',
      'quantity': 2,
      'unit_price': 99.99,
      'total_amount': 199.98,
      'status': 'SHIPPED',
    });
  }

  @override
  Widget build(BuildContext context) {
    return DataAccessProvider(
      dataAccess: dataAccess,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Enhanced AutoForm Examples'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildReactiveFormExample(),
            const SizedBox(height: 32),
            _buildBatchEditingExample(),
            const SizedBox(height: 32),
            _buildDialogExamples(),
          ],
        ),
      ),
    );
  }

  Widget _buildReactiveFormExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reactive Form with Live Preview & Computed Fields',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        ReactiveAutoForm(
          tableName: 'orders',
          title: 'Create New Order',
          livePreview: false, // Disabled for new records
          fields: [
            // Customer selection with related field display
            AutoFormField.text('customer_id', 
              label: 'Customer ID',
              required: true,
              validator: (value) {
                final id = int.tryParse(value?.toString() ?? '');
                if (id == null || id <= 0) return 'Please enter a valid customer ID';
                return null;
              },
            ),
            
            // Display customer name from related table
            AutoFormField.related('customer_id',
              label: 'Customer Name',
              relatedTable: 'customers',
              relatedValueColumn: 'id',
              relatedDisplayColumn: 'name',
            ),

            // Product details
            AutoFormField.text('product_name',
              label: 'Product',
              required: true,
              hint: 'Enter product name',
            ),

            // Quantity and price
            AutoFormField.text('quantity',
              label: 'Quantity',
              required: true,
              validator: (value) {
                final qty = int.tryParse(value?.toString() ?? '');
                if (qty == null || qty <= 0) return 'Quantity must be positive';
                return null;
              },
              triggersValidation: true, // Triggers total recalculation
            ),

            AutoFormField.text('unit_price',
              label: 'Unit Price',
              required: true,
              validator: (value) {
                final price = double.tryParse(value?.toString() ?? '');
                if (price == null || price <= 0) return 'Price must be positive';
                return null;
              },
              triggersValidation: true, // Triggers total recalculation
            ),

            // Computed total amount
            AutoFormField.computed('total_amount',
              label: 'Total Amount',
              computation: (formData) {
                final qty = int.tryParse(formData['quantity']?.toString() ?? '') ?? 0;
                final price = double.tryParse(formData['unit_price']?.toString() ?? '') ?? 0.0;
                return qty * price;
              },
              dependsOn: {'quantity', 'unit_price'},
            ),

            // Notes field with conditional visibility
            AutoFormField.text('notes',
              label: 'Special Notes',
              maxLines: 3,
              hint: 'Add notes for premium customers...',
              visibilityCondition: (formData) {
                // Only show notes for orders > $100
                final total = double.tryParse(formData['total_amount']?.toString() ?? '') ?? 0.0;
                return total > 100.0;
              },
            ),
          ],
          onSave: (data) async {
            await dataAccess.insert('orders', data);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Order created successfully!')),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBatchEditingExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Batch Editing',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 400,
          child: AutoFormBatch(
            tableName: 'orders',
            query: QueryBuilder()
                .selectAll()
                .from('orders')
                .where((cb) => cb.eq('status', 'PENDING')),
            fields: [
              AutoFormField.text('status', 
                label: 'Status',
                hint: 'PENDING, SHIPPED, DELIVERED',
              ),
              AutoFormField.text('notes',
                label: 'Notes',
                maxLines: 2,
              ),
            ],
            maxRecords: 10,
            onBatchSave: (records) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Updated ${records.length} orders')),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDialogExamples() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enhanced Form Dialogs',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            ElevatedButton(
              onPressed: () => _showCreateCustomerDialog(),
              child: const Text('Create Customer'),
            ),
            ElevatedButton(
              onPressed: () => _showEditOrderDialog(),
              child: const Text('Edit Order'),
            ),
            ElevatedButton(
              onPressed: () => _showBatchEditDialog(),
              child: const Text('Batch Edit Customers'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showCreateCustomerDialog() async {
    await ReactiveAutoFormDialog.showCreate(
      context: context,
      tableName: 'customers',
      title: 'New Customer',
      fields: [
        AutoFormField.text('name',
          required: true,
          validator: (value) => value?.toString().isEmpty == true ? 'Name is required' : null,
        ),
        AutoFormField.text('email',
          required: true,
          validator: (value) {
            if (value?.toString().isEmpty == true) return 'Email is required';
            if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.toString())) {
              return 'Please enter a valid email';
            }
            return null;
          },
        ),
        AutoFormField.text('phone', label: 'Phone Number'),
        AutoFormField.text('customer_type',
          label: 'Customer Type',
          hint: 'standard or premium',
        ),
        AutoFormField.text('credit_limit',
          label: 'Credit Limit',
          validator: (value) {
            if (value?.toString().isNotEmpty == true) {
              final limit = double.tryParse(value.toString());
              if (limit == null || limit < 0) return 'Credit limit must be a positive number';
            }
            return null;
          },
        ),
      ],
    );
  }

  Future<void> _showEditOrderDialog() async {
    await ReactiveAutoFormDialog.showEdit(
      context: context,
      tableName: 'orders',
      primaryKey: 1, // Edit the first order
      title: 'Edit Order',
      livePreview: true, // Enable live updates
      fields: [
        AutoFormField.text('product_name', label: 'Product'),
        AutoFormField.text('quantity', label: 'Quantity'),
        AutoFormField.text('unit_price', label: 'Unit Price'),
        AutoFormField.computed('total_amount',
          label: 'Total',
          computation: (formData) {
            final qty = int.tryParse(formData['quantity']?.toString() ?? '') ?? 0;
            final price = double.tryParse(formData['unit_price']?.toString() ?? '') ?? 0.0;
            return qty * price;
          },
        ),
        AutoFormField.text('status', label: 'Status'),
        AutoFormField.text('notes', label: 'Notes', maxLines: 3),
      ],
    );
  }

  Future<void> _showBatchEditDialog() async {
    await ReactiveAutoFormDialog.showBatch(
      context: context,
      tableName: 'customers',
      query: QueryBuilder()
          .selectAll()
          .from('customers')
          .where((cb) => cb.eq('customer_type', 'standard')),
      title: 'Upgrade Standard Customers',
      fields: [
        AutoFormField.text('customer_type', label: 'Customer Type'),
        AutoFormField.text('credit_limit', label: 'Credit Limit'),
      ],
    );
  }
}

void main() {
  runApp(MaterialApp(
    home: const EnhancedAutoFormExample(),
    title: 'Enhanced AutoForm Demo',
  ));
}
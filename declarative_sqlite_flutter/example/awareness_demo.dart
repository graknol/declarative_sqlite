import 'package:flutter/material.dart';
import '../lib/declarative_sqlite_flutter.dart';

/// Comprehensive demo of the Awareness Indicator functionality
/// Shows Microsoft Office-style awareness bubbles with various configurations
class AwarenessIndicatorDemo extends StatefulWidget {
  const AwarenessIndicatorDemo({Key? key}) : super(key: key);

  @override
  State<AwarenessIndicatorDemo> createState() => _AwarenessIndicatorDemoState();
}

class _AwarenessIndicatorDemoState extends State<AwarenessIndicatorDemo> {
  late AwarenessManager awarenessManager;
  
  // Mock data for demonstration
  final List<AwarenessUser> mockUsers = [
    const AwarenessUser(name: 'John Smith'),
    const AwarenessUser(name: 'Jane Doe'),
    const AwarenessUser(name: 'Michael Johnson'),
    const AwarenessUser(name: 'Sarah Wilson'),
    const AwarenessUser(name: 'David Brown'),
    const AwarenessUser(name: 'Emma Davis'),
  ];
  
  int currentUserCount = 0;

  @override
  void initState() {
    super.initState();
    
    // Initialize awareness manager with mock callback
    awarenessManager = AwarenessManager(
      onFetchAwareness: _mockFetchAwareness,
      pollingInterval: const Duration(seconds: 5),
      enableDebugLogging: true,
    );
  }

  @override
  void dispose() {
    awarenessManager.dispose();
    super.dispose();
  }

  /// Mock implementation of awareness fetching
  /// In a real app, this would call your server API
  Future<List<String>> _mockFetchAwareness(AwarenessContext context) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Return subset of users based on current count
    return mockUsers
        .take(currentUserCount)
        .map((user) => user.name)
        .toList();
  }

  void _updateUserCount(int count) {
    setState(() {
      currentUserCount = count;
    });
    // Trigger refresh to update awareness
    awarenessManager.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Awareness Indicators Demo'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildControlSection(),
            const SizedBox(height: 32),
            _buildBasicExamples(),
            const SizedBox(height: 32),
            _buildVariantExamples(),
            const SizedBox(height: 32),
            _buildIntegrationExamples(),
          ],
        ),
      ),
    );
  }

  Widget _buildControlSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Demo Controls',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text('Simulate users viewing this page: $currentUserCount'),
            Slider(
              value: currentUserCount.toDouble(),
              min: 0,
              max: mockUsers.length.toDouble(),
              divisions: mockUsers.length,
              label: '$currentUserCount users',
              onChanged: (value) => _updateUserCount(value.round()),
            ),
            const SizedBox(height: 8),
            Text(
              'Current users: ${mockUsers.take(currentUserCount).map((u) => u.name).join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicExamples() {
    final currentUsers = mockUsers.take(currentUserCount).toList();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Basic Awareness Indicators',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            
            // Standard indicator
            _buildExample(
              'Standard (32px)',
              AwarenessIndicator(users: currentUsers),
            ),
            
            // Compact indicator  
            _buildExample(
              'Compact (24px)',
              CompactAwarenessIndicator(users: currentUsers),
            ),
            
            // Large indicator
            _buildExample(
              'Large (48px)',
              AwarenessIndicator(
                users: currentUsers,
                size: 48.0,
                spacing: 24.0,
              ),
            ),
            
            // Badge style
            _buildExample(
              'Badge Style',
              AwarenessBadge(users: currentUsers),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantExamples() {
    final currentUsers = mockUsers.take(currentUserCount).toList();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Layout Variants',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            
            // Horizontal layout
            _buildExample(
              'Horizontal Layout',
              HorizontalAwarenessIndicator(users: currentUsers),
            ),
            
            // Horizontal with names
            _buildExample(
              'Horizontal with Names',
              HorizontalAwarenessIndicator(
                users: currentUsers,
                showNames: true,
              ),
            ),
            
            // Different max visible
            _buildExample(
              'Max 1 Visible',
              AwarenessIndicator(
                users: currentUsers,
                maxVisible: 1,
              ),
            ),
            
            _buildExample(
              'Max 4 Visible',
              AwarenessIndicator(
                users: currentUsers,
                maxVisible: 4,
                spacing: 12.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntegrationExamples() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Integration Examples',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            
            // In app bar
            _buildExample(
              'In App Bar',
              AppBar(
                title: const Text('Document.docx'),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: ReactiveAwarenessIndicator(
                      awarenessManager: awarenessManager,
                      context: const AwarenessContext(
                        tableName: 'documents',
                        recordId: 123,
                      ),
                      size: 28.0,
                    ),
                  ),
                ],
                backgroundColor: Colors.indigo[600],
                foregroundColor: Colors.white,
              ),
            ),
            
            // In list tiles
            _buildExample(
              'In List Tiles',
              Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.description),
                    title: const Text('Project Report.docx'),
                    subtitle: const Text('Last modified 2 hours ago'),
                    trailing: ReactiveAwarenessIndicator(
                      awarenessManager: awarenessManager,
                      context: const AwarenessContext(
                        tableName: 'documents',
                        recordId: 1,
                      ),
                      size: 24.0,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.spreadsheet_chart),
                    title: const Text('Q4 Budget.xlsx'),
                    subtitle: const Text('Last modified 1 hour ago'),
                    trailing: ReactiveAwarenessIndicator(
                      awarenessManager: awarenessManager,
                      context: const AwarenessContext(
                        tableName: 'documents',
                        recordId: 2,
                      ),
                      size: 24.0,
                    ),
                  ),
                ],
              ),
            ),
            
            // In cards
            _buildExample(
              'In Cards',
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Marketing Plan',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ReactiveAwarenessIndicator(
                            awarenessManager: awarenessManager,
                            context: const AwarenessContext(
                              tableName: 'projects',
                              recordId: 456,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('Collaborative planning document for Q1 2024 marketing initiatives.'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            'Updated 30 minutes ago',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExample(String title, Widget widget) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(4),
              ),
              child: widget,
            ),
          ),
        ],
      ),
    );
  }
}

/// Main app for running the demo
class AwarenessDemoApp extends StatelessWidget {
  const AwarenessDemoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Awareness Indicators Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const AwarenessIndicatorDemo(),
      debugShowCheckedModeBanner: false,
    );
  }
}

void main() {
  runApp(const AwarenessDemoApp());
}
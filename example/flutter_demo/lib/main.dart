import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'models/database_service.dart';
import 'pages/order_list_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize the global database service
  await DatabaseService.instance.initialize();
  
  runApp(ShopFloorDemoApp());
}

class ShopFloorDemoApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shop Floor Demo - Declarative SQLite',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: OrderListPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
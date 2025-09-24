import 'package:declarative_sqlite/declarative_sqlite.dart';

// Import all the DbRecord classes that need to be registered
import 'user.dart';
import 'post.dart';

part 'registration.reg.dart';

/// Registration class for all DbRecord factories in the demo app
@GenerateRegistration()
class DemoRegistration {
  // The registerAllFactories() method will be generated here
}
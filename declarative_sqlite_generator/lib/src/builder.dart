import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

Builder declarativeSqliteGenerator(BuilderOptions options) =>
    SharedPartBuilder([DeclarativeSqliteGenerator()], 'declarative_sqlite');

class DeclarativeSqliteGenerator extends Generator {
  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    // Generator logic will be added later
    return '// TODO: Implement generator';
  }
}

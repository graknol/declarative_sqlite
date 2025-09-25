import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

/// A builder that scans for `@GenerateDbRecord` annotations and outputs
/// metadata files.
class RegistrationScanner extends Builder {
  // Use fromUrl for a stable reference to the annotation.
  static const _annotationChecker = TypeChecker.fromUrl(
    'package:declarative_sqlite/src/annotations/generate_db_record.dart#GenerateDbRecord',
  );

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.dbrecord_meta']
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) {
      return;
    }

    final library = await buildStep.inputLibrary;
    final reader = LibraryReader(library);
    final annotated = reader.annotatedWith(_annotationChecker);

    if (annotated.isEmpty) {
      return;
    }

    final outputId = buildStep.inputId.changeExtension('.dbrecord_meta');
    final content = annotated
        .map((e) => e.element.name)
        .where((name) => name != null)
        .join('\n');

    if (content.isNotEmpty) {
      await buildStep.writeAsString(outputId, content);
    }
  }
}
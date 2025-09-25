import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/element/element.dart' as el;
import 'package:build/build.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:glob/glob.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';

/// A builder that generates a JSON cache of the database schema by finding
/// and executing a function annotated with `@DbSchema`.
class SchemaGeneratorBuilder implements Builder {
  static final _logger = Logger('SchemaGeneratorBuilder');
  static const _dbSchemaChecker = TypeChecker.fromUrl(
    'package:declarative_sqlite/src/annotations/db_schema.dart#DbSchema',
  );

  final BuilderOptions options;

  SchemaGeneratorBuilder(this.options);

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$package$': ['schema_cache.json'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    _logger.info('=== SchemaGeneratorBuilder.build START ===');

    if (buildStep.inputId.path != r'$package$') {
      _logger.info('Skipping non-package input: ${buildStep.inputId.path}');
      return;
    }

    try {
      _logger.info('Starting schema function search...');
      final schemaFunctionData = await _findSchemaFunction(buildStep);
      if (schemaFunctionData == null) {
        _logger.warning('No function annotated with @DbSchema found.');
        // Create an empty schema cache to avoid breaking downstream builders
        final cacheAssetId = AssetId(buildStep.inputId.package, 'schema_cache.json');
        await buildStep.writeAsString(cacheAssetId, jsonEncode(Schema(tables: [], views: []).toJson()));
        return;
      }

      final (schemaFunction, assetId) = schemaFunctionData;
      _logger.info('Found schema function: ${schemaFunction.name}');
      final schema = await _executeSchemaFunction(schemaFunction, assetId);

      final cacheAssetId = AssetId(buildStep.inputId.package, 'schema_cache.json');
      final jsonString = jsonEncode(schema.toJson());

      await buildStep.writeAsString(cacheAssetId, jsonString);
      _logger.info('Schema cache written with ${schema.tables.length} tables.');
    } catch (e, st) {
      _logger.severe('Error during schema generation: $e\n$st');
      rethrow;
    }
  }

  /// Finds the first top-level function annotated with `@DbSchema`.
  Future<(el.ExecutableElement, AssetId)?> _findSchemaFunction(BuildStep buildStep) async {
    final assets = buildStep.findAssets(Glob('**.dart'));
    await for (final assetId in assets) {
      if (!await buildStep.resolver.isLibrary(assetId)) continue;
      final library = await buildStep.resolver.libraryFor(assetId);
      _logger.fine('Scanning library: ${assetId.uri}');
      
      for (final element in library.children) {
        if (element is el.ExecutableElement) {
          final hasAnnotation = _dbSchemaChecker.hasAnnotationOfExact(element);
          
          if (hasAnnotation) {
            _logger.info('Found @DbSchema function: ${element.name} in ${assetId.uri}');
            return (element, assetId);
          }
        }
      }
    }
    return null;
  }

  /// Executes the schema function in a separate Dart process to build the schema.
  Future<Schema> _executeSchemaFunction(el.ExecutableElement function, AssetId assetId) async {
    final tempDir = await Directory.systemTemp.createTemp('schema_gen_');
    try {
      final scriptPath = p.join(tempDir.path, 'run_schema.dart');
      final packageUri = assetId.uri.toString();

      final packageConfigUri = await Isolate.packageConfig;
      if (packageConfigUri == null) {
        throw StateError('Could not find package config for the current isolate.');
      }
      final packageConfigFile = File.fromUri(packageConfigUri);

      final scriptContent = """
import 'dart:convert';
import 'dart:io';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import '$packageUri' as schema_lib;

void main() {
  try {
    final builder = SchemaBuilder();
    schema_lib.${function.name}(builder);
    final schema = builder.build();
    stdout.write(jsonEncode(schema.toJson()));
  } catch (e, stackTrace) {
    stderr.writeln('Error during schema execution: \$e');
    stderr.writeln('Stack trace: \$stackTrace');
    exit(1);
  }
}
""";
      await File(scriptPath).writeAsString(scriptContent);

      final result = await Process.run(
        Platform.executable,
        ['--packages=${packageConfigFile.path}', scriptPath],
        workingDirectory: Directory.current.path,
      );

      if (result.exitCode != 0) {
        throw Exception(
          'Failed to execute schema script. Exit code: ${result.exitCode}\\n'
          'Stderr: ${result.stderr}\\n'
          'Stdout: ${result.stdout}',
        );
      }

      final jsonMap = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      return Schema.fromJson(jsonMap);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }
}

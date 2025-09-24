import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:declarative_sqlite/declarative_sqlite.dart';
import 'package:source_gen/source_gen.dart';
import 'package:logging/logging.dart';

/// Generator that creates registration methods for classes annotated with @GenerateRegistration
class RegistrationGenerator extends GeneratorForAnnotation<GenerateRegistration> {
  static final _logger = Logger('RegistrationGenerator');

  @override
  FutureOr<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    _logger.info('=== RegistrationGenerator.generateForAnnotatedElement START ===');
    _logger.info('Processing element: ${element.name} (${element.runtimeType})');

    if (element is! ClassElement) {
      _logger.warning('Element is not a class: ${element.runtimeType}');
      throw InvalidGenerationSourceError(
        '@GenerateRegistration can only be applied to classes.',
        element: element,
      );
    }

    // Find all DbRecord classes in all libraries of the current package
    final packageName = buildStep.inputId.package;
    final dbRecordClasses = <String>[];
    
    _logger.info('Scanning all libraries in package "$packageName" for DbRecord classes...');
    
    // Get all libraries from the resolver
    final allLibraries = await buildStep.resolver.libraries.toList();
    _logger.info('Found ${allLibraries.length} total libraries');
    
    var packageLibraryCount = 0;
    for (final library in allLibraries) {
      // Only process libraries from the current package
      if (library.identifier.startsWith('package:$packageName/')) {
        packageLibraryCount++;
        _logger.info('Processing package library #$packageLibraryCount: ${library.identifier}');
        
        for (final topLevelElement in library.children) {
          if (topLevelElement is ClassElement) {
            _logger.fine('Checking class: ${topLevelElement.name} in ${library.identifier}');
            
            if (_extendsDbRecord(topLevelElement)) {
              _logger.info('Found DbRecord class: ${topLevelElement.name}');
              final name = topLevelElement.name;
              if (name != null) {
                dbRecordClasses.add(name);
              }
            }
          }
        }
      } else {
        _logger.finest('Skipping external library: ${library.identifier}');
      }
    }
    
    _logger.info('Processed $packageLibraryCount package libraries');

    _logger.info('Found ${dbRecordClasses.length} DbRecord classes: ${dbRecordClasses.join(', ')}');

    // Generate the registration method
    final buffer = StringBuffer();
    
    buffer.writeln('extension ${element.name}Generated on ${element.name} {');
    buffer.writeln('  /// Registers all factory methods for DbRecord classes');
    buffer.writeln('  static void registerAllFactories() {');
    
    if (dbRecordClasses.isNotEmpty) {
      for (final className in dbRecordClasses) {
        buffer.writeln('    RecordMapFactoryRegistry.register<$className>($className.fromMap);');
      }
    } else {
      buffer.writeln('    // No DbRecord classes found to register');
    }
    
    buffer.writeln('  }');
    buffer.writeln('}');

    final generatedCode = buffer.toString();
    _logger.info('Generated ${generatedCode.split('\n').length} lines of registration code');
    _logger.info('=== RegistrationGenerator.generateForAnnotatedElement END ===');
    
    return generatedCode;
  }

  /// Checks if the given class element extends DbRecord
  bool _extendsDbRecord(ClassElement element) {
    _logger.fine('Checking if ${element.name} extends DbRecord');
    
    ClassElement? current = element;
    int depth = 0;
    const maxDepth = 10; // Prevent infinite loops
    
    while (current != null && depth < maxDepth) {
      _logger.finest('  Checking class: ${current.name} at depth $depth');
      
      if (current.name == 'DbRecord') {
        _logger.fine('  ✓ ${element.name} extends DbRecord');
        return true;
      }
      
      final supertype = current.supertype;
      if (supertype != null) {
        current = supertype.element as ClassElement?;
        _logger.finest('  Supertype: ${current?.name}');
      } else {
        current = null;
        _logger.finest('  Supertype: null');
      }
      depth++;
    }
    
    _logger.fine('  ✗ ${element.name} does not extend DbRecord');
    return false;
  }


}
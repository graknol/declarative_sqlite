import 'dart:async';
import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:logging/logging.dart';

/// Scanner that finds DbRecord classes in individual files and outputs metadata
class RegistrationScanner implements Builder {
  static final _logger = Logger('RegistrationScanner');

  @override
  Map<String, List<String>> get buildExtensions => {
    '.dart': ['.dbrecord_meta'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    _logger.info('Scanning file: ${inputId.path}');
    
    final library = await buildStep.inputLibrary;
    final dbRecordClasses = <Map<String, String>>[];
    
    for (final topLevelElement in library.children) {
      if (topLevelElement is ClassElement) {
        _logger.fine('Checking class: ${topLevelElement.name}');
        
        if (_extendsDbRecord(topLevelElement)) {
          final name = topLevelElement.name;
          if (name != null) {
            _logger.info('Found DbRecord class: $name in ${inputId.path}');
            
            // Create metadata for this class
            dbRecordClasses.add({
              'className': name,
              'sourceFile': inputId.path,
              'importPath': inputId.path.replaceFirst('lib/', ''),
            });
          }
        }
      }
    }
    
    // Write metadata as JSON
    final metadata = {
      'sourceFile': inputId.path,
      'dbRecordClasses': dbRecordClasses,
    };
    
    final outputId = inputId.changeExtension('.dbrecord_meta');
    await buildStep.writeAsString(outputId, jsonEncode(metadata));
    
    if (dbRecordClasses.isNotEmpty) {
      _logger.info('Generated metadata for ${dbRecordClasses.length} DbRecord classes from ${inputId.path}');
    }
  }

  /// Checks if a class extends DbRecord
  bool _extendsDbRecord(ClassElement element) {
    _logger.fine('Checking inheritance for class: ${element.name}');
    
    ClassElement? current = element;
    while (current != null) {
      final supertype = current.supertype;
      if (supertype == null) break;
      
      final supertypeName = supertype.element.name;
      _logger.fine('  Checking supertype: $supertypeName');
      
      if (supertypeName == 'DbRecord') {
        _logger.fine('  Found DbRecord inheritance!');
        return true;
      }
      
      // Continue up the inheritance chain
      current = supertype.element as ClassElement?;
    }
    
    return false;
  }
}
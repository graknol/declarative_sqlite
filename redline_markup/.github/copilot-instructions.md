# GitHub Copilot Instructions for Redline Markup PDF Library

This Flutter library provides comprehensive PDF annotation capabilities with redline markup functionality.

## Project Overview

This is a Flutter library that combines:
- **PDF Viewer**: High-performance PDF rendering and display
- **Redline Markup Tools**: Annotation utilities including stamps, arrows, and text overlays
- **PDF Binary Editor**: Direct PDF manipulation for applying and removing markup edits
- **Annotation Detection**: Metadata-based system for tracking and managing applied annotations

## Architecture Guidelines

### Core Components

1. **PDF Viewer Widget**
   - Use Flutter's CustomPainter for efficient rendering
   - Implement zoom, pan, and scroll functionality
   - Support multi-page navigation
   - Optimize for performance with large documents

2. **Annotation Engine**
   - Modular annotation types (stamps, arrows, text, highlights)
   - Vector-based drawing system for scalable annotations
   - Undo/redo functionality
   - Layer management for annotation ordering

3. **PDF Binary Editor**
   - Direct PDF structure manipulation
   - Annotation embedding using PDF standards (e.g., /Annot objects)
   - Metadata preservation and enhancement
   - Cross-reference table management

4. **Metadata System**
   - Custom metadata fields for tracking applied annotations
   - Version control for annotation history
   - User attribution and timestamps
   - Annotation categorization and tagging

## Development Standards

### Code Organization
```
lib/
├── src/
│   ├── viewer/          # PDF viewing components
│   ├── annotations/     # Annotation tools and rendering
│   ├── editor/          # PDF binary manipulation
│   ├── metadata/        # Annotation tracking system
│   └── utils/           # Shared utilities
├── widgets/             # Public Flutter widgets
└── models/              # Data models and DTOs
```

### Naming Conventions
- Use descriptive names that indicate PDF/annotation context
- Prefix annotation-specific classes with `RedlineMark` or `Annotation`
- Use verb-noun patterns for methods (e.g., `applyStamp`, `removeAnnotation`)

### Performance Considerations
- Implement lazy loading for large PDF documents
- Use efficient rendering techniques (viewport culling, layer caching)
- Minimize memory footprint with proper resource disposal
- Optimize annotation rendering for real-time editing

### PDF Format Compliance
- Follow PDF 1.7 specification for annotation objects
- Use standard PDF annotation types where possible
- Implement proper coordinate system transformations
- Ensure compatibility with PDF viewers and editors

## Feature Implementation Guidelines

### Annotation Tools
When implementing annotation features:
- Create reusable annotation widgets
- Implement touch/gesture handling for mobile devices
- Support keyboard shortcuts for desktop
- Provide customizable styling options
- Include accessibility features (screen reader support)

### Binary PDF Editing
For PDF manipulation:
- Parse PDF structure safely with error handling
- Preserve existing document integrity
- Implement incremental updates when possible
- Support both in-memory and file-based operations
- Include validation for PDF compliance

### Metadata Management
For annotation tracking:
- Use PDF's Info dictionary for basic metadata
- Implement custom XMP metadata for complex tracking
- Store annotation relationships and dependencies
- Include creation/modification timestamps
- Support user-defined categorization

## Code Quality Standards

### Error Handling
- Use Result/Either patterns for operations that can fail
- Provide meaningful error messages with context
- Implement graceful degradation for unsupported features
- Log errors appropriately for debugging

### Testing Strategy
- Unit tests for all core PDF manipulation functions
- Widget tests for annotation UI components
- Integration tests for end-to-end workflows
- Performance tests for large document handling
- Mock PDF documents for consistent testing

### Documentation
- Comprehensive API documentation with examples
- Architecture decision records (ADRs) for major design choices
- User guides for common annotation workflows
- Technical documentation for PDF format handling

## Dependencies and Libraries

### Recommended Packages
- `pdf`: For PDF parsing and rendering
- `flutter/painting`: For custom drawing operations
- `path_provider`: For file system operations
- `shared_preferences`: For user settings persistence

### PDF Format Resources
- Adobe PDF Reference 1.7
- ISO 32000-1:2008 (PDF 1.7 standard)
- PDF annotation specification documents
- XMP metadata specification

## Security Considerations

### PDF Security
- Validate PDF structure before processing
- Handle encrypted PDFs appropriately
- Prevent malicious PDF exploitation
- Sanitize user input for text annotations

### Data Privacy
- Handle sensitive document content securely
- Implement proper access controls
- Consider local vs cloud storage implications
- Respect user privacy in metadata collection

## Performance Optimization

### Memory Management
- Implement proper dispose patterns
- Use weak references for large objects
- Cache rendered pages efficiently
- Clean up annotation resources promptly

### Rendering Optimization
- Use Flutter's RepaintBoundary for annotation layers
- Implement viewport-based rendering
- Optimize for different device capabilities
- Consider hardware acceleration opportunities

## Future Considerations

### Extensibility
- Design plugin architecture for custom annotation types
- Support for external annotation standards
- Integration with cloud storage services
- Collaboration features for multi-user editing

### Advanced Features
- OCR integration for text recognition
- Form field annotation support
- Digital signature compatibility
- Advanced search within annotations
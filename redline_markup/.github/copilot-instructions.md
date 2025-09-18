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
   - Direct PDF 2.0 structure manipulation
   - Annotation embedding using PDF 2.0 standards (enhanced /Annot objects)
   - Advanced metadata preservation and enhancement
   - Cross-reference table management with PDF 2.0 features

4. **Metadata System**
   - Custom metadata fields for tracking applied annotations
   - Version control for annotation history
   - User attribution and timestamps
   - Annotation categorization and tagging

## Font and Image Rendering with Flutter Canvas

### Overview
Rendering PDF fonts and images requires deep understanding of both PDF 2.0 specifications and Flutter's canvas capabilities. This section covers the technical implementation details for accurate font and image rendering.

### Font Rendering with Flutter Canvas

#### PDF 2.0 Font Types Support
- **Type 1 Fonts**: PostScript-based fonts with custom rendering
- **TrueType Fonts**: Standard TrueType font embedding and rendering
- **Type 3 Fonts**: User-defined fonts with custom glyph procedures
- **CIDFonts**: Composite fonts for complex scripts and Unicode support
- **Type 0 Fonts**: Composite font format for multi-byte character sets

#### Flutter Canvas Font Implementation
```dart
// Font rendering pipeline using Canvas primitives
class PDFTextRenderer {
  void renderText(Canvas canvas, String text, PDFFont font, Matrix4 transform) {
    // 1. Extract font metrics from PDF font dictionary
    // 2. Convert PDF font units to Flutter logical pixels
    // 3. Apply text transformation matrix
    // 4. Render using canvas.drawParagraph() or custom glyph drawing
  }
}
```

#### Key Implementation Strategies
- **Font Substitution**: Map PDF fonts to system fonts when original not available
- **Glyph Caching**: Cache rendered glyphs for performance optimization
- **Text Measurement**: Accurate width/height calculations for layout
- **Encoding Handling**: Support for various text encodings (UTF-8, UTF-16, custom)
- **Bidirectional Text**: Handle RTL and complex script rendering

#### Canvas Primitives for Text
- `Canvas.drawParagraph()`: For formatted text blocks
- `Canvas.drawRRect()`: For text selection backgrounds
- `Paint.shader`: For gradient text effects
- `Path.addPolygon()`: For custom glyph outlines
- `Canvas.clipPath()`: For text clipping and masking

### Image Rendering with Flutter Canvas

#### PDF 2.0 Image Types Support
- **JPEG Images**: Direct rendering with compression support
- **JPEG 2000**: Advanced compression format support
- **PNG Images**: Full PNG specification including transparency
- **JBIG2**: Monochrome image compression
- **Inline Images**: Small images embedded directly in content streams

#### Flutter Canvas Image Implementation
```dart
// Image rendering pipeline
class PDFImageRenderer {
  void renderImage(Canvas canvas, PDFImage image, Rect bounds) {
    // 1. Decode image data based on PDF filter type
    // 2. Apply color space transformations
    // 3. Handle image masks and transparency
    // 4. Scale and position using transformation matrix
    // 5. Render using canvas.drawImageRect()
  }
}
```

#### Advanced Image Features
- **Image Masks**: Soft and hard masking support
- **Color Spaces**: DeviceRGB, DeviceCMYK, CalRGB, Lab color spaces
- **Image Interpolation**: Smooth scaling for high-quality rendering
- **Transparency**: Alpha channel and blend mode support
- **Tiling Patterns**: Repetitive image patterns

#### Canvas Primitives for Images
- `Canvas.drawImage()`: Basic image rendering
- `Canvas.drawImageRect()`: Scaled and positioned image rendering
- `Paint.colorFilter`: Color space transformations
- `Paint.blendMode`: Advanced blending operations
- `Canvas.saveLayer()`: Layer-based compositing for transparency

### Low-Level Rendering Optimizations

#### Memory Management
- **Image Caching**: LRU cache for decoded images
- **Texture Compression**: GPU-optimized image formats
- **Streaming Decoding**: Process large images in chunks
- **Resource Pooling**: Reuse Paint and Path objects

#### Performance Techniques
- **Viewport Culling**: Only render visible elements
- **Level of Detail**: Use lower resolution for distant content
- **Batch Rendering**: Group similar operations for efficiency
- **Hardware Acceleration**: Leverage GPU when available

### Canvas Coordinate Systems

#### PDF to Flutter Transformation
```dart
// Transform PDF coordinates to Flutter canvas coordinates
Matrix4 pdfToFlutterTransform(PDFPage page, Size canvasSize) {
  // PDF origin is bottom-left, Flutter origin is top-left
  // Apply scaling, translation, and coordinate system flip
  return Matrix4.identity()
    ..scale(scale, -scale)  // Flip Y-axis
    ..translate(0, -page.height * scale);
}
```

#### Precision Considerations
- Use double precision for all coordinate calculations
- Handle sub-pixel positioning for crisp rendering
- Account for device pixel ratio differences
- Implement proper rounding for pixel alignment

## Development Standards

### Code Organization
```
lib/
├── src/
│   ├── viewer/          # PDF viewing components
│   ├── annotations/     # Annotation tools and rendering
│   ├── editor/          # PDF binary manipulation
│   ├── metadata/        # Annotation tracking system
│   ├── rendering/       # Font and image rendering engine
│   │   ├── fonts/       # Font parsing and rendering
│   │   ├── images/      # Image decoding and rendering
│   │   └── canvas/      # Canvas primitive utilities
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
- Follow PDF 2.0 specification (ISO32000-2) for all PDF operations
- **IMPORTANT**: Only support PDF 2.0 files - older PDF versions should be rejected
- Use standard PDF 2.0 annotation types and features
- Implement proper coordinate system transformations
- Leverage PDF 2.0 enhanced security and metadata features

### PDF Version Validation
```dart
// Example validation logic
class PDFVersionValidator {
  static bool isSupported(String pdfVersion) {
    // Only accept PDF 2.0 and newer
    return pdfVersion.startsWith('%PDF-2.');
  }
  
  static void validateOrThrow(PDFDocument doc) {
    if (!isSupported(doc.version)) {
      throw UnsupportedPDFVersionException(
        'Only PDF 2.0 files are supported. Found: ${doc.version}'
      );
    }
  }
}
```

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
- Parse PDF 2.0 structure safely with error handling
- **Version Validation**: Reject PDF files older than PDF 2.0
- Preserve existing document integrity
- Implement incremental updates when possible
- Support both in-memory and file-based operations
- Include validation for PDF 2.0 compliance

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
- **Font Rendering Tests**: Validate text accuracy across different font types
- **Image Rendering Tests**: Verify image quality and color accuracy
- **PDF Version Tests**: Ensure older PDF versions are properly rejected

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
- ISO 32000-2:2020 (PDF 2.0 standard)
- PDF 2.0 annotation specification documents
- XMP metadata specification for PDF 2.0
- Adobe PDF 2.0 implementation notes

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
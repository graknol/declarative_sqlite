/// Note model representing collaborative notes with offline-first GUID support
class Note {
  final String id; // GUID for offline-first creation
  final String orderId;
  final String content;
  final String author;
  final String noteType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final String? createdOnDevice;
  
  const Note({
    required this.id,
    required this.orderId,
    required this.content,
    required this.author,
    required this.noteType,
    required this.createdAt,
    required this.updatedAt,
    required this.isSynced,
    this.createdOnDevice,
  });
  
  /// Create Note from database map
  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      content: map['content'] as String,
      author: map['author'] as String,
      noteType: map['note_type'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      isSynced: (map['is_synced'] as int) == 1,
      createdOnDevice: map['created_on_device'] as String?,
    );
  }
  
  /// Convert Note to database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'order_id': orderId,
      'content': content,
      'author': author,
      'note_type': noteType,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
      'created_on_device': createdOnDevice,
    };
  }
  
  /// Get note type color for UI
  NoteTypeColor get typeColor {
    switch (noteType.toLowerCase()) {
      case 'priority':
        return NoteTypeColor.priority;
      case 'quality':
        return NoteTypeColor.quality;
      case 'issue':
        return NoteTypeColor.issue;
      case 'general':
        return NoteTypeColor.general;
      default:
        return NoteTypeColor.general;
    }
  }
  
  /// Get formatted time ago string
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    
    if (difference.inDays > 7) {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
  
  /// Create a copy with updated fields (for offline sync scenarios)
  Note copyWith({
    String? content,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return Note(
      id: id,
      orderId: orderId,
      content: content ?? this.content,
      author: author,
      noteType: noteType,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      createdOnDevice: createdOnDevice,
    );
  }
  
  @override
  String toString() {
    return 'Note{id: $id, author: $author, noteType: $noteType, isSynced: $isSynced}';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Note && other.id == id;
  }
  
  @override
  int get hashCode => id.hashCode;
}

/// Note type color enumeration for UI consistency
enum NoteTypeColor {
  priority,
  quality,
  issue,
  general,
}
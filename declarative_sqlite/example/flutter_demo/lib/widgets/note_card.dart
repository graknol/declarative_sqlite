import 'package:flutter/material.dart';
import '../models/note.dart';

/// Card widget displaying note information with offline-first indicators
class NoteCard extends StatelessWidget {
  final Note note;
  
  const NoteCard({
    Key? key,
    required this.note,
  }) : super(key: key);
  
  Color _getNoteTypeColor(String noteType) {
    switch (noteType.toLowerCase()) {
      case 'priority':
        return Colors.red;
      case 'quality':
        return Colors.blue;
      case 'issue':
        return Colors.orange;
      case 'general':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
  
  IconData _getNoteTypeIcon(String noteType) {
    switch (noteType.toLowerCase()) {
      case 'priority':
        return Icons.priority_high;
      case 'quality':
        return Icons.verified;
      case 'issue':
        return Icons.warning;
      case 'general':
        return Icons.note;
      default:
        return Icons.note;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final typeColor = _getNoteTypeColor(note.noteType);
    
    return Card(
      elevation: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: typeColor,
              width: 4,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with type, author, and sync status
              Row(
                children: [
                  // Note type indicator
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: typeColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getNoteTypeIcon(note.noteType),
                          size: 12,
                          color: typeColor,
                        ),
                        SizedBox(width: 4),
                        Text(
                          note.noteType.toUpperCase(),
                          style: TextStyle(
                            color: typeColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  Spacer(),
                  
                  // Sync status indicator
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: note.isSynced 
                          ? Colors.green.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: note.isSynced 
                            ? Colors.green.withOpacity(0.3)
                            : Colors.orange.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          note.isSynced ? Icons.cloud_done : Icons.cloud_upload,
                          size: 10,
                          color: note.isSynced ? Colors.green : Colors.orange,
                        ),
                        SizedBox(width: 2),
                        Text(
                          note.isSynced ? 'SYNCED' : 'PENDING',
                          style: TextStyle(
                            color: note.isSynced ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              SizedBox(height: 12),
              
              // Note content
              Text(
                note.content,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              
              SizedBox(height: 12),
              
              // Footer row with author and timestamp information
              Row(
                children: [
                  // Author
                  Icon(Icons.person, size: 14, color: Colors.grey),
                  SizedBox(width: 4),
                  Text(
                    note.author,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  
                  SizedBox(width: 16),
                  
                  // Device indicator
                  if (note.createdOnDevice != null) ...[
                    Icon(Icons.devices, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      note.createdOnDevice!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    SizedBox(width: 16),
                  ],
                  
                  Spacer(),
                  
                  // Time ago
                  Icon(Icons.access_time, size: 14, color: Colors.grey),
                  SizedBox(width: 4),
                  Text(
                    note.timeAgo,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              
              // Offline-first info for demonstration
              if (!note.isSynced) ...[
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This note was created offline and will sync when connection is available',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              // Updated timestamp if different from created
              if (note.updatedAt != note.createdAt) ...[
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.edit, size: 12, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      'Last updated: ${note.updatedAt.day}/${note.updatedAt.month}/${note.updatedAt.year} ${note.updatedAt.hour}:${note.updatedAt.minute.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
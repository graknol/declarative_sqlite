import 'package:flutter/material.dart';
import '../models/database_service.dart';

/// Dialog for adding new notes with offline-first GUID support
class AddNoteDialog extends StatefulWidget {
  final String orderId;
  final VoidCallback? onNoteAdded;
  
  const AddNoteDialog({
    Key? key,
    required this.orderId,
    this.onNoteAdded,
  }) : super(key: key);
  
  @override
  _AddNoteDialogState createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<AddNoteDialog> {
  final _contentController = TextEditingController();
  final _authorController = TextEditingController();
  String _selectedNoteType = 'general';
  bool _isSubmitting = false;
  
  final List<String> _noteTypes = ['general', 'priority', 'quality', 'issue'];
  
  @override
  void initState() {
    super.initState();
    // Pre-fill author with a default value (in a real app, this would come from user session)
    _authorController.text = 'Demo User';
  }
  
  @override
  void dispose() {
    _contentController.dispose();
    _authorController.dispose();
    super.dispose();
  }
  
  Future<void> _submitNote() async {
    if (_contentController.text.trim().isEmpty || _authorController.text.trim().isEmpty) {
      _showSnackBar('Please fill in all fields', isError: true);
      return;
    }
    
    setState(() {
      _isSubmitting = true;
    });
    
    try {
      await DatabaseService.instance.addNote(
        widget.orderId,
        _contentController.text.trim(),
        _authorController.text.trim(),
        noteType: _selectedNoteType,
      );
      
      _showSnackBar('Note added successfully!');
      
      if (widget.onNoteAdded != null) {
        widget.onNoteAdded!();
      }
      
      Navigator.of(context).pop();
      
    } catch (error) {
      _showSnackBar('Error adding note: $error', isError: true);
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }
  
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
  
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
    return AlertDialog(
      title: Text('Add Note'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Note type selection
            Text(
              'Note Type',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            
            Wrap(
              spacing: 8,
              children: _noteTypes.map((type) {
                final isSelected = type == _selectedNoteType;
                final color = _getNoteTypeColor(type);
                
                return FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getNoteTypeIcon(type),
                        size: 16,
                        color: isSelected ? color : null,
                      ),
                      SizedBox(width: 4),
                      Text(
                        type.toUpperCase(),
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedNoteType = type;
                      });
                    }
                  },
                  backgroundColor: color.withOpacity(0.1),
                  selectedColor: color.withOpacity(0.2),
                  side: BorderSide(color: color.withOpacity(0.3)),
                );
              }).toList(),
            ),
            
            SizedBox(height: 16),
            
            // Author field
            TextField(
              controller: _authorController,
              decoration: InputDecoration(
                labelText: 'Author',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Content field
            TextField(
              controller: _contentController,
              decoration: InputDecoration(
                labelText: 'Note Content',
                border: OutlineInputBorder(),
                hintText: 'Enter your note here...',
                prefixIcon: Icon(Icons.note_add),
              ),
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
            ),
            
            SizedBox(height: 16),
            
            // Offline-first info
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.offline_bolt,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Offline-First Creation',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'This note will be created with a GUID and can be synced later when connection is available.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitNote,
          child: _isSubmitting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Add Note'),
        ),
      ],
    );
  }
}
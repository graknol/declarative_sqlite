---
sidebar_position: 4
---

# Examples

Explore practical examples of using Declarative SQLite in real-world applications.

## Basic Blog App

A complete example showing how to build a simple blog application with users, posts, and comments.

### Schema Definition

```dart
// lib/database/schema.dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

final blogSchema = SchemaBuilder()
  // Users table
  .table('users', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('username', (col) => col.notNull().unique().maxLength(50))
    .text('email', (col) => col.notNull().unique().maxLength(255))
    .text('full_name', (col) => col.maxLength(100))
    .text('bio', (col) => col.maxLength(500))
    .boolean('is_active', (col) => col.notNull().defaultValue(true))
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .date('last_login'))
  
  // Posts table
  .table('posts', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('title', (col) => col.notNull().maxLength(200))
    .text('slug', (col) => col.notNull().maxLength(200))
    .text('content', (col) => col.notNull())
    .text('excerpt', (col) => col.maxLength(500))
    .integer('user_id', (col) => col.notNull())
    .boolean('published', (col) => col.notNull().defaultValue(false))
    .integer('view_count', (col) => col.notNull().defaultValue(0))
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .date('updated_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .date('published_at')
    .foreignKey('user_id').references('users', 'id'))
  
  // Comments table
  .table('comments', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('content', (col) => col.notNull().maxLength(1000))
    .integer('post_id', (col) => col.notNull())
    .integer('user_id', (col) => col.notNull())
    .boolean('approved', (col) => col.notNull().defaultValue(false))
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .foreignKey('post_id').references('posts', 'id')
    .foreignKey('user_id').references('users', 'id'))
  
  // Indices for performance
  .index('posts', ['user_id', 'published'])
  .index('posts', ['published_at'])
  .index('posts', ['slug'])
  .index('comments', ['post_id', 'approved'])
  .uniqueIndex('users', ['email'])
  .uniqueIndex('posts', ['slug'])
  
  // Views for common queries
  .view('published_posts', (view) => view
    .select('p.*')
    .select('u.username', 'author')
    .select('u.full_name', 'author_name')
    .from('posts', 'p')
    .innerJoin('users', 'u', 'p.user_id = u.id')
    .where('p.published = 1'));
```

### Repository Layer

```dart
// lib/repositories/blog_repository.dart
import 'package:declarative_sqlite/declarative_sqlite.dart';

class BlogRepository {
  final DeclarativeDatabase database;
  
  BlogRepository(this.database);
  
  // User operations
  Future<int> createUser({
    required String username,
    required String email,
    String? fullName,
    String? bio,
  }) async {
    return await database.insert('users', {
      'username': username,
      'email': email,
      'full_name': fullName,
      'bio': bio,
      'created_at': DateTime.now(),
    });
  }
  
  Future<Map<String, dynamic>?> getUserByUsername(String username) async {
    return await database.queryFirst(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );
  }
  
  Stream<List<Map<String, dynamic>>> getActiveUsersStream() {
    return database
      .from('users')
      .where('is_active', equals: true)
      .orderBy('created_at', descending: true)
      .stream();
  }
  
  // Post operations
  Future<int> createPost({
    required String title,
    required String content,
    required int userId,
    String? excerpt,
    bool published = false,
  }) async {
    final slug = _generateSlug(title);
    
    return await database.insert('posts', {
      'title': title,
      'slug': slug,
      'content': content,
      'excerpt': excerpt,
      'user_id': userId,
      'published': published,
      'created_at': DateTime.now(),
      'updated_at': DateTime.now(),
      'published_at': published ? DateTime.now() : null,
    });
  }
  
  Future<void> publishPost(int postId) async {
    await database.update(
      'posts',
      {
        'published': true,
        'published_at': DateTime.now(),
        'updated_at': DateTime.now(),
      },
      where: 'id = ?',
      whereArgs: [postId],
    );
  }
  
  Stream<List<Map<String, dynamic>>> getPublishedPostsStream() {
    return database
      .fromView('published_posts')
      .orderBy('created_at', descending: true)
      .stream();
  }
  
  Stream<List<Map<String, dynamic>>> getUserPostsStream(int userId) {
    return database
      .from('posts')
      .where('user_id', equals: userId)
      .orderBy('created_at', descending: true)
      .stream();
  }
  
  Future<void> incrementViewCount(int postId) async {
    await database.rawUpdate('''
      UPDATE posts 
      SET view_count = view_count + 1,
          updated_at = ?
      WHERE id = ?
    ''', [DateTime.now().toIso8601String(), postId]);
  }
  
  // Comment operations
  Future<int> addComment({
    required String content,
    required int postId,
    required int userId,
  }) async {
    return await database.insert('comments', {
      'content': content,
      'post_id': postId,
      'user_id': userId,
      'created_at': DateTime.now(),
    });
  }
  
  Future<void> approveComment(int commentId) async {
    await database.update(
      'comments',
      {'approved': true},
      where: 'id = ?',
      whereArgs: [commentId],
    );
  }
  
  Stream<List<Map<String, dynamic>>> getPostCommentsStream(int postId) {
    return database
      .rawStreamQuery('''
        SELECT 
          c.*,
          u.username,
          u.full_name
        FROM comments c
        JOIN users u ON c.user_id = u.id
        WHERE c.post_id = ? AND c.approved = 1
        ORDER BY c.created_at ASC
      ''', [postId])
      .stream();
  }
  
  // Utility methods
  String _generateSlug(String title) {
    return title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .trim();
  }
  
  // Analytics
  Future<Map<String, dynamic>> getBlogStats() async {
    final result = await database.rawQuery('''
      SELECT 
        (SELECT COUNT(*) FROM users WHERE is_active = 1) as active_users,
        (SELECT COUNT(*) FROM posts WHERE published = 1) as published_posts,
        (SELECT COUNT(*) FROM comments WHERE approved = 1) as approved_comments,
        (SELECT SUM(view_count) FROM posts WHERE published = 1) as total_views
    ''');
    
    return result.first;
  }
}
```

### Flutter UI Components

```dart
// lib/widgets/post_list.dart
import 'package:flutter/material.dart';
import 'package:declarative_sqlite_flutter/declarative_sqlite_flutter.dart';
import '../repositories/blog_repository.dart';

class PostList extends StatelessWidget {
  final BlogRepository repository;
  final int? userId; // If provided, show only user's posts
  
  const PostList({
    Key? key,
    required this.repository,
    this.userId,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final stream = userId != null
      ? repository.getUserPostsStream(userId!)
      : repository.getPublishedPostsStream();
    
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }
        
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
        
        final posts = snapshot.data!;
        
        if (posts.isEmpty) {
          return const Center(
            child: Text('No posts found'),
          );
        }
        
        return ListView.builder(
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final post = posts[index];
            return PostCard(
              post: post,
              repository: repository,
            );
          },
        );
      },
    );
  }
}

class PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final BlogRepository repository;
  
  const PostCard({
    Key? key,
    required this.post,
    required this.repository,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: InkWell(
        onTap: () {
          // Increment view count and navigate to post detail
          repository.incrementViewCount(post['id']);
          Navigator.pushNamed(
            context,
            '/post',
            arguments: post['id'],
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                post['title'] ?? '',
                style: Theme.of(context).textTheme.headlineSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              
              // Excerpt or content preview
              if (post['excerpt'] != null)
                Text(
                  post['excerpt'],
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              
              const SizedBox(height: 12),
              
              // Meta information
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    post['author'] ?? 'Unknown',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(post['created_at']),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Icon(Icons.visibility, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${post['view_count'] ?? 0}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }
}
```

### Post Detail Screen

```dart
// lib/screens/post_detail_screen.dart
import 'package:flutter/material.dart';
import '../repositories/blog_repository.dart';
import '../widgets/comment_section.dart';

class PostDetailScreen extends StatefulWidget {
  final int postId;
  final BlogRepository repository;
  
  const PostDetailScreen({
    Key? key,
    required this.postId,
    required this.repository,
  }) : super(key: key);
  
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Map<String, dynamic>? post;
  bool loading = true;
  
  @override
  void initState() {
    super.initState();
    _loadPost();
  }
  
  Future<void> _loadPost() async {
    try {
      final postData = await widget.repository.database.queryFirst(
        'published_posts',
        where: 'id = ?',
        whereArgs: [widget.postId],
      );
      
      setState(() {
        post = postData;
        loading = false;
      });
    } catch (e) {
      setState(() {
        loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading post: $e')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (post == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Post Not Found')),
        body: const Center(
          child: Text('The requested post could not be found.'),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text(post!['title'] ?? ''),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Post title
            Text(
              post!['title'] ?? '',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            
            // Post meta
            Row(
              children: [
                Text(
                  'By ${post!['author_name'] ?? post!['author'] ?? 'Unknown'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  _formatDate(post!['created_at']),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Icon(Icons.visibility, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '${post!['view_count'] ?? 0} views',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            
            const Divider(height: 32),
            
            // Post content
            Text(
              post!['content'] ?? '',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            
            const SizedBox(height: 32),
            
            // Comments section
            CommentSection(
              postId: widget.postId,
              repository: widget.repository,
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }
}
```

### Comment Section Widget

```dart
// lib/widgets/comment_section.dart
import 'package:flutter/material.dart';

class CommentSection extends StatefulWidget {
  final int postId;
  final BlogRepository repository;
  
  const CommentSection({
    Key? key,
    required this.postId,
    required this.repository,
  }) : super(key: key);
  
  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
  
  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comments',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        
        // Comment input
        _buildCommentInput(),
        
        const SizedBox(height: 24),
        
        // Comments list
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: widget.repository.getPostCommentsStream(widget.postId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Error loading comments: ${snapshot.error}');
            }
            
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            
            final comments = snapshot.data!;
            
            if (comments.isEmpty) {
              return const Text('No comments yet. Be the first to comment!');
            }
            
            return Column(
              children: comments.map((comment) => _buildCommentCard(comment)).toList(),
            );
          },
        ),
      ],
    );
  }
  
  Widget _buildCommentInput() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Write a comment...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitComment,
                  child: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Post Comment'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCommentCard(Map<String, dynamic> comment) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  comment['full_name'] ?? comment['username'] ?? 'Anonymous',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  _formatDate(comment['created_at']),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(comment['content'] ?? ''),
          ],
        ),
      ),
    );
  }
  
  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty) return;
    
    setState(() {
      _isSubmitting = true;
    });
    
    try {
      // In a real app, you'd get the current user ID from authentication
      const currentUserId = 1; // Placeholder
      
      await widget.repository.addComment(
        content: _commentController.text.trim(),
        postId: widget.postId,
        userId: currentUserId,
      );
      
      _commentController.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment posted successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error posting comment: $e')),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }
  
  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }
}
```

## Task Management App

A simpler example showing task management with categories and priorities.

### Schema

```dart
final taskSchema = SchemaBuilder()
  .table('categories', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('name', (col) => col.notNull().unique())
    .text('color', (col) => col.notNull().defaultValue('#007AFF'))
    .integer('sort_order', (col) => col.notNull().defaultValue(0)))
    
  .table('tasks', (table) => table
    .autoIncrementPrimaryKey('id')
    .text('title', (col) => col.notNull())
    .text('description')
    .integer('category_id')
    .integer('priority', (col) => col.notNull().defaultValue(0)) // 0=Low, 1=Medium, 2=High
    .boolean('completed', (col) => col.notNull().defaultValue(false))
    .date('due_date')
    .date('created_at', (col) => col.notNull().defaultValue(DateTime.now()))
    .date('completed_at')
    .foreignKey('category_id').references('categories', 'id'))
    
  .index('tasks', ['completed', 'due_date'])
  .index('tasks', ['category_id'])
  
  .view('task_overview', (view) => view
    .select('t.*')
    .select('c.name', 'category_name')
    .select('c.color', 'category_color')
    .from('tasks', 't')
    .leftJoin('categories', 'c', 't.category_id = c.id'));
```

### Task List Widget

```dart
class TaskList extends StatelessWidget {
  final DeclarativeDatabase database;
  final bool showCompleted;
  
  const TaskList({
    Key? key,
    required this.database,
    this.showCompleted = false,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: database
        .fromView('task_overview')
        .where('completed', equals: showCompleted)
        .orderBy('priority', descending: true)
        .orderBy('due_date', ascending: true)
        .stream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }
        
        final tasks = snapshot.data!;
        
        return ListView.builder(
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return TaskTile(
              task: task,
              database: database,
            );
          },
        );
      },
    );
  }
}

class TaskTile extends StatelessWidget {
  final Map<String, dynamic> task;
  final DeclarativeDatabase database;
  
  const TaskTile({
    Key? key,
    required this.task,
    required this.database,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final isCompleted = task['completed'] == 1;
    final priority = task['priority'] ?? 0;
    
    return Card(
      child: ListTile(
        leading: Checkbox(
          value: isCompleted,
          onChanged: (value) => _toggleCompleted(),
        ),
        title: Text(
          task['title'] ?? '',
          style: TextStyle(
            decoration: isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task['description'] != null)
              Text(task['description']),
            Row(
              children: [
                if (task['category_name'] != null)
                  Chip(
                    label: Text(task['category_name']),
                    backgroundColor: Color(int.parse(
                      task['category_color'].replaceFirst('#', '0xFF'),
                    )),
                  ),
                const SizedBox(width: 8),
                _buildPriorityIcon(priority),
              ],
            ),
          ],
        ),
        trailing: task['due_date'] != null
          ? Text(_formatDueDate(task['due_date']))
          : null,
      ),
    );
  }
  
  Widget _buildPriorityIcon(int priority) {
    switch (priority) {
      case 2:
        return const Icon(Icons.priority_high, color: Colors.red);
      case 1:
        return const Icon(Icons.low_priority, color: Colors.orange);
      default:
        return const Icon(Icons.low_priority, color: Colors.green);
    }
  }
  
  String _formatDueDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = date.difference(now).inDays;
      
      if (difference == 0) return 'Today';
      if (difference == 1) return 'Tomorrow';
      if (difference == -1) return 'Yesterday';
      if (difference > 1) return 'In $difference days';
      return '${-difference} days ago';
    } catch (e) {
      return '';
    }
  }
  
  Future<void> _toggleCompleted() async {
    final newCompleted = task['completed'] != 1;
    
    await database.update(
      'tasks',
      {
        'completed': newCompleted,
        'completed_at': newCompleted ? DateTime.now().toIso8601String() : null,
      },
      where: 'id = ?',
      whereArgs: [task['id']],
    );
  }
}
```

## Key Takeaways

These examples demonstrate:

1. **Schema Design** - How to structure related tables with proper relationships
2. **Repository Pattern** - Organizing database operations in a clean, testable way
3. **Streaming UI** - Building reactive interfaces that update automatically
4. **Error Handling** - Proper exception handling and user feedback
5. **Performance** - Using indices and views for efficient queries
6. **Real-world Patterns** - Common app patterns like lists, detail views, and forms

## Next Steps

- Explore the [complete example apps](https://github.com/graknol/declarative_sqlite/tree/main/examples) in the repository
- Learn about [Performance Optimization](../advanced/performance) techniques
- See [Testing Strategies](../advanced/testing) for your applications
- Check out [Deployment](../advanced/deployment) for production apps
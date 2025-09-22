/// The Ultimate Developer Experience Demo
/// 
/// This example demonstrates the absolute pinnacle of what's possible
/// with the enhanced code generation system.

import 'package:declarative_sqlite/declarative_sqlite.dart';

part 'ultimate_example.g.dart'; // Where all the magic happens

// ============================================================================
// STEP 1: Define your schema (this could even be generated from existing DB!)
// ============================================================================

Schema createAppSchema() {
  return SchemaBuilder()
    ..table('users', (table) {
      table.integer('id').notNull();
      table.text('name').notNull();
      table.text('email');
      table.integer('age');
      table.date('created_at').notNull();
      table.date('updated_at').lww();
      table.key(['id']).primary();
    })
    ..table('posts', (table) {
      table.integer('id').notNull();
      table.integer('user_id').notNull();
      table.text('title').notNull();
      table.text('content');
      table.date('published_at');
      table.boolean('is_published').notNull(false);
      table.key(['id']).primary();
    })
    ..table('comments', (table) {
      table.integer('id').notNull();
      table.integer('post_id').notNull();
      table.integer('user_id').notNull();
      table.text('comment').notNull();
      table.date('created_at').notNull();
      table.key(['id']).primary();
    })
    ..build();
}

// ============================================================================
// STEP 2: Write minimal record classes (just the essentials!)
// ============================================================================

@GenerateDbRecord('users')
@RegisterFactory()
class User extends DbRecord with UserFromMapMixin {
  User(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'users', database);
  
  // That's it! Everything else is generated:
  // - All getters: id, name, email, age, createdAt, updatedAt
  // - All setters: name=, email=, age=, updatedAt=
  // - fromMap method via mixin
  // - Factory registration
}

@GenerateDbRecord('posts')
@RegisterFactory()  
class Post extends DbRecord with PostFromMapMixin {
  Post(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'posts', database);
  
  // Generated: id, userId, title, content, publishedAt, isPublished
  // Generated: title=, content=, publishedAt=, isPublished=
  // Generated: fromMap, registration
}

@GenerateDbRecord('comments')
@RegisterFactory()
class Comment extends DbRecord with CommentFromMapMixin {
  Comment(Map<String, Object?> data, DeclarativeDatabase database)
      : super(data, 'comments', database);
  
  // Generated: id, postId, userId, comment, createdAt
  // Generated: comment=, (id, postId, userId, createdAt are immutable)
  // Generated: fromMap, registration
}

// ============================================================================
// STEP 3: One-line application setup
// ============================================================================

class BlogApp {
  late DeclarativeDatabase database;
  
  Future<void> initialize() async {
    // Open database
    database = await DeclarativeDatabase.open('blog.db', schema: createAppSchema());
    
    // Register ALL factories with one call
    registerAllFactories(database);
    
    print('✅ Database initialized with automatic factory registration!');
  }
  
  // ============================================================================
  // STEP 4: Enjoy the incredible developer experience
  // ============================================================================
  
  Future<void> demonstrateUsage() async {
    // Create a user with type-safe properties
    final userData = {
      'id': 1,
      'name': 'Alice Johnson',
      'email': 'alice@example.com',
      'age': 28,
      'created_at': DateTime.now().toIso8601String(),
    };
    
    final user = UserFromMapMixin.fromMap(userData, database);
    
    // Type-safe property access (all generated!)
    print('User: ${user.name} (${user.age}) - ${user.email}');
    
    // Type-safe property updates (all generated!)
    user.email = 'alice.johnson@newjob.com';
    user.age = 29;
    
    await user.save();
    
    // Create a post
    final postData = {
      'id': 1,
      'user_id': user.id,
      'title': 'My First Blog Post',
      'content': 'This is amazing! Look how little code I had to write.',
      'published_at': DateTime.now().toIso8601String(),
      'is_published': true,
    };
    
    final post = PostFromMapMixin.fromMap(postData, database);
    
    // All properties are typed and safe
    print('Post: "${post.title}" by User ${post.userId}');
    print('Published: ${post.isPublished}');
    
    await post.save();
    
    // Add a comment
    final commentData = {
      'id': 1,
      'post_id': post.id,
      'user_id': user.id,
      'comment': 'Great post! Code generation is the future.',
      'created_at': DateTime.now().toIso8601String(),
    };
    
    final comment = CommentFromMapMixin.fromMap(commentData, database);
    await comment.save();
    
    // ========================================================================
    // Query with zero boilerplate (no mappers needed!)
    // ========================================================================
    
    // Get all users (automatically typed!)
    final users = await database.queryTyped<User>((q) => q.from('users'));
    print('Found ${users.length} users');
    
    // Get posts by user (automatically typed!)
    final userPosts = await database.queryTyped<Post>(
      (q) => q.from('posts').where('user_id = ?', [user.id])
    );
    print('User has ${userPosts.length} posts');
    
    // Get comments on post (automatically typed!)
    final postComments = await database.queryTyped<Comment>(
      (q) => q.from('comments').where('post_id = ?', [post.id])
    );
    print('Post has ${postComments.length} comments');
    
    // Complex joins work too (still zero mappers!)
    final postsWithUsers = await database.query((q) => 
      q.from('posts')
       .join('users', 'posts.user_id = users.id')
       .select(['posts.*', 'users.name as author_name'])
    );
    
    for (final row in postsWithUsers) {
      print('Post: ${row['title']} by ${row['author_name']}');
    }
    
    // ========================================================================
    // Individual factory registration for granular control
    // ========================================================================
    
    // Clear all and register selectively
    RecordMapFactoryRegistry.clear();
    
    registerUserFactory(database);   // Only users
    registerPostFactory(database);   // Add posts
    // Comments deliberately not registered
    
    print('Selective registration complete');
    
    // ========================================================================
    // Backwards compatibility with manual registration
    // ========================================================================
    
    // Old manual approach still works
    RecordMapFactoryRegistry.register<Comment>((data) => 
      CommentFromMapMixin.fromMap(data, database)
    );
    
    final manualComment = RecordMapFactoryRegistry.create<Comment>(commentData);
    print('Manual registration works: ${manualComment.comment}');
  }
}

// ============================================================================
// Main function - See how clean everything is!
// ============================================================================

void main() async {
  final app = BlogApp();
  
  await app.initialize();
  await app.demonstrateUsage();
  
  print('🚀 Ultimate developer experience achieved!');
  print('   📝 Minimal code written');
  print('   🔧 Maximum functionality generated');
  print('   ⚡ Zero boilerplate queries');
  print('   🎯 Full type safety');
  print('   🔄 Automatic factory registration');
}

/* 
============================================================================
WHAT THE GENERATOR PRODUCES (all automatic):
============================================================================

// For each @GenerateDbRecord class, we get:

extension UserGenerated on User {
  // Typed getters for all columns
  int get id => getIntegerNotNull('id');
  String get name => getTextNotNull('name');
  String? get email => getText('email');
  int? get age => getInteger('age');
  DateTime get createdAt => getDateTimeNotNull('created_at');
  DateTime? get updatedAt => getDateTime('updated_at');
  
  // Typed setters (excluding primary keys and immutable fields)
  set name(String value) => setText('name', value);
  set email(String? value) => setText('email', value);
  set age(int? value) => setInteger('age', value);
  set updatedAt(DateTime? value) => setDateTime('updated_at', value);
}

extension UserFactory on User {
  static User createFromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return User(data, database);
  }
  
  static User Function(Map<String, Object?>) getFactory(DeclarativeDatabase database) {
    return (data) => createFromMap(data, database);
  }
}

mixin UserFromMapMixin {
  static User fromMap(Map<String, Object?> data, DeclarativeDatabase database) {
    return UserFactory.createFromMap(data, database);
  }
}

// Registration functions
void registerAllFactories(DeclarativeDatabase database) {
  registerGeneratedFactories(database);
}

void registerGeneratedFactories(DeclarativeDatabase database) {
  RecordMapFactoryRegistry.register<User>(UserFactory.getFactory(database));
  RecordMapFactoryRegistry.register<Post>(PostFactory.getFactory(database));
  RecordMapFactoryRegistry.register<Comment>(CommentFactory.getFactory(database));
}

void registerUserFactory(DeclarativeDatabase database) {
  RecordMapFactoryRegistry.register<User>(UserFactory.getFactory(database));
}

void registerPostFactory(DeclarativeDatabase database) {
  RecordMapFactoryRegistry.register<Post>(PostFactory.getFactory(database));
}

void registerCommentFactory(DeclarativeDatabase database) {
  RecordMapFactoryRegistry.register<Comment>(CommentFactory.getFactory(database));
}

*/
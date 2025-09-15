import 'dart:async';
import 'dart:math';

/// Information about a user currently viewing a record/page
class AwarenessUser {
  const AwarenessUser({
    required this.name,
    this.userId,
    this.initials,
    this.color,
  });

  final String name;
  final String? userId;
  final String? initials;
  final int? color;

  /// Generate initials from name if not provided
  String get displayInitials {
    if (initials != null) return initials!;
    
    final words = name.trim().split(' ');
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      return words[0].isNotEmpty ? words[0][0].toUpperCase() : '?';
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  /// Generate a vibrant color based on the name
  int get displayColor {
    if (color != null) return color!;
    
    // Generate vibrant color from name hash
    final hash = name.hashCode;
    final hue = (hash % 360).abs().toDouble();
    
    // Use high saturation and brightness for vibrant colors
    return _hsvToColor(hue, 0.7, 0.9);
  }

  /// Convert HSV to RGB color value
  static int _hsvToColor(double h, double s, double v) {
    final c = v * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = v - c;
    
    double r = 0, g = 0, b = 0;
    
    if (h >= 0 && h < 60) {
      r = c; g = x; b = 0;
    } else if (h >= 60 && h < 120) {
      r = x; g = c; b = 0;
    } else if (h >= 120 && h < 180) {
      r = 0; g = c; b = x;
    } else if (h >= 180 && h < 240) {
      r = 0; g = x; b = c;
    } else if (h >= 240 && h < 300) {
      r = x; g = 0; b = c;
    } else if (h >= 300 && h < 360) {
      r = c; g = 0; b = x;
    }
    
    final red = ((r + m) * 255).round();
    final green = ((g + m) * 255).round();
    final blue = ((b + m) * 255).round();
    
    return (255 << 24) | (red << 16) | (green << 8) | blue;
  }
}

/// Context information for awareness tracking
class AwarenessContext {
  const AwarenessContext({
    this.tableName,
    this.recordId,
    this.route,
    this.additionalContext,
  });

  final String? tableName;
  final dynamic recordId;
  final String? route;
  final Map<String, dynamic>? additionalContext;

  /// Create a unique key for this context
  String get contextKey {
    final parts = <String>[];
    if (tableName != null) parts.add('table:$tableName');
    if (recordId != null) parts.add('record:$recordId');
    if (route != null) parts.add('route:$route');
    return parts.isEmpty ? 'global' : parts.join('|');
  }
}

/// Callback type for fetching awareness data from the server
typedef AwarenessCallback = Future<List<String>> Function(AwarenessContext context);

/// Manages real-time awareness tracking showing who's currently viewing records/pages
/// Similar to Microsoft Office's awareness indicators
class AwarenessManager {
  AwarenessManager({
    required this.onFetchAwareness,
    this.pollingInterval = const Duration(seconds: 30),
    this.offlineRetryInterval = const Duration(minutes: 1),
    this.enableDebugLogging = false,
  });

  final AwarenessCallback onFetchAwareness;
  final Duration pollingInterval;
  final Duration offlineRetryInterval;
  final bool enableDebugLogging;

  // Track awareness data by context
  final Map<String, List<AwarenessUser>> _awarenessData = {};
  
  // Stream controllers for awareness changes
  final Map<String, StreamController<List<AwarenessUser>>> _controllers = {};
  
  // Timer for periodic updates
  Timer? _pollingTimer;
  
  // Track active contexts to poll
  final Set<String> _activeContexts = {};
  
  // Network status tracking
  bool _isOnline = true;
  Timer? _offlineRetryTimer;

  /// Start tracking awareness for a specific context
  void startTracking(AwarenessContext context) {
    final key = context.contextKey;
    _activeContexts.add(key);
    
    if (_controllers[key] == null) {
      _controllers[key] = StreamController<List<AwarenessUser>>.broadcast();
    }
    
    // Start polling if not already running
    _startPolling();
    
    // Immediately fetch for this context
    _fetchAwarenessForContext(context);
    
    _log('Started tracking awareness for: $key');
  }

  /// Stop tracking awareness for a specific context
  void stopTracking(AwarenessContext context) {
    final key = context.contextKey;
    _activeContexts.remove(key);
    
    // If no more active contexts, stop polling
    if (_activeContexts.isEmpty) {
      _stopPolling();
    }
    
    _log('Stopped tracking awareness for: $key');
  }

  /// Get current awareness users for a context
  List<AwarenessUser> getAwarenessUsers(AwarenessContext context) {
    final key = context.contextKey;
    return _awarenessData[key] ?? [];
  }

  /// Get a stream of awareness changes for a context
  Stream<List<AwarenessUser>> getAwarenessStream(AwarenessContext context) {
    final key = context.contextKey;
    
    if (_controllers[key] == null) {
      _controllers[key] = StreamController<List<AwarenessUser>>.broadcast();
    }
    
    return _controllers[key]!.stream;
  }

  /// Manually trigger awareness update for all active contexts
  Future<void> refresh() async {
    for (final contextKey in _activeContexts) {
      final context = _parseContextKey(contextKey);
      if (context != null) {
        await _fetchAwarenessForContext(context);
      }
    }
  }

  /// Start the polling timer
  void _startPolling() {
    if (_pollingTimer != null && _pollingTimer!.isActive) return;
    
    _pollingTimer = Timer.periodic(pollingInterval, (timer) {
      _pollAllActiveContexts();
    });
    
    _log('Started polling with interval: $pollingInterval');
  }

  /// Stop the polling timer
  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _log('Stopped polling');
  }

  /// Poll all active contexts for awareness updates
  Future<void> _pollAllActiveContexts() async {
    if (!_isOnline) {
      _log('Skipping poll - offline');
      return;
    }

    for (final contextKey in List.from(_activeContexts)) {
      final context = _parseContextKey(contextKey);
      if (context != null) {
        await _fetchAwarenessForContext(context);
      }
    }
  }

  /// Fetch awareness data for a specific context
  Future<void> _fetchAwarenessForContext(AwarenessContext context) async {
    try {
      final userNames = await onFetchAwareness(context);
      final users = userNames.map((name) => AwarenessUser(name: name)).toList();
      
      final key = context.contextKey;
      _awarenessData[key] = users;
      
      // Notify listeners
      final controller = _controllers[key];
      if (controller != null && !controller.isClosed) {
        controller.add(users);
      }
      
      // Update online status if we got a response
      if (!_isOnline) {
        _setOnlineStatus(true);
      }
      
      _log('Fetched awareness for $key: ${users.length} users');
      
    } catch (e) {
      _log('Error fetching awareness for ${context.contextKey}: $e');
      
      // Handle offline/error state
      _setOnlineStatus(false);
    }
  }

  /// Update online/offline status and handle retry logic
  void _setOnlineStatus(bool isOnline) {
    if (_isOnline == isOnline) return;
    
    _isOnline = isOnline;
    _log('Network status changed to: ${isOnline ? 'online' : 'offline'}');
    
    if (isOnline) {
      // Back online - cancel retry timer and resume normal polling
      _offlineRetryTimer?.cancel();
      _offlineRetryTimer = null;
      _startPolling();
    } else {
      // Gone offline - start retry timer
      _stopPolling();
      _startOfflineRetryTimer();
    }
  }

  /// Start timer for offline retry attempts
  void _startOfflineRetryTimer() {
    _offlineRetryTimer?.cancel();
    
    _offlineRetryTimer = Timer.periodic(offlineRetryInterval, (timer) {
      _log('Attempting to reconnect...');
      _pollAllActiveContexts();
    });
  }

  /// Parse context key back to AwarenessContext
  AwarenessContext? _parseContextKey(String key) {
    if (key == 'global') {
      return const AwarenessContext();
    }
    
    final parts = key.split('|');
    String? tableName;
    dynamic recordId;
    String? route;
    
    for (final part in parts) {
      if (part.startsWith('table:')) {
        tableName = part.substring(6);
      } else if (part.startsWith('record:')) {
        recordId = part.substring(7);
      } else if (part.startsWith('route:')) {
        route = part.substring(6);
      }
    }
    
    return AwarenessContext(
      tableName: tableName,
      recordId: recordId,
      route: route,
    );
  }

  /// Log debug messages if enabled
  void _log(String message) {
    if (enableDebugLogging) {
      print('[AwarenessManager] $message');
    }
  }

  /// Clean up resources
  void dispose() {
    _stopPolling();
    _offlineRetryTimer?.cancel();
    
    for (final controller in _controllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _controllers.clear();
    _awarenessData.clear();
    _activeContexts.clear();
    
    _log('Disposed');
  }
}
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// A Hybrid Logical Clock (HLC) timestamp.
///
/// HLCs combine physical time (wall-clock) with a logical counter to create
/// a partially ordered, sortable, and conflict-free timestamp across
/// distributed nodes.
///
/// The format is: `<milliseconds>:<counter>:<nodeId>`
/// - `milliseconds`: Milliseconds since the Unix epoch, left-padded with zeros.
/// - `counter`: A logical counter, left-padded with zeros, to resolve ties
///   when events occur in the same millisecond.
/// - `nodeId`: A unique identifier for the node that generated the timestamp.
///
/// The padding ensures that HLC timestamps can be lexically sorted.
class Hlc extends Equatable implements Comparable<Hlc> {
  final int milliseconds;
  final int counter;
  final String nodeId;

  @override
  List<Object?> get props =>
      [milliseconds.hashCode, counter.hashCode, nodeId.hashCode];

  @override
  bool? get stringify => false;

  static Hlc min = const Hlc(0, 0, '0');

  const Hlc(this.milliseconds, this.counter, this.nodeId);

  /// Creates an HLC timestamp from a string representation.
  factory Hlc.parse(String encoded) {
    final parts = encoded.split(':');
    if (parts.length != 3) {
      throw FormatException('Invalid HLC string format', encoded);
    }
    return Hlc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      parts[2],
    );
  }

  @override
  String toString() {
    // Pad to ensure lexical sortability.
    // Milliseconds: 15 digits (supports dates far into the future)
    // Counter: 5 digits (allows for 100,000 events per millisecond)
    return '${milliseconds.toString().padLeft(15, '0')}:'
        '${counter.toString().padLeft(5, '0')}:'
        '$nodeId';
  }

  @override
  int compareTo(Hlc other) {
    if (milliseconds != other.milliseconds) {
      return milliseconds.compareTo(other.milliseconds);
    }
    if (counter != other.counter) {
      return counter.compareTo(other.counter);
    }
    return nodeId.compareTo(other.nodeId);
  }
}

/// A clock that generates Hybrid Logical Clock timestamps.
/// 
/// This is a singleton to ensure causal ordering is preserved throughout
/// the entire application. All database instances should use the same
/// HLC clock instance.
class HlcClock {
  static HlcClock? _instance;
  
  int _lastMilliseconds;
  int _lastCounter;
  final String nodeId;

  HlcClock._internal({String? nodeId})
      : _lastMilliseconds = DateTime.now().millisecondsSinceEpoch,
        _lastCounter = 0,
        nodeId = nodeId ?? const Uuid().v4();

  /// Gets the singleton instance of the HLC clock.
  /// 
  /// If [nodeId] is provided on first access, it will be used as the node ID.
  /// Subsequent calls with different node IDs will be ignored.
  factory HlcClock({String? nodeId}) {
    return _instance ??= HlcClock._internal(nodeId: nodeId);
  }

  /// Gets the singleton instance without creating it.
  /// Throws if the instance hasn't been created yet.
  static HlcClock get instance {
    if (_instance == null) {
      throw StateError('HlcClock instance not initialized. Call HlcClock() first.');
    }
    return _instance!;
  }

  /// Resets the singleton instance. Used primarily for testing.
  static void resetInstance() {
    _instance = null;
  }

  /// Generates a new HLC timestamp.
  Hlc now() {
    final wallClock = DateTime.now().millisecondsSinceEpoch;

    if (wallClock > _lastMilliseconds) {
      _lastMilliseconds = wallClock;
      _lastCounter = 0;
    } else {
      _lastCounter++;
    }

    return Hlc(_lastMilliseconds, _lastCounter, nodeId);
  }

  /// Updates the clock based on a received HLC timestamp from another node.
  /// This is crucial for keeping clocks synchronized in a distributed system.
  void update(Hlc received) {
    final wallClock = DateTime.now().millisecondsSinceEpoch;

    if (wallClock > _lastMilliseconds && wallClock > received.milliseconds) {
      // Case 1: Local and received time are both in the past.
      // The physical clock is authoritative.
      _lastMilliseconds = wallClock;
      _lastCounter = 0;
    } else if (_lastMilliseconds == received.milliseconds) {
      // Case 2: Same millisecond, update to the higher counter.
      _lastCounter =
          (received.counter > _lastCounter ? received.counter : _lastCounter) +
              1;
    } else if (_lastMilliseconds > received.milliseconds) {
      // Case 3: Local clock is ahead. Increment counter.
      _lastCounter++;
    } else {
      // Case 4: Received clock is ahead. Adopt its time.
      _lastMilliseconds = received.milliseconds;
      _lastCounter = received.counter + 1;
    }
  }
}

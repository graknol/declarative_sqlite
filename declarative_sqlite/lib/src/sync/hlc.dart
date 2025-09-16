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
class Hlc implements Comparable<Hlc> {
  final int milliseconds;
  final int counter;
  final String nodeId;

  Hlc(this.milliseconds, this.counter, this.nodeId);

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hlc &&
          runtimeType == other.runtimeType &&
          milliseconds == other.milliseconds &&
          counter == other.counter &&
          nodeId == other.nodeId;

  @override
  int get hashCode =>
      milliseconds.hashCode ^ counter.hashCode ^ nodeId.hashCode;
}

/// A clock that generates Hybrid Logical Clock timestamps.
class HlcClock {
  int _lastMilliseconds;
  int _lastCounter;
  final String nodeId;

  HlcClock({String? nodeId})
      : _lastMilliseconds = DateTime.now().millisecondsSinceEpoch,
        _lastCounter = 0,
        nodeId = nodeId ?? const Uuid().v4();

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

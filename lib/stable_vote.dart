import 'dart:collection';

/// One frame's top detection (or nothing, when no bill was seen).
class VoteObservation {
  const VoteObservation(this.label, this.confidence);

  final String label;
  final double confidence;
}

/// The label that won the vote.
class VoteResult {
  const VoteResult({
    required this.label,
    required this.confidence,
    required this.votes,
  });

  final String label;

  /// Average confidence of the frames that voted for [label].
  final double confidence;

  /// How many frames in the window voted for [label].
  final int votes;
}

/// Smooths per-frame detections so the screen does not flicker between
/// denominations. A label is only confirmed when it wins at least
/// [votesNeeded] of the last [windowSize] frames.
class StableVote {
  StableVote({this.windowSize = 8, this.votesNeeded = 5})
      : assert(votesNeeded <= windowSize);

  final int windowSize;
  final int votesNeeded;

  final Queue<VoteObservation?> _window = Queue<VoteObservation?>();

  /// Adds one frame (pass null when no bill was detected in it).
  VoteResult? add(VoteObservation? observation) {
    _window.addLast(observation);
    while (_window.length > windowSize) {
      _window.removeFirst();
    }
    return current;
  }

  /// The confirmed result right now, or null if nothing is stable yet.
  VoteResult? get current {
    final counts = <String, int>{};
    final sums = <String, double>{};
    for (final obs in _window) {
      if (obs == null) continue;
      counts[obs.label] = (counts[obs.label] ?? 0) + 1;
      sums[obs.label] = (sums[obs.label] ?? 0) + obs.confidence;
    }

    String? bestLabel;
    var bestCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        bestLabel = entry.key;
        bestCount = entry.value;
      }
    }

    final label = bestLabel;
    if (label == null || bestCount < votesNeeded) return null;
    return VoteResult(
      label: label,
      confidence: (sums[label] ?? 0) / bestCount,
      votes: bestCount,
    );
  }

  void reset() => _window.clear();
}

// Unit tests for the frame-voting logic and the bill table.
// (The file is called widget_test.dart so that `flutter create` does not add
// its own template test, which would not match this app.)
import 'package:bill_scanner/bill_info.dart';
import 'package:bill_scanner/stable_vote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  VoteObservation obs(String label, [double conf = 0.9]) =>
      VoteObservation(label, conf);

  group('StableVote', () {
    test('shows nothing until enough frames agree', () {
      final vote = StableVote(windowSize: 8, votesNeeded: 5);
      for (var i = 0; i < 4; i++) {
        expect(vote.add(obs('php_500')), isNull);
      }
      final result = vote.add(obs('php_500'));
      expect(result?.label, 'php_500');
      expect(result?.votes, 5);
    });

    test('averages the confidence of the winning frames', () {
      final vote = StableVote(windowSize: 8, votesNeeded: 5);
      VoteResult? result;
      for (final c in [0.6, 0.7, 0.8, 0.9, 1.0]) {
        result = vote.add(obs('usd_20', c));
      }
      expect(result?.confidence, closeTo(0.8, 1e-9));
    });

    test('a few wrong frames do not change the answer', () {
      final vote = StableVote(windowSize: 8, votesNeeded: 5);
      VoteResult? result;
      for (final label in [
        'eur_10', 'eur_10', 'eur_20', 'eur_10',
        'eur_20', 'eur_10', 'eur_20', 'eur_10',
      ]) {
        result = vote.add(obs(label));
      }
      expect(result?.label, 'eur_10');
    });

    test('result disappears once the bill leaves the frame', () {
      final vote = StableVote(windowSize: 8, votesNeeded: 5);
      for (var i = 0; i < 8; i++) {
        vote.add(obs('php_1000'));
      }
      expect(vote.current?.label, 'php_1000');
      for (var i = 0; i < 8; i++) {
        vote.add(null);
      }
      expect(vote.current, isNull);
    });

    test('reset clears everything', () {
      final vote = StableVote(windowSize: 8, votesNeeded: 5);
      for (var i = 0; i < 8; i++) {
        vote.add(obs('usd_5'));
      }
      vote.reset();
      expect(vote.current, isNull);
    });
  });

  group('kBills', () {
    test('all nine supported bills have a display entry', () {
      const keys = [
        'php_100', 'php_500', 'php_1000',
        'usd_1', 'usd_5', 'usd_20',
        'eur_5', 'eur_10', 'eur_20',
      ];
      for (final key in keys) {
        expect(kBills.containsKey(key), isTrue, reason: key);
      }
    });

    test('unknown labels fall back to the raw text', () {
      final info = billInfoFor('gbp_10');
      expect(info.name, 'gbp_10');
      expect(info.symbol, 'gbp_10');
    });
  });
}

import 'package:omnitrain/data/models/models.dart';

class FuzzySearch {
  static List<Exercise> filterAndRank(String query, List<Exercise> exercises) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return exercises;

    final scored = <(Exercise, int)>[];

    for (final exercise in exercises) {
      final candidate = exercise.name.trim().toLowerCase();
      final distance = _matchDistance(normalizedQuery, candidate);
      if (distance != null) {
        scored.add((exercise, distance));
      }
    }

    scored.sort((a, b) {
      final byDistance = a.$2.compareTo(b.$2);
      if (byDistance != 0) return byDistance;
      return a.$1.name.toLowerCase().compareTo(b.$1.name.toLowerCase());
    });

    return scored.map((entry) => entry.$1).toList(growable: false);
  }

  static bool matches(String query, String candidate) {
    final normalizedQuery = query.trim().toLowerCase();
    final normalizedCandidate = candidate.trim().toLowerCase();
    if (normalizedQuery.isEmpty || normalizedCandidate.isEmpty) return false;
    return _matchDistance(normalizedQuery, normalizedCandidate) != null;
  }

  static int score(String query, String candidate) {
    final normalizedQuery = query.trim().toLowerCase();
    final normalizedCandidate = candidate.trim().toLowerCase();
    if (normalizedQuery.isEmpty || normalizedCandidate.isEmpty) {
      return 1 << 30;
    }

    final distance = _matchDistance(normalizedQuery, normalizedCandidate);
    if (distance != null) return distance;

    final queryTokens = _tokens(normalizedQuery);
    final candidateTokens = _tokens(normalizedCandidate);
    if (queryTokens.isEmpty || candidateTokens.isEmpty) {
      return 1 << 30;
    }

    var totalDistance = 0;
    for (final token in queryTokens) {
      var best = 1 << 30;
      for (final nameToken in candidateTokens) {
        final distance = _editDistance(token, nameToken);
        if (distance < best) best = distance;
      }
      totalDistance += best;
    }

    return totalDistance;
  }

  static int? _matchDistance(
    String normalizedQuery,
    String normalizedCandidate,
  ) {
    if (normalizedCandidate.contains(normalizedQuery)) {
      return 0;
    }

    final queryTokens = _tokens(normalizedQuery);
    final candidateTokens = _tokens(normalizedCandidate);
    if (queryTokens.isEmpty || candidateTokens.isEmpty) return null;

    var totalDistance = 0;
    var totalThreshold = 0;

    for (final token in queryTokens) {
      final threshold = _tokenThreshold(token.length);
      totalThreshold += threshold;

      var bestDistance = 1 << 30;
      for (final nameToken in candidateTokens) {
        final distance = _editDistance(token, nameToken);
        if (distance < bestDistance) bestDistance = distance;
      }

      if (bestDistance > threshold) {
        return null;
      }

      totalDistance += bestDistance;
    }

    if (totalDistance > totalThreshold) return null;
    return totalDistance;
  }

  static List<String> _tokens(String value) => value
      .split(RegExp(r'[^a-z0-9]+'))
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  static int _tokenThreshold(int tokenLength) {
    if (tokenLength <= 3) return 0;
    if (tokenLength <= 5) return 1;
    return 2;
  }

  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (i) => i);

    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;

      for (var j = 1; j <= b.length; j++) {
        final substitutionCost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
            ? 0
            : 1;

        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final substitution = previous[j - 1] + substitutionCost;

        current[j] = deletion < insertion
            ? (deletion < substitution ? deletion : substitution)
            : (insertion < substitution ? insertion : substitution);
      }

      previous = current;
    }

    return previous[b.length];
  }
}

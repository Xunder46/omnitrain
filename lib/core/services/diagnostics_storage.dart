/// Where the diagnostics log keeps its text (plan 143, D-14301).
///
/// Three small operations over one blob of text, so the log's rules (bound,
/// torn line, back-off) are testable without a file system and the web build
/// compiles without `dart:io`.
abstract class DiagnosticsStorage {
  /// Everything stored, or an empty string when nothing is stored or it cannot
  /// be read.
  String read();

  /// Adds [text] after what is stored. False when it could not be written.
  bool append(String text);

  /// Replaces everything stored with [text]. False when it could not be
  /// written; what was stored is then left as it was.
  bool replace(String text);
}

/// Keeps the text in memory: the web build's storage, and a test's.
class InMemoryDiagnosticsStorage implements DiagnosticsStorage {
  String _text = '';

  @override
  String read() => _text;

  @override
  bool append(String text) {
    _text += text;
    return true;
  }

  @override
  bool replace(String text) {
    _text = text;
    return true;
  }
}

import 'dart:async';

import 'restore_read_only_preflight.dart';

/// A short-lived in-memory owner for an *already validated* plaintext
/// candidate staged inside Android no_backup/backup_staging. All callbacks
/// ultimately ask Android to delete its exact quarantined path. The app
/// startup staging sweep is the crash fallback (it never removes journal-owned
/// candidates). This class never grants destructive replacement authority.
final class ReadOnlyImportRetention {
  final RestoreReadOnlyPreviewEvidence evidence;
  final String liveDatabasePath;
  final String validatedCandidatePath;
  final Future<bool> Function(String path) clearNative;
  final void Function(bool success)? onExpiry;
  Timer? _expiry;
  bool _closed = false;
  bool _cleaned = false;
  Future<void>? _inFlight;

  ReadOnlyImportRetention({
    required this.evidence,
    required this.liveDatabasePath,
    required this.validatedCandidatePath,
    required this.clearNative,
    this.onExpiry,
    Duration maxRetention = const Duration(minutes: 5),
  }) {
    if (maxRetention <= Duration.zero ||
        liveDatabasePath.isEmpty || validatedCandidatePath.isEmpty ||
        liveDatabasePath == validatedCandidatePath) {
      throw ArgumentError('Invalid read-only retention');
    }
    _expiry = Timer(maxRetention, () {
      unawaited(close().then(
        (_) => onExpiry?.call(true),
        onError: (Object _) => onExpiry?.call(false),
      ));
    });
  }

  bool get isClosed => _closed;
  bool get cleaned => _cleaned;

  /// Compare only; cannot authorize Phase B. Any mismatch invalidates the
  /// previous preview and attempts immediate native quarantine cleanup.
  Future<RestorePreviewRecheck> recheckReadOnly() async {
    if (_closed) return RestorePreviewRecheck.invalidated;
    final status = await evidence.recheckReadOnly(
      liveDatabasePath: liveDatabasePath,
      validatedCandidatePath: validatedCandidatePath,
    );
    if (_closed) return RestorePreviewRecheck.invalidated;
    if (status != RestorePreviewRecheck.unchanged) await close();
    return status;
  }

  /// One cleanup at a time. A failed native cleanup is NOT reported as success
  /// and may be explicitly retried. A process crash is handled on cold start.
  Future<void> close() {
    _closed = true;
    evidence.invalidate();
    _expiry?.cancel();
    if (_cleaned) return Future<void>.value();
    return _inFlight ??= _doClear();
  }

  Future<void> _doClear() async {
    try {
      final ok = await clearNative(validatedCandidatePath);
      if (!ok) throw StateError('Native import cleanup was not acknowledged');
      _cleaned = true;
    } finally {
      _inFlight = null;
    }
  }
}

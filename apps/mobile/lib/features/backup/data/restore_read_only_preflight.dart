import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'live_database_fingerprint.dart';

/// One read-only observation of an *already authenticated and inspected*
/// candidate. This is NOT a SQLite validation, consent token, or permission
/// to execute Phase B. The OS/native replacement boundary must be reviewed
/// separately and must repeat these checks under an exclusive lifetime lock.
final class ReadOnlyCandidateSeal {
  final int sizeBytes;
  final String sha256;

  const ReadOnlyCandidateSeal(this.sizeBytes, this.sha256);
}

final class _SingleDigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get result =>
      _digest ?? (throw StateError('Candidate SHA-256 was not finalized'));

  @override
  void add(Digest data) {
    if (_digest != null) throw StateError('More than one digest');
    _digest = data;
  }

  @override
  void close() {}
}

Future<ReadOnlyCandidateSeal> _sealCandidate(String path) async {
  const maxCandidateBytes = 64 * 1024 * 1024;
  final file = File(path);
  if (path.isEmpty || !file.isAbsolute ||
      await FileSystemEntity.isLink(path)) {
    throw const FormatException('Invalid candidate path');
  }
  final info = await file.stat();
  if (info.type != FileSystemEntityType.file ||
      info.size < 1 || info.size > maxCandidateBytes) {
    throw const FormatException('Candidate size is invalid');
  }
  final collector = _SingleDigestSink();
  final hashingSink = sha256.startChunkedConversion(collector);
  var total = 0;
  await for (final block in file.openRead()) {
    total += block.length;
    if (total > maxCandidateBytes) {
      throw const FormatException('Candidate exceeds the bounded limit');
    }
    hashingSink.add(block);
  }
  hashingSink.close();
  if (total < 1 || total != info.size) {
    throw const FormatException('Candidate changed during reading');
  }
  // A file could still be replaced after this read. Phase B must verify
  // again under native exclusive ownership immediately before any mutation.
  return ReadOnlyCandidateSeal(total, collector.result.toString());
}

/// Reasons the read-only recheck refused a previous preview. All failures are
/// fail-closed; even [unchanged] is never authorization for active DB mutation.
enum RestorePreviewRecheck {
  unchanged,
  invalidated,
  expired,
  pathChanged,
  liveDataChanged,
  candidateChanged,
  cannotVerify,
}

/// An ephemeral, memory-only read-only preview binding. Never persist to
/// disk, never hold secrets, and never use as a substitute for user consent.
final class RestoreReadOnlyPreviewEvidence {
  final String _livePath;
  final String _candidatePath;
  final String _liveDigest;
  final ReadOnlyCandidateSeal _candidate;
  final Duration _validFor;
  final Stopwatch _lifetime;
  bool _invalidated = false;

  RestoreReadOnlyPreviewEvidence._(
    this._livePath, this._candidatePath, this._liveDigest,
    this._candidate, this._validFor,
  ) : _lifetime = Stopwatch()..start();

  /// Capture is permitted only AFTER successful authenticated decryption and
  /// defensive v5 SQLite inspection of the candidate. Callers are responsible
  /// for those prerequisites; this method only hashes already trusted input.
  static Future<RestoreReadOnlyPreviewEvidence> captureReadOnly({
    required String liveDatabasePath,
    required String validatedCandidatePath,
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    if (maxAge.isNegative || maxAge == Duration.zero ||
        liveDatabasePath.isEmpty || validatedCandidatePath.isEmpty ||
        liveDatabasePath == validatedCandidatePath) {
      throw ArgumentError('Invalid preview evidence parameters');
    }
    final live = await fingerprintLiveDatabase(liveDatabasePath);
    final candidate = await Isolate.run(
        () => _sealCandidate(validatedCandidatePath));
    return RestoreReadOnlyPreviewEvidence._(
      liveDatabasePath, validatedCandidatePath, live.sha256, candidate, maxAge,
    );
  }

  void invalidate() {
    _invalidated = true;
    _lifetime.stop();
  }

  /// The evidence is intentionally one-shot for each operation. This
  /// method *only* compares read-only observations and never grants Restore.
  /// Real Phase B must first obtain exclusive native ownership and freeze
  /// writers, then invoke a separately reviewed final recheck.
  Future<RestorePreviewRecheck> recheckReadOnly({
    required String liveDatabasePath,
    required String validatedCandidatePath,
  }) async {
    if (_invalidated) return RestorePreviewRecheck.invalidated;
    if (_lifetime.elapsed >= _validFor) return RestorePreviewRecheck.expired;
    if (liveDatabasePath != _livePath ||
        validatedCandidatePath != _candidatePath) {
      return RestorePreviewRecheck.pathChanged;
    }
    try {
      final live = await fingerprintLiveDatabase(liveDatabasePath);
      if (_invalidated) return RestorePreviewRecheck.invalidated;
      if (_lifetime.elapsed >= _validFor) return RestorePreviewRecheck.expired;
      if (live.sha256 != _liveDigest) {
        return RestorePreviewRecheck.liveDataChanged;
      }
      final candidate = await Isolate.run(
          () => _sealCandidate(validatedCandidatePath));
      if (_invalidated) return RestorePreviewRecheck.invalidated;
      if (_lifetime.elapsed >= _validFor) return RestorePreviewRecheck.expired;
      if (candidate.sizeBytes != _candidate.sizeBytes ||
          candidate.sha256 != _candidate.sha256) {
        return RestorePreviewRecheck.candidateChanged;
      }
      return RestorePreviewRecheck.unchanged;
    } catch (_) {
      return _invalidated
          ? RestorePreviewRecheck.invalidated
          : RestorePreviewRecheck.cannotVerify;
    }
  }
}

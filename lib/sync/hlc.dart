/// Hybrid Logical Clock (roadmap Phase 4).
///
/// A physical timestamp that never goes backwards plus a counter to break
/// ties. This gives a total order that respects causality even if the two
/// devices' wall clocks disagree.
class Hlc implements Comparable<Hlc> {
  const Hlc(this.physicalMs, this.counter);

  final int physicalMs;
  final int counter;

  static const Hlc zero = Hlc(0, 0);

  /// Encodes as an ISO-8601 UTC instant plus a zero-padded tiebreaker.
  ///
  /// Chosen so that lexicographic text ordering equals chronological ordering,
  /// and so legacy ISO-only timestamps still sort correctly against these.
  String encode() {
    final iso = DateTime.fromMillisecondsSinceEpoch(physicalMs, isUtc: true)
        .toIso8601String();
    return '$iso#${counter.toString().padLeft(6, '0')}';
  }

  static Hlc parse(String text) {
    final hash = text.indexOf('#');
    final iso = hash == -1 ? text : text.substring(0, hash);
    final counter =
        hash == -1 ? 0 : int.tryParse(text.substring(hash + 1)) ?? 0;
    final parsed = DateTime.tryParse(iso);
    return Hlc(parsed?.toUtc().millisecondsSinceEpoch ?? 0, counter);
  }

  /// Month key (`yyyy-MM`) used for shard rotation.
  DateTime get month =>
      DateTime.fromMillisecondsSinceEpoch(physicalMs, isUtc: true);

  @override
  int compareTo(Hlc other) {
    final byPhysical = physicalMs.compareTo(other.physicalMs);
    return byPhysical != 0 ? byPhysical : counter.compareTo(other.counter);
  }

  @override
  String toString() => encode();

  @override
  bool operator ==(Object other) => other is Hlc && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(physicalMs, counter);
}

/// Generates monotonically increasing [Hlc] values.
class HlcClock {
  HlcClock([Hlc? initial]) : _last = initial ?? Hlc.zero;

  Hlc _last;

  Hlc get last => _last;

  /// Next local timestamp. Never returns a value <= a previously returned one.
  Hlc next({DateTime? now}) {
    final ms = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
    _last = ms > _last.physicalMs
        ? Hlc(ms, 0)
        : Hlc(_last.physicalMs, _last.counter + 1);
    return _last;
  }

  /// Advances the clock past a remote event, so subsequent local events sort
  /// after everything we have already seen.
  void observe(Hlc remote) {
    if (remote.compareTo(_last) > 0) _last = remote;
  }
}

// Feature flags, производные от Pro-статуса.
//
// Централизует все гейты Free vs Pro: BPM-диапазон, доступ к debug-экрану,
// экспорту, виджету, лимиты истории. UI и бизнес-логика зависят только от
// этого класса, а не от `ProStatusService` напрямую.

class FeatureFlags {
  const FeatureFlags({required this.isPro});

  final bool isPro;

  // BPM range gates
  double get minBpm => isPro ? 155.0 : 170.0;
  double get maxBpm => 230.0;

  // Feature access gates
  bool get canAccessDebugScreen => isPro;
  bool get canExport => isPro;
  bool get canAccessWidget => isPro;
  bool get canAccessSetlist => isPro;

  // History limits
  Duration get maxHistoryDuration => isPro
      ? const Duration(hours: 24) // Pro: unlimited (24h cap as safety)
      : const Duration(seconds: 30); // Free: 30 seconds

  int get maxHistorySamples => isPro
      ? 86400 // Pro: 24h at 1 Hz
      : 30; // Free: 30 samples at 1 Hz
}

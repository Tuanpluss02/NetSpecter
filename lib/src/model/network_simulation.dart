class NetworkSimulationProfile {
  const NetworkSimulationProfile({
    required this.name,
    required this.offline,
    required this.latencyMs,
    required this.downloadKbps,
    required this.uploadKbps,
  });

  final String name;
  final bool offline;
  final int latencyMs;
  final int downloadKbps;
  final int uploadKbps;

  bool get isNoThrottling =>
      !offline && latencyMs <= 0 && downloadKbps <= 0 && uploadKbps <= 0;

  static const none = NetworkSimulationProfile(
    name: 'No throttling',
    offline: false,
    latencyMs: 0,
    downloadKbps: 0,
    uploadKbps: 0,
  );

  static const offlineProfile = NetworkSimulationProfile(
    name: 'Offline',
    offline: true,
    latencyMs: 0,
    downloadKbps: 0,
    uploadKbps: 0,
  );

  static const slow3G = NetworkSimulationProfile(
    name: 'Slow 3G',
    offline: false,
    latencyMs: 400,
    downloadKbps: 400,
    uploadKbps: 400,
  );

  static const fast3G = NetworkSimulationProfile(
    name: 'Fast 3G',
    offline: false,
    latencyMs: 150,
    downloadKbps: 1600,
    uploadKbps: 750,
  );

  static const fourG = NetworkSimulationProfile(
    name: '4G',
    offline: false,
    latencyMs: 70,
    downloadKbps: 9000,
    uploadKbps: 9000,
  );

  static const wifi = NetworkSimulationProfile(
    name: 'Wi-Fi',
    offline: false,
    latencyMs: 30,
    downloadKbps: 30000,
    uploadKbps: 15000,
  );

  static const presets = <NetworkSimulationProfile>[
    none,
    offlineProfile,
    slow3G,
    fast3G,
    fourG,
    wifi,
  ];

  NetworkSimulationProfile copyWith({
    String? name,
    bool? offline,
    int? latencyMs,
    int? downloadKbps,
    int? uploadKbps,
  }) {
    return NetworkSimulationProfile(
      name: name ?? this.name,
      offline: offline ?? this.offline,
      latencyMs: latencyMs ?? this.latencyMs,
      downloadKbps: downloadKbps ?? this.downloadKbps,
      uploadKbps: uploadKbps ?? this.uploadKbps,
    );
  }
}

class SimulatedNetworkException implements Exception {
  const SimulatedNetworkException(this.message);

  final String message;

  @override
  String toString() => message;
}

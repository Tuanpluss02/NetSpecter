import '../models/net_specter_settings.dart';

class RetentionPolicy {
  const RetentionPolicy({
    required this.retentionDays,
    required this.maxStorageBytes,
  });

  factory RetentionPolicy.fromSettings(NetSpecterSettings settings) {
    return RetentionPolicy(
      retentionDays: settings.retentionDays,
      maxStorageBytes: settings.maxStorageBytes,
    );
  }

  final int retentionDays;
  final int maxStorageBytes;
}

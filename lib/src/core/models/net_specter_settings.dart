class NetSpecterSettings {
  const NetSpecterSettings({
    this.retentionDays = 3,
    this.maxStorageBytes = 50 * 1024 * 1024,
    this.isolateThresholdBytes = 100 * 1024,
    this.previewTruncationBytes = 16 * 1024,
    this.maxBodyBytes = 2 * 1024 * 1024,
    this.maxQueuedEvents = 500,
  });

  final int retentionDays;
  final int maxStorageBytes;
  final int isolateThresholdBytes;
  final int previewTruncationBytes;
  final int maxBodyBytes;
  final int maxQueuedEvents;
}

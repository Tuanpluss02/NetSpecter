import 'package:flutter/material.dart';

import '../../core/netspecter_controller.dart';

class NetSpecterSettingsScreen extends StatelessWidget {
  const NetSpecterSettingsScreen({
    super.key,
    required this.specter,
  });

  final NetSpecter specter;

  @override
  Widget build(BuildContext context) {
    final settings = specter.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('NetSpecter Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Retention days: ${settings.retentionDays}'),
          const SizedBox(height: 12),
          Text('Max storage: ${settings.maxStorageBytes} bytes'),
          const SizedBox(height: 12),
          Text('Isolate threshold: ${settings.isolateThresholdBytes} bytes'),
          const SizedBox(height: 12),
          Text(
            'Preview truncation: ${settings.previewTruncationBytes} bytes',
          ),
          const SizedBox(height: 12),
          Text('Max body storage: ${settings.maxBodyBytes} bytes'),
          const SizedBox(height: 12),
          Text('Max queued events: ${settings.maxQueuedEvents}'),
          const SizedBox(height: 12),
          Text('Dropped events: ${specter.droppedEvents}'),
          const SizedBox(height: 12),
          Text('Captured calls in memory: ${specter.calls.length}'),
        ],
      ),
    );
  }
}

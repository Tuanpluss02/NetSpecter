# Interceptly

[![pub package](https://img.shields.io/pub/v/interceptly.svg)](https://pub.dev/packages/interceptly)
[![pub points](https://img.shields.io/pub/points/interceptly.svg)](https://pub.dev/packages/interceptly)
[![license](https://img.shields.io/github/license/Tuanpluss02/interceptly.svg)](https://github.com/Tuanpluss02/interceptly/blob/main/LICENSE)

Interceptly is a high-performance network inspector for Flutter. It provides real-time traffic visualization for Dio, Http, and Chopper with minimal impact on UI performance.

[Features](#features) | [Installation](#install) | [Quick Start](#quick-start-dio) | [Integrations](#integrations) | [Network Simulation](#network-simulation)

---

## Features

- **High Performance**: Background isolates handle all serialization logic to prevent UI jank.
- **Hybrid Storage**: Smart memory management that offloads large payloads to temporary files.
- **Postman-like Replay**: Built-in request editor to modify headers/body and re-send requests.
- **Network Simulation**: Global profiles for Offline, 3G, 4G, or custom latency/bandwidth.
- **Advanced Formatters**: Specialized views for GraphQL, Multipart, cURL, and Binary data.
- **Flexible Triggers**: Support for Shake, Long Press, Floating Button, or Custom Streams.

---

## Install

Add the following to your `pubspec.yaml`:

```yaml
dependencies:
  interceptly: ^1.0.1
```

---

## Quick Start (Dio)

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  // 1. Initialize interceptor
  final dio = Dio()..interceptors.add(Interceptly.dioInterceptor);

  runApp(
    MaterialApp(
      home: InterceptlyOverlay(
        // 2. Wrap your application
        child: MyApp(dio: dio),
      ),
    ),
  );
}
```

---

## Integrations

### Dio
```dart
final dio = Dio()..interceptors.add(Interceptly.dioInterceptor);
```

### HTTP (package:http)
```dart
import 'package:http/http.dart' as http;

final client = Interceptly.wrapHttpClient(http.Client());
final res = await client.get(Uri.parse('[https://api.example.com/data](https://api.example.com/data)'));
```

### Chopper
```dart
import 'package:chopper/chopper.dart';

final chopper = ChopperClient(
  interceptors: [InterceptlyChopperInterceptor()],
);
```

---

## Network Simulation

Simulate various network conditions globally for all intercepted requests:

```dart
// Apply built-in profiles
Interceptly.instance.setNetworkSimulation(NetworkSimulationProfile.slow3G);

// Custom profile definition
Interceptly.instance.setNetworkSimulation(
  const NetworkSimulationProfile(
    name: 'Custom Profile',
    latencyMs: 500,
    downloadKbps: 1000,
    uploadKbps: 500,
  ),
);

// Disable simulation
Interceptly.instance.clearNetworkSimulation();
```

---

## Configuration

### InterceptlySettings

| Parameter | Default | Description |
| :--- | :--- | :--- |
| `bodyOffloadThreshold` | `50 * 1024` | Threshold (bytes) to move body to temp file |
| `maxEntries` | `5000` | Maximum requests kept in history |
| `maxBodyBytes` | `2 * 1024 * 1024` | Hard cap for body size before truncation |
| `urlDecodeEnabled` | `true` | Initial state of URL decoding in UI |

### UI Triggers
```dart
InterceptlyOverlay(
  config: InterceptlyConfig(
    triggers: {
      InspectorTrigger.floatingButton,
      InspectorTrigger.shake,
      InspectorTrigger.longPress,
    },
    shakeThreshold: 15.0,
  ),
  child: MyApp(),
)
```

---

## Navigator Setup (MaterialApp.router)

To use `Interceptly.showInspector()` without context in Router-based applications, pass the navigator key to the overlay:

```dart
final navigatorKey = GlobalKey();

MaterialApp.router(
  routerConfig: router,
  builder: (context, child) {
    return InterceptlyOverlay(
      navigatorKey: navigatorKey,
      child: child ?? const SizedBox(),
    );
  },
)
```

---

## Storage Model

- **Small Payloads**: Kept in memory for instant access.
- **Large Payloads**: Written to temporary files via background isolates to keep memory footprint low.
- **Lazy Loading**: Body data is only loaded from disk when a record is selected for inspection.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---
Published by [stormx.dev](https://stormx.dev)
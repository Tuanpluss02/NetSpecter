# NetSpecter

NetSpecter is a Flutter network inspector package focused on `dio` with disk-backed storage, in-app inspection UI, and a low-friction setup flow.

## Features

- Capture `dio` requests, responses, and errors
- Open an in-app inspector from a draggable floating button
- Persist captured calls locally with `isar`
- Inspect overview, request, response, and error details
- Filter by method, status code, host, and text query
- Generate cURL and HAR data from captured calls

## Getting Started

Add the package, then attach the interceptor and wrap your app with `NetSpecterOverlay`.

```yaml
dependencies:
  netspecter: ^0.0.1
```

## Usage

### Minimal setup

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:netspecter/netspecter.dart';

void main() {
  final dio = Dio()..interceptors.add(NetSpecterDioInterceptor());

  runApp(
    MaterialApp(
      home: NetSpecterOverlay(
        child: MyApp(dio: dio),
      ),
    ),
  );
}
```

This setup uses the shared `NetSpecter.instance` internally, so you do not need to manually create or initialize the inspector in the common case.

### What `NetSpecterOverlay` does

`NetSpecterOverlay` adds a draggable floating button on top of your app. Tapping that button opens the NetSpecter inspector UI.

### Advanced usage

If you want a custom instance for tests or special app flows, you can still provide one explicitly:

```dart
final specter = NetSpecter.withIsar();
final dio = Dio()..interceptors.add(NetSpecterDioInterceptor(specter));

runApp(
  MaterialApp(
    home: NetSpecterOverlay(
      specter: specter,
      child: MyApp(dio: dio),
    ),
  ),
);
```

### Open the example app

See `example/lib/main.dart` for a working integration with:

- `GET` request
- `POST` request
- error request

## Current Scope

- Primary client support: `dio`
- Inspector UI: available in-app
- Storage: `isar`
- Intended usage: debug and internal tooling workflows

## Notes

- The default floating trigger is draggable.
- The current UI is functional-first and may evolve.
- For a complete runnable integration, check the `example/` app.

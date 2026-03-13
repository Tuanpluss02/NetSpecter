# NetSpecter v1 Plan

## Product Goal
Build a Flutter network inspector package that is fast under heavy traffic, safe for long-running debug sessions, and pleasant to use in real apps.

The package should specifically improve on common problems in existing tools:
1. Avoid UI jank when inspecting large payloads.
2. Avoid unbounded in-memory growth during long sessions.
3. Provide a clean developer workflow for inspecting, filtering, and exporting calls.

## v1 Scope

### In Scope
1. `dio` integration only.
2. Debug-only in-app inspector UI.
3. Disk-backed request/response storage.
4. Search, filter, pagination, and request detail view.
5. Copy as cURL.
6. Export to HAR.

### Out of Scope
1. `package:http` support.
2. Native `HttpClient` support.
3. Response mocking.
4. Network throttling.
5. Postman export.
6. Production runtime support.

Reasoning: v1 should prove the core architecture before adding more client adapters or "power features".

## Key Decisions

1. **HTTP client for v1:** `dio` only.
   `dio` has a clear interceptor model, which makes capture, timing, error handling, and future mocking feasible.

2. **Storage engine for v1:** `isar`.
   We need indexed local persistence, query support, and fast reads for paginated UI. A custom file logger adds too much product risk for the first release.

3. **Threading model:** main isolate for lightweight capture, worker isolate for expensive payload work.
   Request metadata is captured immediately. Heavy tasks such as JSON pretty-printing, large body normalization, and compression handling are delegated to a worker isolate only when thresholds are exceeded.

4. **Retention policy:** bounded storage, not best-effort cleanup.
   v1 should enforce both:
   - TTL: default 3 days
   - Size cap: default 50 MB
   If either limit is exceeded, oldest records are purged first.

5. **Release target:** mobile Flutter debug builds first.
   Desktop/web support can be evaluated later, but should not drive the v1 architecture.

## Non-Functional Requirements

1. Scrolling the request list remains smooth with at least 10,000 stored calls.
2. Capturing traffic must not block the UI thread on large JSON payloads.
3. Storage growth must stay bounded by policy.
4. The package must degrade safely under burst traffic.
5. The inspector must be optional and removable from host apps with minimal setup.

## Architecture

The system is split into 4 layers.

### 1. Capture Layer
- A `NetSpecterDioInterceptor` captures request, response, and error events.
- The interceptor records lightweight metadata immediately:
  - method
  - url
  - headers
  - status code
  - timings
  - body size
  - content type
- The interceptor should avoid expensive formatting work inline.

### 2. Ingestion Queue
- Captured events are pushed into an internal bounded queue.
- The queue must have explicit backpressure behavior.
- v1 policy:
  - keep a max queue size
  - drop oldest unprocessed items when overloaded
  - increment a dropped-events counter for observability

This is important because a plain broadcast stream does not solve memory pressure by itself.

### 3. Processing and Storage
- Small payloads can be normalized on the main isolate if cost is trivial.
- Large or expensive payloads are sent to a worker isolate.
- Processing tasks include:
  - gzip or compressed body decoding when possible
  - JSON detection and pretty formatting
  - safe text truncation for very large bodies
  - preview generation for list/detail screens
- Processed calls are persisted to `isar`.
- Data model should separate:
  - indexed metadata used for search/listing
  - larger request/response body fields

### 4. Presentation Layer
- A debug-only overlay entry opens the inspector.
- Main screens:
  - request list
  - request detail
  - settings
- The list must use database-backed pagination, not in-memory snapshots.
- Search and filter should operate on indexed metadata first, with body search explicitly deferred unless performance is proven acceptable.

## Proposed Package Structure

```text
lib/
├── netspecter.dart
└── src/
    ├── capture/
    │   └── dio/
    │       └── netspecter_dio_interceptor.dart
    ├── core/
    │   ├── models/
    │   ├── queue/
    │   ├── processing/
    │   ├── storage/
    │   └── retention/
    ├── ui/
    │   ├── overlay/
    │   ├── screens/
    │   └── widgets/
    └── export/
        ├── curl_generator.dart
        └── har_exporter.dart
```

## Data Model

Core entities for v1:
1. `HttpCall`
2. `HttpRequestData`
3. `HttpResponseData`
4. `HttpErrorData`
5. `NetSpecterSettings`

Minimum indexed fields on `HttpCall`:
1. id
2. createdAt
3. method
4. url
5. host
6. path
7. statusCode
8. durationMs
9. hasError
10. requestBodyBytes
11. responseBodyBytes

## Performance Rules

1. Do not pretty-print every payload eagerly.
2. Only send bodies to the worker isolate above a defined threshold.
3. Store raw body and preview separately when useful.
4. Truncate display payloads safely for huge responses.
5. Never render the full dataset in memory for the main list.

Suggested first thresholds:
- Isolate threshold: 100 KB
- Preview truncation threshold: 16 KB
- Hard body storage cap per field: configurable, default 2 MB

These values can be tuned after benchmarks.

## Benchmarks and Validation

Performance is a product requirement, so it must be validated before release.

### Benchmark Scenarios
1. 1,000 small JSON calls.
2. 500 medium calls with 100-300 KB bodies.
3. 100 large calls with 1-2 MB bodies.
4. Burst traffic: 200 calls in a short interval.
5. Long session retention test until storage cap is reached.

### Metrics to Track
1. Frame stability while list is open.
2. Average and p95 processing time per call.
3. Queue depth under burst load.
4. Number of dropped events.
5. Database write latency.
6. Total disk usage over time.
7. Peak memory during stress tests.

## Milestones

### Phase 1: Foundation and Capture
- [x] Initialize Flutter package structure.
- [x] Define v1 public API.
- [x] Implement `NetSpecter` controller/service.
- [x] Implement `NetSpecterDioInterceptor`.
- [x] Capture request, response, and error metadata correctly.
- [x] Add smoke example app.

Acceptance criteria:
- A sample app using `dio` can record and display basic calls.
- No request inspection logic blocks normal app flow.

### Phase 2: Queue, Processing, and Storage
- [x] Implement bounded ingestion queue.
- [x] Implement worker-isolate payload processing.
- [x] Persist `HttpCall` records to `isar`.
- [x] Implement retention cleanup by TTL and size cap.
- [x] Add dropped-events telemetry in debug UI/settings.

Acceptance criteria:
- The system remains stable during burst traffic.
- Storage remains bounded without manual cleanup.

### Phase 3: Inspector UI
- [x] Build overlay entry point.
- [x] Build paginated request list.
- [x] Build detail screen with tabs:
  - overview
  - request
  - response
  - error
- [x] Add filters for method, status, host, and text query.
- [x] Add settings screen for retention and capture limits.

Acceptance criteria:
- Users can inspect at least 10,000 stored calls without loading all rows into memory.
- Large payloads do not freeze navigation into the detail screen.

### Phase 4: Export and Developer Workflow
- [ ] Implement "Copy as cURL".
- [ ] Implement HAR export.
- [ ] Improve empty states, error states, and loading states.
- [ ] Document setup and limitations clearly.

Acceptance criteria:
- Exported HAR is valid for common inspection workflows.
- cURL output reproduces request metadata accurately enough for debugging.

### Phase 5: Testing, Benchmarking, and Release
- [ ] Unit tests for models, processing, retention, and exports.
- [ ] Widget tests for core UI flows.
- [ ] Integration tests with a sample `dio` app.
- [ ] Benchmark and memory stress test suite.
- [ ] CI for `flutter test` and `flutter analyze`.
- [ ] Prepare `README.md`, screenshots, and example project.
- [ ] Publish initial version to `pub.dev`.

Acceptance criteria:
- Benchmarks satisfy agreed thresholds.
- Documentation is sufficient for first-time setup in under 10 minutes.

## Risks and Mitigations

1. **Large bodies still cause memory pressure**
   Mitigation: bounded queue, truncation rules, body size caps, and lazy formatting.

2. **`isar` adds package complexity**
   Mitigation: isolate all storage behind an interface so a future backend swap is possible.

3. **Overlay UX may be intrusive**
   Mitigation: keep overlay optional and provide a direct `NetSpecterScreen` entry point as fallback.

4. **Feature creep in v1**
   Mitigation: response mocking, throttling, and multi-client support stay out of the first release.

## Future Roadmap After v1

1. Add `package:http` support via a dedicated wrapped client API.
2. Evaluate native `HttpClient` support.
3. Add response mocking rules for `dio`.
4. Add Postman export.
5. Add advanced search over headers and body content.

## Draft Quick Start

```dart
runApp(
  NetSpecterOverlay(
    child: MyApp(),
  ),
);

dio.interceptors.add(
  NetSpecterDioInterceptor(),
);
```
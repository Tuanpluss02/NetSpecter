import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/queue/bounded_event_queue.dart';
import '../model/body_location.dart';
import '../model/http_call_filter.dart';
import '../model/index_entry.dart';
import '../model/net_specter_settings.dart';
import '../model/raw_capture.dart';
import '../model/request_record.dart';
import 'body_store.dart';
import 'memory_index.dart';
import 'writer_isolate.dart';

/// Central lifecycle manager for the NetSpecter session.
///
/// Owns the [MemoryIndex] (in-RAM list view data) and the [WriterIsolate]
/// (serialised disk writer for large bodies).
///
/// All public methods are safe to call from the main isolate.
class InspectorSession extends ChangeNotifier {
  InspectorSession({NetSpecterSettings? settings})
      : settings = settings ?? const NetSpecterSettings() {
    _memoryIndex = MemoryIndex(maxEntries: this.settings.maxEntries);
    _writerIsolate = WriterIsolate(this.settings);
    _preInitQueue = BoundedEventQueue(maxSize: this.settings.maxQueuedEvents);
  }

  static InspectorSession? _instance;

  static InspectorSession get instance {
    return _instance ??= InspectorSession();
  }

  final NetSpecterSettings settings;
  late final MemoryIndex _memoryIndex;
  late final WriterIsolate _writerIsolate;
  late final BoundedEventQueue<RawCapture> _preInitQueue;
  StreamSubscription<IndexEntry>? _resultSub;

  Future<void>? _initFuture;
  bool _initialized = false;
  bool _enabled = true;
  bool _clearing = false;
  bool _urlDecodeEnabled = false;

  /// Captures sent to the isolate but not yet returned as [IndexEntry].
  int _inFlight = 0;
  int _droppedCount = 0;

  /// Pre-resolved temp file path (set during [initialize], main isolate only).
  String? _tempFilePath;

  HttpCallFilter _filter = const HttpCallFilter();

  // Master search state.
  String? _masterQuery;
  List<IndexEntry>? _masterResults;
  bool _isScanningBodies = false;
  bool _isScanningFiles = false;
  int _searchGeneration = 0;

  HttpCallFilter get filter => _filter;
  List<IndexEntry> get entries {
    if (_masterQuery != null) {
      return _masterResults ?? const [];
    }
    return _memoryIndex.filtered(_filter);
  }

  int get totalEntries => _memoryIndex.length;
  int get droppedCount => _droppedCount;
  bool get isEnabled => _enabled;
  bool get urlDecodeEnabled => _urlDecodeEnabled;

  String? get masterQuery => _masterQuery;
  bool get isMasterSearchActive => _masterQuery != null;
  bool get isScanningBodies => _isScanningBodies;
  bool get isScanningFiles => _isScanningFiles;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> initialize() async {
    _initFuture ??= _performInit();
    return _initFuture;
  }

  Future<void> _performInit() async {
    if (_initialized) return;

    // Resolve the temp directory HERE on the main isolate — never inside
    // the background isolate where platform channels are unavailable.
    final dir = await getTemporaryDirectory();
    _tempFilePath = '${dir.path}/${BodyStore.kFileName}';

    await _writerIsolate.start(tempDirPath: dir.path);
    _resultSub = _writerIsolate.results.listen(_onEntryReady);
    _initialized = true;

    // Flush captures buffered before the isolate was ready.
    // Runs synchronously (no awaits) so no new record() call can interleave.
    _droppedCount += _preInitQueue.droppedCount;
    _urlDecodeEnabled = settings.urlDecodeEnabled;
    RawCapture? pending;
    while ((pending = _preInitQueue.removeFirstOrNull()) != null) {
      _sendCapture(pending!);
    }
  }

  void _onEntryReady(IndexEntry entry) {
    _inFlight--;
    _memoryIndex.add(entry);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Capture control
  // ---------------------------------------------------------------------------

  /// Enables capture. Capture is enabled by default.
  void enable() {
    _enabled = true;
  }

  /// Disables capture. The interceptor still runs but all [record] calls are
  /// silently dropped. Useful for hiding sensitive screens (e.g. payment flows).
  void disable() {
    _enabled = false;
  }

  /// Toggles URL decoding for the UI views.
  void setUrlDecodeEnabled(bool value) {
    if (_urlDecodeEnabled != value) {
      _urlDecodeEnabled = value;
      notifyListeners();
    }
  }

  /// Fire-and-forget: enqueue a [RawCapture] for background processing.
  /// Returns immediately — never blocks the interceptor.
  /// No-op when [isEnabled] is false or the queue is full.
  void record(RawCapture capture) {
    if (!_enabled) return;
    if (!_initialized) {
      // Buffer until the isolate is ready; bounded by maxQueuedEvents.
      _preInitQueue.add(capture);
      initialize();
      return;
    }
    _sendCapture(capture);
  }

  void _sendCapture(RawCapture capture) {
    if (_inFlight >= settings.maxQueuedEvents) {
      _droppedCount++;
      return;
    }
    _inFlight++;
    _writerIsolate.send(capture);
  }

  // ---------------------------------------------------------------------------
  // Filter
  // ---------------------------------------------------------------------------

  void applyFilter(HttpCallFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  void clearFilter() {
    _filter = const HttpCallFilter();
    notifyListeners();
  }

  /// Cancels any in-progress master search and restores normal filtered mode.
  void cancelMasterSearch() {
    _searchGeneration++;
    _masterQuery = null;
    _masterResults = null;
    _isScanningBodies = false;
    _isScanningFiles = false;
    notifyListeners();
  }

  /// Starts a progressive master search over all captures.
  ///
  /// Phase 1 (sync): URL, method, headers, error messages.
  /// Phase 2 (chunked async): in-memory bodies.
  /// Phase 3 (async I/O): file-backed bodies.
  Future<void> startMasterSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      cancelMasterSearch();
      return;
    }

    final gen = ++_searchGeneration;
    final q = trimmed.toLowerCase();

    _masterQuery = trimmed;
    _masterResults = [];
    _isScanningBodies = false;
    _isScanningFiles = false;
    notifyListeners();

    final allEntries = _memoryIndex.entries;
    final matchedIds = <String>{};

    bool matchesStructured(IndexEntry e) {
      if (e.url.toLowerCase().contains(q)) return true;
      if (e.method.toLowerCase().contains(q)) return true;
      if (e.errorMessage?.toLowerCase().contains(q) ?? false) return true;

      for (final h in e.requestHeaders.entries) {
        if (h.key.toLowerCase().contains(q)) return true;
        if (h.value.toLowerCase().contains(q)) return true;
      }
      for (final h in e.responseHeaders.entries) {
        if (h.key.toLowerCase().contains(q)) return true;
        if (h.value.toLowerCase().contains(q)) return true;
      }
      return false;
    }

    bool matchesInlineBody(IndexEntry e) {
      final req =
          _decodeBody(e.inlineRequestBody, e.requestContentType)?.toLowerCase();
      if (req != null && req.contains(q)) return true;
      final res = _decodeBody(e.inlineResponseBody, e.responseContentType)
          ?.toLowerCase();
      if (res != null && res.contains(q)) return true;
      return false;
    }

    // Phase 1: structured fields only (sync).
    for (final e in allEntries) {
      if (matchesStructured(e)) {
        matchedIds.add(e.id);
        _masterResults!.add(e);
      }
    }
    if (gen != _searchGeneration) return;
    notifyListeners();

    // Phase 2: in-memory bodies, processed in small async batches (append-only for O(1) updates).
    _isScanningBodies = true;
    notifyListeners();
    for (var i = 0; i < allEntries.length; i++) {
      if (gen != _searchGeneration) return;
      final e = allEntries[i];
      if (e.bodyLocation == BodyLocation.memory &&
          !matchedIds.contains(e.id) &&
          matchesInlineBody(e)) {
        matchedIds.add(e.id);
        _masterResults!.add(e);
        notifyListeners();
      }
      if (i % 20 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (gen != _searchGeneration) return;
    _isScanningBodies = false;
    notifyListeners();

    // Phase 3: file-backed bodies with parallel batch reading for better performance.
    final filePath = _tempFilePath;
    if (filePath != null) {
      _isScanningFiles = true;
      notifyListeners();

      // Collect all file entries to read.
      final fileEntries = <(IndexEntry, int, int)>[];
      for (final e in allEntries) {
        if (e.bodyLocation == BodyLocation.file &&
            !matchedIds.contains(e.id) &&
            e.fileOffset != null &&
            e.fileLength != null) {
          fileEntries.add((e, e.fileOffset!, e.fileLength!));
        }
      }

      // Process in parallel batches of 4 files.
      const batchSize = 4;
      for (var batchStart = 0;
          batchStart < fileEntries.length;
          batchStart += batchSize) {
        if (gen != _searchGeneration) return;

        final batchEnd = (batchStart + batchSize).clamp(0, fileEntries.length);
        final batch = fileEntries.sublist(batchStart, batchEnd);

        final futures = batch.map((entry) async {
          try {
            final (e, offset, length) = entry;
            final raw = await BodyStore.readBytes(filePath, offset, length);
            final decoded = raw.length > _kComputeThreshold
                ? await compute(_unpackBodies, raw)
                : _unpackBodies(raw);
            final combined =
                '${decoded.$1 ?? ''}\n${decoded.$2 ?? ''}'.toLowerCase();
            if (combined.contains(q)) {
              return (true, e);
            }
          } catch (_) {
            // Ignore individual file read errors for search.
          }
          return (false, null);
        });

        final results = await Future.wait(futures);
        for (final (matched, e) in results) {
          if (matched && e != null && !matchedIds.contains(e.id)) {
            matchedIds.add(e.id);
            _masterResults!.add(e);
            notifyListeners();
          }
        }
      }

      if (gen != _searchGeneration) return;
      _isScanningFiles = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Detail loading
  // ---------------------------------------------------------------------------

  /// Load the full [RequestRecord] for [entry].
  ///
  /// - [BodyLocation.memory]: decodes inline bytes, zero I/O.
  /// - [BodyLocation.file]: reads only the specific region via
  ///   [BodyStore.readBytes] — never recreates or deletes the file.
  Future<RequestRecord> loadDetail(IndexEntry entry) async {
    String? reqPreview;
    String? resPreview;
    bool isTruncated = entry.isBodyTruncated;

    if (entry.bodyLocation == BodyLocation.memory) {
      reqPreview =
          _decodeBody(entry.inlineRequestBody, entry.requestContentType);
      resPreview =
          _decodeBody(entry.inlineResponseBody, entry.responseContentType);
    } else {
      final offset = entry.fileOffset;
      final length = entry.fileLength;
      final filePath = _tempFilePath;

      if (offset != null && length != null && filePath != null) {
        try {
          // Static read — creates a read-only handle, never modifies the file.
          final raw = await BodyStore.readBytes(filePath, offset, length);
          final decoded = raw.length > _kComputeThreshold
              ? await compute(_unpackBodies, raw)
              : _unpackBodies(raw);
          reqPreview = decoded.$1;
          resPreview = decoded.$2;
          isTruncated = isTruncated || decoded.$3;
        } catch (_) {
          reqPreview = '[body unavailable]';
          resPreview = '[body unavailable]';
        }
      }
    }

    return RequestRecord(
      id: entry.id,
      method: entry.method,
      url: entry.url,
      statusCode: entry.statusCode,
      durationMs: entry.durationMs,
      requestSizeBytes: entry.requestSizeBytes,
      responseSizeBytes: entry.responseSizeBytes,
      timestamp: entry.timestamp,
      requestHeaders: entry.requestHeaders,
      responseHeaders: entry.responseHeaders,
      requestContentType: entry.requestContentType,
      responseContentType: entry.responseContentType,
      requestBodyPreview: reqPreview,
      responseBodyPreview: resPreview,
      isBodyTruncated: isTruncated,
      errorType: entry.errorType,
      errorMessage: entry.errorMessage,
    );
  }

  // ---------------------------------------------------------------------------
  // Clear / Dispose
  // ---------------------------------------------------------------------------

  Future<void> clear() async {
    if (_clearing) return;
    _clearing = true;
    try {
      if (_initialized) {
        // Wait for the isolate to finish all pending writes AND reset the file
        // before clearing the in-memory index, so offsets never go stale.
        await _writerIsolate.clear();
      } else {
        _preInitQueue.clear();
      }
      _droppedCount = 0;
      _memoryIndex.clear();
      _filter = const HttpCallFilter();
      _searchGeneration++;
      _masterQuery = null;
      _masterResults = null;
      _isScanningBodies = false;
      _isScanningFiles = false;
      notifyListeners();
    } finally {
      _clearing = false;
    }
  }

  @override
  Future<void> dispose() async {
    await _resultSub?.cancel();
    await _writerIsolate.dispose();
    await _memoryIndex.dispose();
    _preInitQueue.clear();
    _initialized = false;
    _inFlight = 0;
    _initFuture = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Body decode helpers
  // ---------------------------------------------------------------------------

  /// Bytes above this threshold are decoded in a background isolate via
  /// [compute] to avoid blocking the main isolate for tens of milliseconds.
  static const int _kComputeThreshold = 100 * 1024; // 100 KB

  static String? _decodeBody(Uint8List? bytes, String? contentType) {
    if (bytes == null || bytes.isEmpty) return null;
    if (_isBinaryContentType(contentType)) {
      return '[binary: ${bytes.length} bytes]';
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return '[binary: ${bytes.length} bytes]';
    }
  }

  static bool _isBinaryContentType(String? contentType) {
    if (contentType == null) return false;
    return contentType.startsWith('image/') ||
        contentType.startsWith('audio/') ||
        contentType.startsWith('video/') ||
        contentType.contains('application/pdf') ||
        contentType.contains('application/octet-stream') ||
        contentType.contains('application/zip');
  }

  static (String?, String?, bool) _unpackBodies(Uint8List raw) {
    try {
      final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final reqBase64 = json['req'] as String?;
      final resBase64 = json['res'] as String?;
      final truncated = json['truncated'] as bool? ?? false;

      final req = reqBase64 != null ? _tryUtf8(base64.decode(reqBase64)) : null;
      final res = resBase64 != null ? _tryUtf8(base64.decode(resBase64)) : null;
      return (req, res, truncated);
    } catch (_) {
      return (null, null, false);
    }
  }

  static String _tryUtf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return '[binary: ${bytes.length} bytes]';
    }
  }
}

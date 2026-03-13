import 'package:flutter/foundation.dart';

import 'models/http_call.dart';
import 'models/http_call_filter.dart';
import 'models/net_specter_settings.dart';
import 'processing/payload_processor.dart';
import 'queue/bounded_event_queue.dart';
import 'retention/retention_policy.dart';
import 'storage/isar/isar_netspecter_storage.dart';
import 'storage/netspecter_storage.dart';

class NetSpecter extends ChangeNotifier {
  static const int _defaultPageSize = 50;
  static NetSpecter? _instance;

  NetSpecter({
    this.settings = const NetSpecterSettings(),
    NetSpecterStorage? storage,
  })  : storage = storage ?? InMemoryNetSpecterStorage(),
        retentionPolicy = RetentionPolicy.fromSettings(settings),
        queue = BoundedEventQueue<HttpCall>(maxSize: settings.maxQueuedEvents);

  final NetSpecterSettings settings;
  final NetSpecterStorage storage;
  final RetentionPolicy retentionPolicy;
  final BoundedEventQueue<HttpCall> queue;

  Future<void>? _initializationFuture;
  List<HttpCall> _calls = const <HttpCall>[];
  HttpCallFilter _filter = const HttpCallFilter();
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;

  List<HttpCall> get calls => _calls;
  HttpCallFilter get filter => _filter;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  int get droppedEvents => queue.droppedCount;

  static NetSpecter get instance {
    return _instance ??= NetSpecter.withIsar();
  }

  factory NetSpecter.withIsar({
    NetSpecterSettings settings = const NetSpecterSettings(),
    String? directory,
  }) {
    final retentionPolicy = RetentionPolicy.fromSettings(settings);
    return NetSpecter(
      settings: settings,
      storage: IsarNetSpecterStorage(
        retentionPolicy: retentionPolicy,
        directory: directory,
      ),
    );
  }

  Future<void> initialize() async {
    _initializationFuture ??= _performInitialization();
    await _initializationFuture;
  }

  Future<void> recordCall(HttpCall call) async {
    await initialize();
    queue.add(call);
    final next = queue.removeFirstOrNull();
    if (next == null) {
      return;
    }

    final processedCall = await PayloadProcessor.processCall(
      next,
      settings: settings,
    );
    await storage.saveCall(processedCall);
    await refreshCalls();
  }

  Future<void> refreshCalls({
    HttpCallFilter? filter,
  }) async {
    await initialize();
    _filter = filter ?? _filter;
    _offset = 0;
    _hasMore = true;
    _isLoading = true;
    notifyListeners();

    final nextPage = await storage.listCalls(
      filter: _filter,
      offset: _offset,
      limit: _defaultPageSize,
    );

    _calls = nextPage;
    _offset = nextPage.length;
    _hasMore = nextPage.length == _defaultPageSize;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    await initialize();
    if (_isLoading || !_hasMore) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    final nextPage = await storage.listCalls(
      filter: _filter,
      offset: _offset,
      limit: _defaultPageSize,
    );

    _calls = <HttpCall>[..._calls, ...nextPage];
    _offset += nextPage.length;
    _hasMore = nextPage.length == _defaultPageSize;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> clear() async {
    await initialize();
    queue.clear();
    await storage.clear();
    _calls = const <HttpCall>[];
    _offset = 0;
    _hasMore = false;
    notifyListeners();
  }

  Future<void> _performInitialization() async {
    await storage.initialize();

    final nextPage = await storage.listCalls(
      filter: _filter,
      offset: 0,
      limit: _defaultPageSize,
    );

    _calls = nextPage;
    _offset = nextPage.length;
    _hasMore = nextPage.length == _defaultPageSize;
    notifyListeners();
  }
}

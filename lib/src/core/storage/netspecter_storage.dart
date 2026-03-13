import '../models/http_call.dart';
import '../models/http_call_filter.dart';

abstract class NetSpecterStorage {
  Future<void> initialize() async {}

  Future<void> saveCall(HttpCall call);

  Future<List<HttpCall>> listCalls({
    HttpCallFilter filter = const HttpCallFilter(),
    int offset = 0,
    int limit = 50,
  });

  Future<void> clear();
}

class InMemoryNetSpecterStorage implements NetSpecterStorage {
  final List<HttpCall> _calls = <HttpCall>[];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> clear() async {
    _calls.clear();
  }

  @override
  Future<List<HttpCall>> listCalls({
    HttpCallFilter filter = const HttpCallFilter(),
    int offset = 0,
    int limit = 50,
  }) async {
    final filtered = _calls.reversed.where((call) {
      if (filter.method != null && filter.method!.isNotEmpty) {
        if (call.request.method.toLowerCase() != filter.method!.toLowerCase()) {
          return false;
        }
      }

      if (filter.statusCode != null &&
          call.response?.statusCode != filter.statusCode) {
        return false;
      }

      if (filter.host != null && filter.host!.trim().isNotEmpty) {
        if (!call.request.uri.host
            .toLowerCase()
            .contains(filter.host!.trim().toLowerCase())) {
          return false;
        }
      }

      if (filter.query != null && filter.query!.trim().isNotEmpty) {
        final query = filter.query!.trim().toLowerCase();
        final searchable = <String>[
          call.request.uri.toString(),
          call.request.body ?? '',
          call.response?.body ?? '',
          call.error?.message ?? '',
        ].join('\n').toLowerCase();

        if (!searchable.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList(growable: false);

    if (offset >= filtered.length) {
      return const <HttpCall>[];
    }

    final end = (offset + limit) > filtered.length
        ? filtered.length
        : offset + limit;
    return List<HttpCall>.unmodifiable(filtered.sublist(offset, end));
  }

  @override
  Future<void> saveCall(HttpCall call) async {
    _calls.add(call);
  }
}

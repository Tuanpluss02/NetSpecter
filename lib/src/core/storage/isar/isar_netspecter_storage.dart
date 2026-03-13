import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/http_call.dart';
import '../../models/http_call_filter.dart';
import '../../retention/retention_policy.dart';
import '../netspecter_storage.dart';
import 'stored_http_call.dart';

class IsarNetSpecterStorage implements NetSpecterStorage {
  IsarNetSpecterStorage({
    required this.retentionPolicy,
    this.directory,
  });

  final RetentionPolicy retentionPolicy;
  final String? directory;

  Isar? _isar;

  @override
  Future<void> initialize() async {
    if (_isar != null) {
      return;
    }

    final resolvedDirectory = directory ??
        (await getApplicationSupportDirectory()).path;

    _isar = await Isar.open(
      <CollectionSchema<dynamic>>[StoredHttpCallSchema],
      directory: resolvedDirectory,
      name: 'netspecter',
    );
  }

  @override
  Future<void> saveCall(HttpCall call) async {
    final isar = await _requireIsar();
    final stored = StoredHttpCall.fromModel(call);

    await isar.writeTxn(() async {
      await isar.storedHttpCalls.put(stored);
    });

    await _enforceRetention(isar);
  }

  @override
  Future<List<HttpCall>> listCalls({
    HttpCallFilter filter = const HttpCallFilter(),
    int offset = 0,
    int limit = 50,
  }) async {
    final isar = await _requireIsar();
    final method = filter.method?.trim();
    final host = filter.host?.trim();
    final textQuery = filter.query?.trim();

    final storedCalls = await isar.storedHttpCalls
        .filter()
        .optional(
          method != null && method.isNotEmpty,
          (query) => query.methodEqualTo(
            method!.toUpperCase(),
            caseSensitive: false,
          ),
        )
        .optional(
          filter.statusCode != null,
          (query) => query.statusCodeEqualTo(filter.statusCode),
        )
        .optional(
          host != null && host.isNotEmpty,
          (query) => query.hostContains(
            host!,
            caseSensitive: false,
          ),
        )
        .optional(
          textQuery != null && textQuery.isNotEmpty,
          (query) => query.group(
            (grouped) => grouped
                .urlContains(textQuery!, caseSensitive: false)
                .or()
                .requestBodyContains(textQuery, caseSensitive: false)
                .or()
                .responseBodyContains(textQuery, caseSensitive: false)
                .or()
                .errorMessageContains(textQuery, caseSensitive: false),
          ),
        )
        .sortByStartedAtDesc()
        .offset(offset)
        .limit(limit)
        .findAll();

    return storedCalls.map((call) => call.toModel()).toList(growable: false);
  }

  @override
  Future<void> clear() async {
    final isar = await _requireIsar();
    await isar.writeTxn(() async {
      await isar.storedHttpCalls.clear();
    });
  }

  Future<Isar> _requireIsar() async {
    await initialize();
    return _isar!;
  }

  Future<void> _enforceRetention(Isar isar) async {
    final cutoff = DateTime.now().subtract(
      Duration(days: retentionPolicy.retentionDays),
    );

    final storedCalls = await isar.storedHttpCalls.where().findAll();
    final expired = storedCalls
        .where((call) => call.startedAt.isBefore(cutoff))
        .toList(growable: false);

    if (expired.isNotEmpty) {
      await isar.writeTxn(() async {
        for (final call in expired) {
          await isar.storedHttpCalls.delete(call.isarId);
        }
      });
    }

    final remainingCalls = await isar.storedHttpCalls.where().findAll();
    remainingCalls.sort(
      (left, right) => left.startedAt.compareTo(right.startedAt),
    );

    var totalBytes = remainingCalls.fold<int>(
      0,
      (sum, call) => sum + call.approximateSizeBytes,
    );

    if (totalBytes <= retentionPolicy.maxStorageBytes) {
      return;
    }

    final idsToDelete = <Id>[];
    for (final call in remainingCalls) {
      if (totalBytes <= retentionPolicy.maxStorageBytes) {
        break;
      }
      idsToDelete.add(call.isarId);
      totalBytes -= call.approximateSizeBytes;
    }

    if (idsToDelete.isEmpty) {
      return;
    }

    await isar.writeTxn(() async {
      await isar.storedHttpCalls.deleteAll(idsToDelete);
    });
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'package:netspecter/netspecter.dart';
import 'package:netspecter/src/core/storage/netspecter_storage.dart';

void main() {
  test('bounded queue drops oldest items when full', () {
    final specter = NetSpecter(
      settings: const NetSpecterSettings(maxQueuedEvents: 2),
    );

    final call1 = _buildCall('1');
    final call2 = _buildCall('2');
    final call3 = _buildCall('3');

    specter.queue.add(call1);
    specter.queue.add(call2);
    specter.queue.add(call3);

    expect(specter.queue.length, 2);
    expect(specter.queue.droppedCount, 1);
    expect(specter.queue.removeFirstOrNull(), call2);
    expect(specter.queue.removeFirstOrNull(), call3);
  });

  test('in-memory storage paginates and filters calls', () async {
    final storage = InMemoryNetSpecterStorage();

    await storage.saveCall(_buildCall('1'));
    await storage.saveCall(_buildCall('2', method: 'POST'));
    await storage.saveCall(
      _buildCall(
        '3',
        host: 'api.example.com',
        statusCode: 503,
        responseBody: 'server down',
      ),
    );

    final firstPage = await storage.listCalls(limit: 2);
    expect(firstPage.length, 2);
    expect(firstPage.first.id, '3');

    final filtered = await storage.listCalls(
      filter: const HttpCallFilter(
        host: 'api.example.com',
        statusCode: 503,
        query: 'server down',
      ),
    );

    expect(filtered.length, 1);
    expect(filtered.first.id, '3');
  });

  test('default API uses shared singleton instance', () {
    final interceptor = NetSpecterDioInterceptor();
    final overlay = NetSpecterOverlay(
      specter: null,
      child: const SizedBox.shrink(),
    );

    expect(interceptor.netSpecter, same(NetSpecter.instance));
    expect(overlay.specter, same(NetSpecter.instance));
  });
}

HttpCall _buildCall(
  String id, {
  String method = 'GET',
  String host = 'example.com',
  int? statusCode = 200,
  String responseBody = 'ok',
}) {
  return HttpCall(
    id: id,
    startedAt: DateTime(2026, 1, 1),
    request: HttpRequestData(
      method: method,
      uri: Uri.parse('https://$host/$id'),
      headers: const <String, String>{},
    ),
    response: HttpResponseData(
      statusCode: statusCode,
      headers: const <String, String>{},
      body: responseBody,
      bodyBytes: responseBody.length,
      durationMs: 20,
    ),
  );
}

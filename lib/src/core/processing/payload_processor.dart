import 'dart:isolate';

import '../models/http_call.dart';
import '../models/http_request_data.dart';
import '../models/http_response_data.dart';
import '../models/net_specter_settings.dart';

class PayloadProcessor {
  const PayloadProcessor._();

  static Future<HttpCall> processCall(
    HttpCall call, {
    required NetSpecterSettings settings,
  }) async {
    final largestPayloadBytes = _largestPayloadBytes(call);
    if (!shouldUseBackgroundProcessing(
      payloadBytes: largestPayloadBytes,
      thresholdBytes: settings.isolateThresholdBytes,
    )) {
      return _normalizeCall(call, settings);
    }

    return Isolate.run<HttpCall>(() => _normalizeCall(call, settings));
  }

  static bool shouldUseBackgroundProcessing({
    required int payloadBytes,
    required int thresholdBytes,
  }) {
    return payloadBytes >= thresholdBytes;
  }

  static HttpCall _normalizeCall(
    HttpCall call,
    NetSpecterSettings settings,
  ) {
    return call.copyWith(
      request: _normalizeRequest(call.request, settings),
      response: call.response == null
          ? null
          : _normalizeResponse(call.response!, settings),
    );
  }

  static HttpRequestData _normalizeRequest(
    HttpRequestData request,
    NetSpecterSettings settings,
  ) {
    final normalizedBody = _truncateBody(
      request.body,
      maxChars: settings.maxBodyBytes,
      previewChars: settings.previewTruncationBytes,
    );

    return request.copyWith(
      body: normalizedBody,
      bodyBytes: normalizedBody?.length ?? 0,
    );
  }

  static HttpResponseData _normalizeResponse(
    HttpResponseData response,
    NetSpecterSettings settings,
  ) {
    final normalizedBody = _truncateBody(
      response.body,
      maxChars: settings.maxBodyBytes,
      previewChars: settings.previewTruncationBytes,
    );

    return response.copyWith(
      body: normalizedBody,
      bodyBytes: normalizedBody?.length ?? 0,
    );
  }

  static String? _truncateBody(
    String? body, {
    required int maxChars,
    required int previewChars,
  }) {
    if (body == null || body.isEmpty) {
      return body;
    }

    if (body.length <= maxChars) {
      return body;
    }

    final preview = buildPreview(body, maxChars: previewChars);
    return '$preview\n\n[truncated by NetSpecter]';
  }

  static String? buildPreview(
    String? body, {
    required int maxChars,
  }) {
    if (body == null || body.isEmpty) {
      return body;
    }
    if (body.length <= maxChars) {
      return body;
    }
    return '${body.substring(0, maxChars)}...';
  }

  static int _largestPayloadBytes(HttpCall call) {
    final requestBytes = call.request.bodyBytes;
    final responseBytes = call.response?.bodyBytes ?? 0;
    return requestBytes > responseBytes ? requestBytes : responseBytes;
  }
}

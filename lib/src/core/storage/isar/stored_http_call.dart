import 'dart:convert';

import 'package:isar/isar.dart';

import '../../models/http_call.dart';
import '../../models/http_error_data.dart';
import '../../models/http_request_data.dart';
import '../../models/http_response_data.dart';

part 'stored_http_call.g.dart';

@collection
class StoredHttpCall {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String callId;

  @Index()
  late DateTime startedAt;

  @Index()
  late String method;

  @Index()
  late String host;

  @Index()
  late String path;

  @Index()
  int? statusCode;

  @Index()
  late bool hasError;

  late String url;
  String? requestContentType;
  String? requestHeadersJson;
  String? requestBody;
  late int requestBodyBytes;
  String? responseContentType;
  String? responseHeadersJson;
  String? responseBody;
  late int responseBodyBytes;
  int? durationMs;
  String? errorType;
  String? errorMessage;
  late int approximateSizeBytes;

  HttpCall toModel() {
    return HttpCall(
      id: callId,
      startedAt: startedAt,
      request: HttpRequestData(
        method: method,
        uri: Uri.parse(url),
        headers: _decodeHeaders(requestHeadersJson),
        body: requestBody,
        bodyBytes: requestBodyBytes,
        contentType: requestContentType,
      ),
      response: statusCode == null &&
              responseHeadersJson == null &&
              responseBody == null &&
              durationMs == null
          ? null
          : HttpResponseData(
              statusCode: statusCode,
              headers: _decodeHeaders(responseHeadersJson),
              body: responseBody,
              bodyBytes: responseBodyBytes,
              contentType: responseContentType,
              durationMs: durationMs,
            ),
      error: errorType == null && errorMessage == null
          ? null
          : HttpErrorData(
              type: errorType ?? 'unknown',
              message: errorMessage ?? '',
            ),
    );
  }

  static StoredHttpCall fromModel(HttpCall call) {
    final stored = StoredHttpCall()
      ..callId = call.id
      ..startedAt = call.startedAt
      ..method = call.request.method
      ..host = call.request.uri.host
      ..path = call.request.uri.path
      ..statusCode = call.response?.statusCode
      ..hasError = call.hasError
      ..url = call.request.uri.toString()
      ..requestContentType = call.request.contentType
      ..requestHeadersJson = jsonEncode(call.request.headers)
      ..requestBody = call.request.body
      ..requestBodyBytes = call.request.bodyBytes
      ..responseContentType = call.response?.contentType
      ..responseHeadersJson = call.response == null
          ? null
          : jsonEncode(call.response!.headers)
      ..responseBody = call.response?.body
      ..responseBodyBytes = call.response?.bodyBytes ?? 0
      ..durationMs = call.response?.durationMs
      ..errorType = call.error?.type
      ..errorMessage = call.error?.message;

    stored.approximateSizeBytes = _approximateSize(
      requestHeadersJson: stored.requestHeadersJson,
      requestBody: stored.requestBody,
      responseHeadersJson: stored.responseHeadersJson,
      responseBody: stored.responseBody,
      errorMessage: stored.errorMessage,
    );
    return stored;
  }

  static Map<String, String> _decodeHeaders(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) {
      return const <String, String>{};
    }

    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    return decoded.map(
      (key, value) => MapEntry(key, value.toString()),
    );
  }

  static int _approximateSize({
    required String? requestHeadersJson,
    required String? requestBody,
    required String? responseHeadersJson,
    required String? responseBody,
    required String? errorMessage,
  }) {
    return (requestHeadersJson?.length ?? 0) +
        (requestBody?.length ?? 0) +
        (responseHeadersJson?.length ?? 0) +
        (responseBody?.length ?? 0) +
        (errorMessage?.length ?? 0);
  }
}

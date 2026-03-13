import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/models/http_call.dart';
import '../../core/models/http_error_data.dart';
import '../../core/models/http_request_data.dart';
import '../../core/models/http_response_data.dart';
import '../../core/netspecter_controller.dart';

class NetSpecterDioInterceptor extends Interceptor {
  NetSpecterDioInterceptor([
    NetSpecter? netSpecter,
  ]) : netSpecter = netSpecter ?? NetSpecter.instance;

  final NetSpecter netSpecter;

  static const String _startedAtKey = 'netspecter_started_at';
  static const String _requestIdKey = 'netspecter_request_id';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] = DateTime.now();
    options.extra[_requestIdKey] = _buildRequestId();
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    unawaited(
      netSpecter.recordCall(
        HttpCall(
          id: response.requestOptions.extra[_requestIdKey] as String? ?? _buildRequestId(),
          startedAt: response.requestOptions.extra[_startedAtKey] as DateTime? ?? DateTime.now(),
          request: _buildRequestData(response.requestOptions),
          response: _buildResponseData(response),
        ),
      ),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    unawaited(
      netSpecter.recordCall(
        HttpCall(
          id: err.requestOptions.extra[_requestIdKey] as String? ?? _buildRequestId(),
          startedAt: err.requestOptions.extra[_startedAtKey] as DateTime? ?? DateTime.now(),
          request: _buildRequestData(err.requestOptions),
          response: err.response != null ? _buildResponseData(err.response!) : null,
          error: HttpErrorData(
            type: err.type.name,
            message: err.message ?? err.error.toString(),
            stackTrace: err.stackTrace,
          ),
        ),
      ),
    );
    handler.next(err);
  }

  HttpRequestData _buildRequestData(RequestOptions options) {
    final body = _serializeBody(options.data);
    return HttpRequestData(
      method: options.method,
      uri: options.uri,
      headers: options.headers.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      body: body,
      bodyBytes: body?.length ?? 0,
      contentType: options.contentType,
    );
  }

  HttpResponseData _buildResponseData(Response<dynamic> response) {
    final body = _serializeBody(response.data);
    final startedAt = response.requestOptions.extra[_startedAtKey] as DateTime?;
    final durationMs = startedAt == null
        ? null
        : DateTime.now().difference(startedAt).inMilliseconds;

    return HttpResponseData(
      statusCode: response.statusCode,
      headers: response.headers.map.map(
        (key, value) => MapEntry(key, value.join(', ')),
      ),
      body: body,
      bodyBytes: body?.length ?? 0,
      contentType: response.headers.value(Headers.contentTypeHeader),
      durationMs: durationMs,
    );
  }

  String _buildRequestId() => DateTime.now().microsecondsSinceEpoch.toString();

  String? _serializeBody(Object? data) {
    if (data == null) {
      return null;
    }
    if (data is String) {
      return data;
    }
    return data.toString();
  }
}

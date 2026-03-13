import 'http_error_data.dart';
import 'http_request_data.dart';
import 'http_response_data.dart';

class HttpCall {
  const HttpCall({
    required this.id,
    required this.startedAt,
    required this.request,
    this.response,
    this.error,
  });

  final String id;
  final DateTime startedAt;
  final HttpRequestData request;
  final HttpResponseData? response;
  final HttpErrorData? error;

  bool get hasError => error != null;

  HttpCall copyWith({
    String? id,
    DateTime? startedAt,
    HttpRequestData? request,
    HttpResponseData? response,
    HttpErrorData? error,
  }) {
    return HttpCall(
      id: id ?? this.id,
      startedAt: startedAt ?? this.startedAt,
      request: request ?? this.request,
      response: response ?? this.response,
      error: error ?? this.error,
    );
  }
}

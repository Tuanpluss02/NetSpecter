import '../core/models/http_call.dart';

class CurlGenerator {
  const CurlGenerator._();

  static String fromCall(HttpCall call) {
    final buffer = StringBuffer('curl');

    buffer.write(" -X ${call.request.method}");

    for (final entry in call.request.headers.entries) {
      buffer.write(" -H '${entry.key}: ${entry.value}'");
    }

    if (call.request.body != null && call.request.body!.isNotEmpty) {
      buffer.write(" --data '${call.request.body}'");
    }

    buffer.write(" '${call.request.uri}'");
    return buffer.toString();
  }
}

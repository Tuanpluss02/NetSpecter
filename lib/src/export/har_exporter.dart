import '../core/models/http_call.dart';

class HarExporter {
  const HarExporter._();

  static Map<String, Object?> fromCalls(List<HttpCall> calls) {
    return <String, Object?>{
      'log': <String, Object?>{
        'version': '1.2',
        'creator': <String, Object?>{
          'name': 'NetSpecter',
          'version': '0.0.1',
        },
        'entries': calls
            .map(
              (call) => <String, Object?>{
                'startedDateTime': call.startedAt.toIso8601String(),
                'request': <String, Object?>{
                  'method': call.request.method,
                  'url': call.request.uri.toString(),
                  'headers': call.request.headers.entries
                      .map(
                        (entry) => <String, String>{
                          'name': entry.key,
                          'value': entry.value,
                        },
                      )
                      .toList(),
                },
                'response': <String, Object?>{
                  'status': call.response?.statusCode ?? 0,
                  'content': <String, Object?>{
                    'text': call.response?.body ?? '',
                  },
                },
              },
            )
            .toList(),
      },
    };
  }
}

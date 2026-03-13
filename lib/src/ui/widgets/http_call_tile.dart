import 'package:flutter/material.dart';

import '../../core/models/http_call.dart';

class HttpCallTile extends StatelessWidget {
  const HttpCallTile({
    super.key,
    required this.call,
    this.onTap,
  });

  final HttpCall call;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final statusCode = call.response?.statusCode;
    final statusText = statusCode?.toString() ?? (call.hasError ? 'ERR' : '--');

    return ListTile(
      onTap: onTap,
      title: Text('${call.request.method} ${call.request.uri}'),
      subtitle: Text('Status: $statusText'),
      trailing: call.response?.durationMs == null
          ? null
          : Text('${call.response!.durationMs} ms'),
    );
  }
}

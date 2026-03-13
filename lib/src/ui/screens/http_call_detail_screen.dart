import 'package:flutter/material.dart';

import '../../core/models/http_call.dart';

class HttpCallDetailScreen extends StatelessWidget {
  const HttpCallDetailScreen({
    super.key,
    required this.call,
  });

  final HttpCall call;

  @override
  Widget build(BuildContext context) {
    final response = call.response;
    final error = call.error;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${call.request.method} ${call.request.uri.host}'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Overview'),
              Tab(text: 'Request'),
              Tab(text: 'Response'),
              Tab(text: 'Error'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _DetailSection(
              children: <Widget>[
                _DetailRow(label: 'Method', value: call.request.method),
                _DetailRow(label: 'URL', value: call.request.uri.toString()),
                _DetailRow(
                  label: 'Status',
                  value: response?.statusCode?.toString() ?? 'N/A',
                ),
                _DetailRow(
                  label: 'Duration',
                  value: response?.durationMs == null
                      ? 'N/A'
                      : '${response!.durationMs} ms',
                ),
                _DetailRow(label: 'Has error', value: call.hasError.toString()),
              ],
            ),
            _DetailSection(
              children: <Widget>[
                _DetailRow(
                  label: 'Headers',
                  value: _formatMap(call.request.headers),
                ),
                _DetailRow(
                  label: 'Body',
                  value: call.request.body ?? '(empty)',
                ),
              ],
            ),
            _DetailSection(
              children: <Widget>[
                _DetailRow(
                  label: 'Headers',
                  value: _formatMap(response?.headers ?? const <String, String>{}),
                ),
                _DetailRow(
                  label: 'Body',
                  value: response?.body ?? '(empty)',
                ),
              ],
            ),
            _DetailSection(
              children: <Widget>[
                _DetailRow(
                  label: 'Type',
                  value: error?.type ?? 'No error',
                ),
                _DetailRow(
                  label: 'Message',
                  value: error?.message ?? 'No error',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatMap(Map<String, String> value) {
    if (value.isEmpty) {
      return '(empty)';
    }
    return value.entries.map((entry) => '${entry.key}: ${entry.value}').join('\n');
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) => children[index],
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemCount: children.length,
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    );
  }
}

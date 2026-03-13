import 'package:flutter/material.dart';

import '../../core/models/http_call.dart';
import '../../core/models/http_call_filter.dart';
import '../../core/netspecter_controller.dart';
import '../widgets/http_call_tile.dart';
import 'http_call_detail_screen.dart';
import 'netspecter_settings_screen.dart';

class NetSpecterScreen extends StatefulWidget {
  const NetSpecterScreen({
    super.key,
    required this.specter,
  });

  final NetSpecter specter;

  @override
  State<NetSpecterScreen> createState() => _NetSpecterScreenState();
}

class _NetSpecterScreenState extends State<NetSpecterScreen> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _selectedMethod;
  String? _selectedStatus;

  NetSpecter get specter => widget.specter;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _queryController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    final threshold = _scrollController.position.maxScrollExtent - 240;
    if (_scrollController.position.pixels >= threshold) {
      specter.loadMore();
    }
  }

  Future<void> _applyFilters() {
    return specter.refreshCalls(
      filter: HttpCallFilter(
        method: _selectedMethod,
        statusCode: _selectedStatus == null ? null : int.tryParse(_selectedStatus!),
        host: _hostController.text.trim().isEmpty ? null : _hostController.text.trim(),
        query: _queryController.text.trim().isEmpty ? null : _queryController.text.trim(),
      ),
    );
  }

  Future<void> _clearFilters() async {
    _hostController.clear();
    _queryController.clear();
    setState(() {
      _selectedMethod = null;
      _selectedStatus = null;
    });
    await specter.refreshCalls(filter: const HttpCallFilter());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.specter,
      builder: (context, _) {
        final calls = specter.calls;

        return Scaffold(
          appBar: AppBar(
            title: const Text('NetSpecter'),
            actions: <Widget>[
              IconButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NetSpecterSettingsScreen(
                        specter: specter,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.settings_outlined),
              ),
              IconButton(
                onPressed: () async {
                  await specter.clear();
                  if (mounted) {
                    await _clearFilters();
                  }
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              _FilterBar(
                hostController: _hostController,
                queryController: _queryController,
                selectedMethod: _selectedMethod,
                selectedStatus: _selectedStatus,
                onMethodChanged: (value) {
                  setState(() {
                    _selectedMethod = value;
                  });
                },
                onStatusChanged: (value) {
                  setState(() {
                    _selectedStatus = value;
                  });
                },
                onApply: _applyFilters,
                onClear: _clearFilters,
              ),
              Expanded(
                child: calls.isEmpty && !specter.isLoading
                    ? const Center(
                        child: Text('No captured requests yet.'),
                      )
                    : RefreshIndicator(
                        onRefresh: () => specter.refreshCalls(),
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: calls.length + 1,
                          itemBuilder: (context, index) {
                            if (index >= calls.length) {
                              if (specter.isLoading) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              if (!specter.hasMore) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: Text('End of captured requests.'),
                                  ),
                                );
                              }

                              return const SizedBox.shrink();
                            }

                            final call = calls[index];
                            return HttpCallTile(
                              call: call,
                              onTap: () => _openCall(context, call),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openCall(BuildContext context, HttpCall call) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HttpCallDetailScreen(call: call),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.hostController,
    required this.queryController,
    required this.selectedMethod,
    required this.selectedStatus,
    required this.onMethodChanged,
    required this.onStatusChanged,
    required this.onApply,
    required this.onClear,
  });

  final TextEditingController hostController;
  final TextEditingController queryController;
  final String? selectedMethod;
  final String? selectedStatus;
  final ValueChanged<String?> onMethodChanged;
  final ValueChanged<String?> onStatusChanged;
  final Future<void> Function() onApply;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            TextField(
              controller: hostController,
              decoration: const InputDecoration(
                labelText: 'Host filter',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: queryController,
              decoration: const InputDecoration(
                labelText: 'Text query',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedMethod,
                    decoration: const InputDecoration(
                      labelText: 'Method',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(value: 'GET', child: Text('GET')),
                      DropdownMenuItem<String>(value: 'POST', child: Text('POST')),
                      DropdownMenuItem<String>(value: 'PUT', child: Text('PUT')),
                      DropdownMenuItem<String>(value: 'PATCH', child: Text('PATCH')),
                      DropdownMenuItem<String>(value: 'DELETE', child: Text('DELETE')),
                    ],
                    onChanged: onMethodChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(value: '200', child: Text('200')),
                      DropdownMenuItem<String>(value: '201', child: Text('201')),
                      DropdownMenuItem<String>(value: '400', child: Text('400')),
                      DropdownMenuItem<String>(value: '401', child: Text('401')),
                      DropdownMenuItem<String>(value: '404', child: Text('404')),
                      DropdownMenuItem<String>(value: '500', child: Text('500')),
                      DropdownMenuItem<String>(value: '503', child: Text('503')),
                    ],
                    onChanged: onStatusChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton(
                    onPressed: onApply,
                    child: const Text('Apply Filters'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onClear,
                    child: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

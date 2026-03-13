import 'package:flutter/material.dart';

import '../../model/index_entry.dart';
import '../../storage/inspector_session.dart';
import '../widgets/http_call_tile.dart';
import 'http_call_detail_screen.dart';
import 'netspecter_settings_screen.dart';

class NetSpecterScreen extends StatefulWidget {
  const NetSpecterScreen({
    super.key,
    required this.session,
  });

  final InspectorSession session;

  @override
  State<NetSpecterScreen> createState() => _NetSpecterScreenState();
}

class _NetSpecterScreenState extends State<NetSpecterScreen> {
  final TextEditingController _searchController = TextEditingController();

  InspectorSession get session => widget.session;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NetSpecterSettingsScreen(session: session),
      ),
    );
  }

  Future<void> _clearAll() async {
    await session.clear();
    if (mounted) {
      _searchController.clear();
    }
  }

  void _onSearchSubmitted(String value) {
    session.startMasterSearch(value);
  }

  void _onClearSearch() {
    _searchController.clear();
    session.cancelMasterSearch();
  }

  void _openEntry(BuildContext context, IndexEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HttpCallDetailScreen(entry: entry, session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NetSpecter'),
        actions: <Widget>[
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _SearchBar(
            controller: _searchController,
            session: session,
            onSubmitted: _onSearchSubmitted,
            onClear: _onClearSearch,
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: session,
              builder: (context, _) {
                final entries = session.entries;

                if (entries.isEmpty) {
                  return const Center(
                    child: Text('No captured requests yet.'),
                  );
                }

                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return HttpCallTile(
                      key: ValueKey(entry.id),
                      entry: entry,
                      onTap: () => _openEntry(context, entry),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.session,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final InspectorSession session;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: controller,
              onSubmitted: onSubmitted,
              decoration: InputDecoration(
                labelText: 'Search URL, headers, body, response…',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (session.isScanningBodies || session.isScanningFiles)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear search',
                      onPressed: onClear,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            if (session.masterQuery != null)
              Text(
                'Searching for: "${session.masterQuery}"'
                '${session.isScanningFiles ? ' (including large bodies...)' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

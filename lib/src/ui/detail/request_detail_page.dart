import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:netspecter/src/ui/netspecter_theme.dart';
import 'package:netspecter/src/ui/widgets/json_viewer.dart';

import '../../model/index_entry.dart';
import '../../model/request_record.dart';
import '../../storage/inspector_session.dart';

class RequestDetailPage extends StatefulWidget {
  final IndexEntry entry;
  final InspectorSession session;

  const RequestDetailPage({
    super.key,
    required this.entry,
    required this.session,
  });

  @override
  State<RequestDetailPage> createState() => _RequestDetailPageState();
}

class _RequestDetailPageState extends State<RequestDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  late Future<RequestRecord> _recordFuture;

  String _query = '';
  int _currentMatchIndex = 0;

  // Cached data
  RequestRecord? _cachedRecord;
  List<_DetailMatch> _cachedMatches = const [];
  String _cachedQuery = '';

  // Track which tabs have been visited (for lazy building)
  final Set<int> _visitedTabs = {0};

  @override
  void initState() {
    super.initState();
    _recordFuture = widget.session.loadDetail(widget.entry);
    _recordFuture.then((record) {
      if (mounted) {
        setState(() {
          _cachedRecord = record;
          _recomputeMatches();
        });
        // Pre-build remaining tabs on the next frame after initial render
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              for (int i = 0; i < _tabController.length; i++) {
                _visitedTabs.add(i);
              }
            });
          }
        });
      }
    });
    final isWs = widget.entry.method == 'WS';
    _tabController = TabController(length: isWs ? 2 : 4, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final idx = _tabController.index;
      if (!_visitedTabs.contains(idx)) {
        setState(() {
          _visitedTabs.add(idx);
        });
      }
    }
  }

  void _recomputeMatches() {
    final record = _cachedRecord;
    if (record == null) {
      _cachedMatches = const [];
      return;
    }
    final isWs = widget.entry.method == 'WS';
    _cachedMatches = _computeMatches(record, _query, isWs, _tryParseJson);
    _cachedQuery = _query;
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  dynamic _tryParseJson(String? content) {
    if (content == null || content.isEmpty) return content;
    try {
      return jsonDecode(content);
    } catch (_) {
      return content;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final isWs = entry.method == 'WS';
    final sStyle = NetSpecterTheme.getStatusStyle(entry.statusCode);

    String displayUrl = entry.url;
    if (widget.session.urlDecodeEnabled) {
      try {
        displayUrl = Uri.decodeFull(entry.url);
      } catch (_) {}
    }

    final path = Uri.tryParse(displayUrl)?.path ?? displayUrl;

    return Scaffold(
      backgroundColor: NetSpecterTheme.surface,
      appBar: AppBar(
        backgroundColor: NetSpecterTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: NetSpecterTheme.textSecondary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          path,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            color: NetSpecterTheme.textPrimary,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16.0),
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: sStyle.bg,
              borderRadius: BorderRadius.circular(4.0),
            ),
            alignment: Alignment.center,
            child: Text(
              '${entry.statusCode} ${entry.statusCode == 200 ? 'OK' : ''}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: sStyle.text,
              ),
            ),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final record = _cachedRecord;
          if (record == null) {
            return const Center(
              child:
                  CircularProgressIndicator(color: NetSpecterTheme.indigo500),
            );
          }

          // Recompute matches only if query changed
          if (_cachedQuery != _query) {
            _recomputeMatches();
          }

          final matches = _cachedMatches;
          final totalMatches = matches.length;

          int effectiveIndex = _currentMatchIndex;
          if (totalMatches > 0) {
            effectiveIndex %= totalMatches;
            if (effectiveIndex < 0) {
              effectiveIndex += totalMatches;
            }
          } else {
            effectiveIndex = 0;
          }

          final activeGlobalIndex = totalMatches == 0 ? null : effectiveIndex;
          final activeMatch =
              totalMatches == 0 ? null : matches[effectiveIndex];

          if (activeMatch != null &&
              _tabController.index != activeMatch.tabIndex &&
              _tabController.length > activeMatch.tabIndex) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _tabController.animateTo(activeMatch.tabIndex);
              }
            });
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Detail Search Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                decoration: BoxDecoration(
                  color: NetSpecterTheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (value) {
                          setState(() {
                            _query = value.trim();
                            _currentMatchIndex = 0;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search in details...',
                          hintStyle: const TextStyle(
                            color: NetSpecterTheme.textMuted,
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: NetSpecterTheme.textMuted,
                            size: 20,
                          ),
                          filled: true,
                          fillColor: NetSpecterTheme.surfaceContainer,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12.0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30.0),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30.0),
                            borderSide: const BorderSide(
                              color: NetSpecterTheme.indigo500,
                              width: 1.0,
                            ),
                          ),
                        ),
                        style: const TextStyle(
                          color: NetSpecterTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      totalMatches == 0
                          ? '0 / 0'
                          : '${effectiveIndex + 1} / $totalMatches',
                      style: const TextStyle(
                        fontSize: 12,
                        color: NetSpecterTheme.textMuted,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_arrow_up,
                        size: 20,
                        color: NetSpecterTheme.textMuted,
                      ),
                      tooltip: 'Previous match',
                      onPressed: totalMatches == 0
                          ? null
                          : () {
                              setState(() {
                                _currentMatchIndex--;
                              });
                            },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 20,
                        color: NetSpecterTheme.textMuted,
                      ),
                      tooltip: 'Next match',
                      onPressed: totalMatches == 0
                          ? null
                          : () {
                              setState(() {
                                _currentMatchIndex++;
                              });
                            },
                    ),
                  ],
                ),
              ),
              // TabBar
              TabBar(
                controller: _tabController,
                indicatorColor: NetSpecterTheme.indigo500,
                labelColor: NetSpecterTheme.indigo400,
                unselectedLabelColor: NetSpecterTheme.textQuaternary,
                dividerColor: Colors.transparent,
                tabs: isWs
                    ? const [
                        Tab(text: 'Overview'),
                        Tab(text: 'Messages'),
                      ]
                    : const [
                        Tab(text: 'Overview'),
                        Tab(text: 'Request'),
                        Tab(text: 'Response'),
                        Tab(text: 'Messages'),
                      ],
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) {
                    final tabIndex = _tabController.index;
                    return IndexedStack(
                      index: tabIndex,
                      children: isWs
                          ? [
                              _visitedTabs.contains(0)
                                  ? _buildOverviewTab(
                                      record, matches, activeGlobalIndex)
                                  : const SizedBox.shrink(),
                              _visitedTabs.contains(1)
                                  ? _buildMessagesTab(record)
                                  : const SizedBox.shrink(),
                            ]
                          : [
                              _visitedTabs.contains(0)
                                  ? _buildOverviewTab(
                                      record, matches, activeGlobalIndex)
                                  : const SizedBox.shrink(),
                              _visitedTabs.contains(1)
                                  ? _buildRequestTab(
                                      record, matches, activeGlobalIndex)
                                  : const SizedBox.shrink(),
                              _visitedTabs.contains(2)
                                  ? _buildResponseTab(
                                      record, matches, activeGlobalIndex)
                                  : const SizedBox.shrink(),
                              _visitedTabs.contains(3)
                                  ? _buildErrorTab(
                                      record, matches, activeGlobalIndex)
                                  : const SizedBox.shrink(),
                            ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }


  Widget _buildOverviewTab(RequestRecord record, List<_DetailMatch> matches,
      int? activeGlobalIndex) {
    final mStyle = NetSpecterTheme.getMethodStyle(record.method);

    String displayUrl = record.url;
    if (widget.session.urlDecodeEnabled) {
      try {
        displayUrl = Uri.decodeFull(record.url);
      } catch (_) {}
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildOverviewRow('URL', displayUrl, _DetailSection.overviewUrl,
            matches, activeGlobalIndex),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Method',
          record.method,
          _DetailSection.overviewMethod,
          matches,
          activeGlobalIndex,
          valueStyle: TextStyle(
            color: mStyle.text,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Status',
          '${record.statusCode}',
          _DetailSection.overviewStatus,
          matches,
          activeGlobalIndex,
        ),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Duration',
          '${record.durationMs} ms',
          _DetailSection.overviewDuration,
          matches,
          activeGlobalIndex,
        ),
        const SizedBox(height: 16),
        _buildOverviewRow(
          'Time',
          record.timestamp.toIso8601String(),
          _DetailSection.overviewTime,
          matches,
          activeGlobalIndex,
        ),
        if (record.isBodyTruncated) ...[
          const SizedBox(height: 16),
          _buildOverviewRow(
            'Note',
            'Body truncated — response exceeded the size limit.',
            _DetailSection.overviewNote,
            matches,
            activeGlobalIndex,
            valueStyle: const TextStyle(
              color: NetSpecterTheme.yellow400,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOverviewRow(
    String label,
    String value,
    _DetailSection section,
    List<_DetailMatch> matches,
    int? activeGlobalIndex, {
    TextStyle? valueStyle,
  }) {
    int matchOffset = matches.indexWhere((m) => m.section == section);
    if (matchOffset < 0) matchOffset = 0;
    final sectionMatchCount = matches.where((m) => m.section == section).length;

    final highlight = activeGlobalIndex != null &&
        activeGlobalIndex >= matchOffset &&
        activeGlobalIndex < matchOffset + sectionMatchCount;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: NetSpecterTheme.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: (valueStyle ??
                    const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: NetSpecterTheme.textSecondary,
                    ))
                .copyWith(
              backgroundColor: highlight ? const Color(0x40FFF59D) : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestTab(RequestRecord record, List<_DetailMatch> matches,
      int? activeGlobalIndex) {
    final uri = Uri.tryParse(record.url);
    final hasQueryParams = uri != null && uri.queryParameters.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Request Headers'),
        _buildJsonBox(
          record.requestHeaders,
          _DetailSection.requestHeaders,
          matches,
          activeGlobalIndex,
        ),
        const SizedBox(height: 24),
        if (hasQueryParams) ...[
          _buildSectionHeader('Query Parameters'),
          _buildJsonBox(
            uri.queryParameters,
            _DetailSection.queryParams,
            matches,
            activeGlobalIndex,
          ),
          const SizedBox(height: 24),
        ],
        _buildSectionHeader('Request Body', color: NetSpecterTheme.indigo400),
        _buildJsonBox(
          _tryParseJson(record.requestBodyPreview),
          _DetailSection.requestBody,
          matches,
          activeGlobalIndex,
        ),
      ],
    );
  }

  Widget _buildResponseTab(RequestRecord record, List<_DetailMatch> matches,
      int? activeGlobalIndex) {
    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Response Headers'),
        _buildJsonBox(
          record.responseHeaders,
          _DetailSection.responseHeaders,
          matches,
          activeGlobalIndex,
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Response Body', color: NetSpecterTheme.green400),
        _buildJsonBox(
          _tryParseJson(record.responseBodyPreview),
          _DetailSection.responseBody,
          matches,
          activeGlobalIndex,
        ),
      ],
    );
  }

  Widget _buildErrorTab(RequestRecord record, List<_DetailMatch> matches,
      int? activeGlobalIndex) {
    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Error Type', color: NetSpecterTheme.yellow400),
        _buildJsonBox(
          record.errorType ?? 'None',
          _DetailSection.errorType,
          matches,
          activeGlobalIndex,
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('Error Message', color: NetSpecterTheme.yellow400),
        _buildJsonBox(
          record.errorMessage ?? 'None',
          _DetailSection.errorMessage,
          matches,
          activeGlobalIndex,
        ),
      ],
    );
  }

  Widget _buildMessagesTab(RequestRecord record) {
    // Note: If WebSockets messages are not captured by RequestRecord, this will simply say no messages
    final messages = [];

    if (messages.isEmpty) {
      return const Center(
          child: Text('No WebSocket messages captured.',
              style: TextStyle(color: NetSpecterTheme.textMuted)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CONNECTION FRAMES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: NetSpecterTheme.purple400,
                    letterSpacing: 1.0,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: NetSpecterTheme.green500.withValues(alpha: 0.1),
                    border: Border.all(
                        color: NetSpecterTheme.green500.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: const Text(
                    'Live',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: NetSpecterTheme.green400,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final msg = messages[index - 1];
        final isOut = msg['type'] == 'out';
        final iconColor =
            isOut ? NetSpecterTheme.green400 : NetSpecterTheme.blue400;
        final icon = isOut ? Icons.call_made : Icons.call_received;
        final bgColor = isOut
            ? NetSpecterTheme.green500.withValues(alpha: 0.1)
            : NetSpecterTheme.blue500.withValues(alpha: 0.1);
        final label = isOut ? 'SENT' : 'RECV';

        return Container(
          margin: const EdgeInsets.only(bottom: 12.0),
          decoration: BoxDecoration(
            color: NetSpecterTheme.surfaceContainer,
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: bgColor,
                  border: Border(
                    bottom:
                        BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: iconColor, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: iconColor,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      msg['time'],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: NetSpecterTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: JsonViewer(
                  data: msg['data'],
                  searchQuery: _query.isEmpty ? null : _query,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color ?? NetSpecterTheme.textMuted,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildJsonBox(
    dynamic data,
    _DetailSection section,
    List<_DetailMatch> matches,
    int? activeGlobalIndex,
  ) {
    int matchOffset = matches.indexWhere((m) => m.section == section);
    if (matchOffset < 0) matchOffset = 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: NetSpecterTheme.surfaceContainer,
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: JsonViewer(
        data: data,
        searchQuery: _query.isEmpty ? null : _query,
        matchOffset: matchOffset,
        activeGlobalIndex: activeGlobalIndex,
      ),
    );
  }
}

class _DetailMatch {
  const _DetailMatch({required this.tabIndex, required this.section});
  final int tabIndex;
  final _DetailSection section;
}

enum _DetailSection {
  overviewUrl,
  overviewMethod,
  overviewStatus,
  overviewDuration,
  overviewTime,
  overviewNote,
  queryParams,
  requestHeaders,
  requestBody,
  responseHeaders,
  responseBody,
  errorType,
  errorMessage,
}

List<_DetailMatch> _computeMatches(
  RequestRecord record,
  String query,
  bool isWs,
  dynamic Function(String?) tryParseJson,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  final matches = <_DetailMatch>[];

  int countOccurrences(String? text) {
    if (text == null || text.isEmpty) return 0;
    int c = 0;
    int start = 0;
    final lower = text.toLowerCase();
    while (true) {
      final idx = lower.indexOf(q, start);
      if (idx < 0) break;
      c++;
      start = idx + q.length;
    }
    return c;
  }

  void addMatches(int count, int tabIndex, _DetailSection section) {
    for (int i = 0; i < count; i++) {
      matches.add(_DetailMatch(tabIndex: tabIndex, section: section));
    }
  }

  // Overview
  addMatches(countOccurrences(record.url), 0, _DetailSection.overviewUrl);
  addMatches(countOccurrences(record.method), 0, _DetailSection.overviewMethod);
  addMatches(
    countOccurrences(
        record.statusCode > 0 ? record.statusCode.toString() : 'N/A'),
    0,
    _DetailSection.overviewStatus,
  );
  addMatches(
    countOccurrences('${record.durationMs} ms'),
    0,
    _DetailSection.overviewDuration,
  );
  addMatches(
    countOccurrences(record.timestamp.toIso8601String()),
    0,
    _DetailSection.overviewTime,
  );
  if (record.isBodyTruncated) {
    addMatches(
      countOccurrences('Body truncated — response exceeded the size limit.'),
      0,
      _DetailSection.overviewNote,
    );
  }

  if (!isWs) {
    // Request tab index 1
    final uri = Uri.tryParse(record.url);
    if (uri != null && uri.queryParameters.isNotEmpty) {
      addMatches(JsonViewer.countMatches(uri.queryParameters, query), 1,
          _DetailSection.queryParams);
    }
    addMatches(
      JsonViewer.countMatches(record.requestHeaders, query),
      1,
      _DetailSection.requestHeaders,
    );
    addMatches(
      JsonViewer.countMatches(tryParseJson(record.requestBodyPreview), query),
      1,
      _DetailSection.requestBody,
    );

    // Response tab index 2
    addMatches(
      JsonViewer.countMatches(record.responseHeaders, query),
      2,
      _DetailSection.responseHeaders,
    );
    addMatches(
      JsonViewer.countMatches(tryParseJson(record.responseBodyPreview), query),
      2,
      _DetailSection.responseBody,
    );

    // Error tab index 3
    addMatches(
      JsonViewer.countMatches(record.errorType ?? 'None', query),
      3,
      _DetailSection.errorType,
    );
    addMatches(
      JsonViewer.countMatches(record.errorMessage ?? 'None', query),
      3,
      _DetailSection.errorMessage,
    );
  }

  return matches;
}


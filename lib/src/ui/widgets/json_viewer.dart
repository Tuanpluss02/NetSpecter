import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import 'toast_notification.dart';

/// Collapsible JSON renderer with search highlighting and copy support.
class JsonViewer extends StatefulWidget {
  /// JSON-like data (Map/List/scalars/String) to render.
  final dynamic data;

  /// Optional search term to highlight in rendered nodes.
  final String? searchQuery;

  /// Global match index offset for coordinated tab search navigation.
  final int matchOffset;

  /// Active global match index currently selected by parent UI.
  final int? activeGlobalIndex;

  /// Creates a JSON viewer for [data] with optional search metadata.
  const JsonViewer({
    super.key,
    required this.data,
    this.searchQuery,
    this.matchOffset = 0,
    this.activeGlobalIndex,
  });

  /// Format any data into a pretty-printed JSON string.
  /// Used by _computeMatches in request_detail_page.dart for search counting.
  static String formatData(dynamic data) {
    if (data == null) return 'null';
    try {
      if (data is String) {
        try {
          final decoded = jsonDecode(data);
          return const JsonEncoder.withIndent('  ').convert(decoded);
        } catch (_) {
          return data;
        }
      } else {
        return const JsonEncoder.withIndent('  ').convert(data);
      }
    } catch (e) {
      return data.toString();
    }
  }

  /// Counts case-insensitive query matches within structured JSON data.
  static int countMatches(dynamic data, String query) {
    if (query.isEmpty) return 0;
    final q = query.toLowerCase();

    if (data == null) return _countIn('null', q);
    if (data is bool) return _countIn(data.toString(), q);
    if (data is num) return _countIn(data.toString(), q);
    if (data is String) {
      return _countIn(data, q);
    }
    if (data is List) {
      int total = 0;
      for (final item in data) {
        total += countMatches(item, query);
      }
      return total;
    }
    if (data is Map) {
      int total = 0;
      for (final entry in data.entries) {
        total += _countIn(entry.key.toString(), q);
        total += countMatches(entry.value, query);
      }
      return total;
    }
    return _countIn(data.toString(), q);
  }

  static int _countIn(String text, String lowerQuery) {
    int count = 0;
    int start = 0;
    final lower = text.toLowerCase();
    while (true) {
      final idx = lower.indexOf(lowerQuery, start);
      if (idx < 0) break;
      count++;
      start = idx + lowerQuery.length;
    }
    return count;
  }

  /// Build highlighted [TextSpan] list for [text], marking query matches.
  ///
  /// [matchOffset] is the global index of the first match within [text].
  /// [activeGlobalIndex] is the currently selected match (painted orange).
  static List<TextSpan> buildHighlightedSpans(
    String text,
    String lowerQuery,
    int matchOffset,
    int? activeGlobalIndex,
    Color baseColor,
  ) {
    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    int start = 0;
    int currentMatch = matchOffset;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) {
        if (start < text.length) {
          spans.add(
            TextSpan(
              text: text.substring(start),
              style: TextStyle(color: baseColor),
            ),
          );
        }
        break;
      }

      if (index > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, index),
            style: TextStyle(color: baseColor),
          ),
        );
      }

      final isActive = currentMatch == activeGlobalIndex;
      currentMatch++;

      spans.add(
        TextSpan(
          text: text.substring(index, index + lowerQuery.length),
          style: TextStyle(
            color: baseColor,
            backgroundColor: isActive
                ? _JsonViewerState._activeHighlightColor
                : _JsonViewerState._highlightColor,
          ),
        ),
      );

      start = index + lowerQuery.length;
    }

    return spans;
  }

  @override
  State<JsonViewer> createState() => _JsonViewerState();
}

class _JsonViewerState extends State<JsonViewer> {
  static const _keyColor = InterceptlyGlobalColor.blue400;
  static const _stringColor = InterceptlyGlobalColor.red400;
  static const _numberColor = InterceptlyGlobalColor.green400;
  static const _boolColor = InterceptlyGlobalColor.blue500;
  static const _nullColor = InterceptlyGlobalColor.blue500;
  static const _punctuationColor = InterceptlyGlobalColor.textQuaternary;
  static const _highlightColor = InterceptlyGlobalColor.highlightStrong;
  static const _activeHighlightColor = InterceptlyGlobalColor.orange;

  /// Cached subtree-match counts per node path, keyed by node instance.
  /// Avoids re-walking the tree on every didUpdateWidget.
  final Map<int, int> _subtreeMatchCache = <int, int>{};

  /// Stable IDs assigned to each _JsonNode instance in build order. Used as
  /// cache key so reordering children doesn't poison the cache.
  int _nextNodeId = 1;

  void _copyToClipboard() {
    final formatted = JsonViewer.formatData(widget.data);
    Clipboard.setData(ClipboardData(text: formatted)).then((_) {
      if (mounted) {
        ToastNotification.show('Copied to clipboard', contextHint: context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data == null) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          'No Data',
          style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
            fontStyle: FontStyle.italic,
            color: InterceptlyTheme.textMuted,
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SelectionArea(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DefaultTextStyle(
                style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                  fontFamilyFallback: ['monospace'],
                  fontSize: 12,
                  height: 1.5,
                ),
                child: _JsonNode(
                  nodeKey: null,
                  value: widget.data,
                  isLast: true,
                  root: true,
                  searchQuery: widget.searchQuery,
                  matchOffset: widget.matchOffset,
                  activeGlobalIndex: widget.activeGlobalIndex,
                  subtreeMatchCache: _subtreeMatchCache,
                  nodeId: _nextNodeId++,
                  nextNodeId: () => _nextNodeId++,
                ),
              ),
            ),
          ),
          Positioned(
            top: -10,
            right: -10,
            child: Material(
              color: InterceptlyGlobalColor.transparent,
              child: IconButton(
                icon: const Icon(
                  Icons.copy,
                  size: 16,
                  color: InterceptlyTheme.textMuted,
                ),
                tooltip: 'Copy JSON',
                onPressed: _copyToClipboard,
                splashRadius: 16,
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                padding: EdgeInsets.zero,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JsonNode extends StatefulWidget {
  final String? nodeKey;
  final dynamic value;
  final bool isLast;
  final bool root;
  final String? searchQuery;
  final int matchOffset;
  final int? activeGlobalIndex;

  /// Cache passed down from the root viewer so sibling subtrees share state.
  final Map<int, int> subtreeMatchCache;

  /// Stable id for this node instance.
  final int nodeId;

  /// Allocator for children to claim their own stable ids.
  final int Function() nextNodeId;

  const _JsonNode({
    this.nodeKey,
    required this.value,
    this.isLast = false,
    this.root = false,
    this.searchQuery,
    this.matchOffset = 0,
    this.activeGlobalIndex,
    required this.subtreeMatchCache,
    required this.nodeId,
    required this.nextNodeId,
  });

  @override
  State<_JsonNode> createState() => _JsonNodeState();
}

class _JsonNodeState extends State<_JsonNode> {
  late bool _isExpanded;
  bool _userToggled = false;
  GlobalKey? _activeScrollKey;

  @override
  void initState() {
    super.initState();
    _isExpanded = _shouldExpandByDefault(widget.value);
    if (!_isExpanded && _subtreeContainsActiveMatch()) {
      _isExpanded = true;
    }
  }

  @override
  void didUpdateWidget(covariant _JsonNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeGlobalIndex != oldWidget.activeGlobalIndex ||
        widget.searchQuery != oldWidget.searchQuery) {
      _userToggled = false;
      _activeScrollKey = null;
    }
    if (!_userToggled && !_isExpanded && _subtreeContainsActiveMatch()) {
      _isExpanded = true;
    }
  }

  /// Returns the total number of search matches within this node's subtree
  /// (key + value + descendants). Caches the result for the lifetime of the
  /// current (data, query) pair so we don't re-walk a 5000-node tree on
  /// every rebuild.
  int _cachedTotalMatchesInNode(String q) {
    final cacheKey = widget.nodeId;
    final cached = widget.subtreeMatchCache[cacheKey];
    if (cached != null) {
      return cached;
    }
    int total = 0;
    if (widget.nodeKey != null) {
      total += JsonViewer._countIn(widget.nodeKey!, q);
    }
    total += JsonViewer.countMatches(widget.value, q);
    widget.subtreeMatchCache[cacheKey] = total;
    return total;
  }

  bool _subtreeContainsActiveMatch() {
    final activeIdx = widget.activeGlobalIndex;
    if (activeIdx == null) return false;
    final q = widget.searchQuery;
    if (q == null || q.isEmpty) return false;

    final total = _cachedTotalMatchesInNode(q);
    final start = widget.matchOffset;
    final end = start + total;
    return activeIdx >= start && activeIdx < end;
  }

  static bool _shouldExpandByDefault(dynamic value) {
    if (value is List) return value.length <= 20;
    if (value is Map) return value.length <= 20;
    return true;
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      _userToggled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.searchQuery?.toLowerCase().trim();
    final hasQuery = query != null && query.isNotEmpty;

    int currentOffset = widget.matchOffset;

    TextSpan keyHtml;
    if (widget.nodeKey != null) {
      final keyText = '"${widget.nodeKey}"';
      if (hasQuery) {
        final keySpans = JsonViewer.buildHighlightedSpans(
          keyText,
          query,
          currentOffset,
          widget.activeGlobalIndex,
          _JsonViewerState._keyColor,
        );
        currentOffset += JsonViewer._countIn(keyText, query);
        keyHtml = TextSpan(
          children: [
            ...keySpans,
            TextSpan(
              text: ': ',
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                color: _JsonViewerState._punctuationColor,
              ),
            ),
          ],
        );
      } else {
        keyHtml = TextSpan(
          children: [
            TextSpan(
              text: keyText,
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                color: _JsonViewerState._keyColor,
              ),
            ),
            TextSpan(
              text: ': ',
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                color: _JsonViewerState._punctuationColor,
              ),
            ),
          ],
        );
      }
    } else {
      keyHtml = const TextSpan();
    }

    final comma = widget.isLast
        ? const TextSpan()
        : TextSpan(
            text: ',',
            style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
              color: _JsonViewerState._punctuationColor,
            ),
          );

    if (widget.value == null) {
      return _buildLeafLine(
        keyHtml,
        'null',
        _JsonViewerState._nullColor,
        currentOffset,
        query,
        comma,
      );
    }
    if (widget.value is bool) {
      return _buildLeafLine(
        keyHtml,
        widget.value.toString(),
        _JsonViewerState._boolColor,
        currentOffset,
        query,
        comma,
      );
    }
    if (widget.value is num) {
      return _buildLeafLine(
        keyHtml,
        widget.value.toString(),
        _JsonViewerState._numberColor,
        currentOffset,
        query,
        comma,
      );
    }
    if (widget.value is String) {
      final text = '"${widget.value}"';
      return _buildLeafLine(
        keyHtml,
        text,
        _JsonViewerState._stringColor,
        currentOffset,
        query,
        comma,
      );
    }

    if (widget.value is List) {
      final list = widget.value as List;
      if (list.isEmpty) {
        return _buildSimpleLine(keyHtml, '[]', comma);
      }
      return _buildCollapsible(
        keyHtml: keyHtml,
        openBracket: '[',
        closeBracket: ']',
        comma: comma,
        entries: list.asMap().entries.map(
              (e) => _ChildEntry(
                key: null,
                value: e.value,
                isLast: e.key == list.length - 1,
              ),
            ),
        valueMatchOffset: currentOffset,
      );
    }

    if (widget.value is Map) {
      final map = widget.value as Map;
      if (map.isEmpty) {
        return _buildSimpleLine(keyHtml, '{}', comma);
      }
      final entries = map.entries.toList();
      return _buildCollapsible(
        keyHtml: keyHtml,
        openBracket: '{',
        closeBracket: '}',
        comma: comma,
        entries: entries.asMap().entries.map(
              (e) => _ChildEntry(
                key: e.value.key.toString(),
                value: e.value.value,
                isLast: e.key == entries.length - 1,
              ),
            ),
        valueMatchOffset: currentOffset,
      );
    }

    return _buildLeafLine(
      keyHtml,
      widget.value.toString(),
      _JsonViewerState._punctuationColor,
      currentOffset,
      query,
      comma,
    );
  }

  Widget _buildLeafLine(
    TextSpan keySpan,
    String valueText,
    Color valueColor,
    int matchOffset,
    String? query,
    TextSpan commaSpan,
  ) {
    final hasQuery = query != null && query.isNotEmpty;

    TextSpan valueSpan;
    bool hasActiveMatch = false;
    if (hasQuery) {
      final spans = JsonViewer.buildHighlightedSpans(
        valueText,
        query,
        matchOffset,
        widget.activeGlobalIndex,
        valueColor,
      );
      final hasActiveMatchInValue = spans.any(
        (s) =>
            s.style?.backgroundColor == _JsonViewerState._activeHighlightColor,
      );
      final hasActiveMatchInKey = _spanHasActiveHighlight(keySpan);
      hasActiveMatch = hasActiveMatchInValue || hasActiveMatchInKey;
      valueSpan = TextSpan(children: spans);
    } else {
      valueSpan = TextSpan(
        text: valueText,
        style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
          color: valueColor,
        ),
      );
    }

    if (hasActiveMatch) {
      _activeScrollKey ??= GlobalKey();
    }
    final key = hasActiveMatch ? _activeScrollKey : null;
    if (hasActiveMatch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = key?.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        }
      });
    }

    return Padding(
      key: key,
      padding: EdgeInsets.only(left: widget.root ? 0 : 16.0),
      child: Text.rich(
        TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [keySpan, valueSpan, commaSpan],
        ),
      ),
    );
  }

  Widget _buildSimpleLine(TextSpan keySpan, String text, TextSpan commaSpan) {
    return Padding(
      padding: EdgeInsets.only(left: widget.root ? 0 : 16.0),
      child: Text.rich(
        TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            keySpan,
            TextSpan(
              text: text,
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                color: _JsonViewerState._punctuationColor,
              ),
            ),
            commaSpan,
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsible({
    required TextSpan keyHtml,
    required String openBracket,
    required String closeBracket,
    required TextSpan comma,
    required Iterable<_ChildEntry> entries,
    required int valueMatchOffset,
  }) {
    List<Widget>? children;
    if (_isExpanded) {
      final query = widget.searchQuery;
      int childOffset = valueMatchOffset;
      children = [];
      for (final entry in entries) {
        final child = _JsonNode(
          nodeKey: entry.key,
          value: entry.value,
          isLast: entry.isLast,
          searchQuery: query,
          matchOffset: childOffset,
          activeGlobalIndex: widget.activeGlobalIndex,
          subtreeMatchCache: widget.subtreeMatchCache,
          nodeId: widget.nextNodeId(),
          nextNodeId: widget.nextNodeId,
        );
        children.add(child);

        if (query != null && query.isNotEmpty) {
          if (entry.key != null) {
            childOffset += JsonViewer._countIn(
              '"${entry.key}"',
              query.toLowerCase(),
            );
          }
          childOffset += JsonViewer.countMatches(entry.value, query);
        }
      }
    }

    final hasActiveMatchInHeader = _spanHasActiveHighlight(keyHtml);
    if (hasActiveMatchInHeader) {
      _activeScrollKey ??= GlobalKey();
    }
    final headerKey = hasActiveMatchInHeader ? _activeScrollKey : null;
    if (hasActiveMatchInHeader) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = headerKey?.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        }
      });
    }

    return Padding(
      padding: EdgeInsets.only(left: widget.root ? 0 : 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: headerKey,
            onTap: _toggle,
            hoverColor: InterceptlyTheme.hoverOverlay,
            borderRadius: BorderRadius.circular(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.rotate(
                  angle: _isExpanded ? 0 : -1.5708,
                  child: const Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: InterceptlyTheme.textMuted,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    style: DefaultTextStyle.of(context).style,
                    children: [
                      keyHtml,
                      TextSpan(
                        text: openBracket,
                        style: InterceptlyTheme.typography.bodyMediumRegular
                            .copyWith(
                          color: _JsonViewerState._punctuationColor,
                        ),
                      ),
                      if (!_isExpanded)
                        TextSpan(
                          text: ' ... ',
                          style: InterceptlyTheme.typography.bodyMediumRegular
                              .copyWith(
                            color: InterceptlyTheme.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      if (!_isExpanded)
                        TextSpan(
                          text: closeBracket,
                          style: InterceptlyTheme.typography.bodyMediumRegular
                              .copyWith(
                            color: _JsonViewerState._punctuationColor,
                          ),
                        ),
                      if (!_isExpanded) comma,
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isExpanded && children != null)
            RepaintBoundary(
              child: Container(
                margin: const EdgeInsets.only(left: 8.0),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: InterceptlyTheme.dividerSubtle,
                      width: 1.0,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
          if (_isExpanded)
            Text.rich(
              TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: closeBracket,
                    style: InterceptlyTheme.typography.bodyMediumRegular
                        .copyWith(color: _JsonViewerState._punctuationColor),
                  ),
                  comma,
                ],
              ),
            ),
        ],
      ),
    );
  }

  static bool _spanHasActiveHighlight(TextSpan span) {
    final style = span.style;
    if (style?.backgroundColor == _JsonViewerState._activeHighlightColor) {
      return true;
    }

    final children = span.children;
    if (children == null || children.isEmpty) return false;
    for (final child in children) {
      if (_spanHasActiveHighlight(child as TextSpan)) {
        return true;
      }
    }
    return false;
  }
}

class _ChildEntry {
  final String? key;
  final dynamic value;
  final bool isLast;
  const _ChildEntry({this.key, required this.value, this.isLast = false});
}

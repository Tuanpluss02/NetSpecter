import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

import 'toast_notification.dart';

/// Collapsible JSON renderer with VSCode-style line numbers, gutter
/// expand/collapse, search highlighting, and copy support.
///
/// Line numbers reflect the position in the **fully-expanded** document.
/// Collapsed regions cause line numbers to skip, matching VSCode behavior.
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

// ─────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────

class _JsonViewerState extends State<JsonViewer> {
  // ── Syntax colours ──
  static const _keyColor = InterceptlyGlobalColor.blue400;
  static const _stringColor = InterceptlyGlobalColor.red400;
  static const _numberColor = InterceptlyGlobalColor.green400;
  static const _boolColor = InterceptlyGlobalColor.blue500;
  static const _nullColor = InterceptlyGlobalColor.blue500;
  static const _punctuationColor = InterceptlyGlobalColor.textQuaternary;
  static const _highlightColor = InterceptlyGlobalColor.highlightStrong;
  static const _activeHighlightColor = InterceptlyGlobalColor.orange;
  static const _lineNumberColor = InterceptlyGlobalColor.textMuted;

  static const double _foldIconWidth = 16.0;

  /// Manual expand / collapse state keyed by JSON path.
  final Map<String, bool> _expandState = {};

  /// Paths auto-expanded to reveal the current active search match.
  final Set<String> _searchAutoExpanded = {};

  /// Paths the **user** explicitly collapsed. Prevents re-auto-expanding
  /// a node when the active match is still in its subtree.
  final Set<String> _userCollapsedPaths = {};

  /// Key attached to the first line containing the active search match,
  /// used by [Scrollable.ensureVisible] to scroll to it.
  GlobalKey? _activeScrollKey;

  // ── Lifecycle ──

  @override
  void didUpdateWidget(covariant JsonViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeGlobalIndex != oldWidget.activeGlobalIndex ||
        widget.searchQuery != oldWidget.searchQuery) {
      _searchAutoExpanded.clear();
      _userCollapsedPaths.clear();
    }
  }

  // ── Expand / collapse helpers ──

  bool _isNodeExpanded(String path, int childCount) {
    if (_searchAutoExpanded.contains(path)) return true;
    return _expandState[path] ?? (childCount <= 20);
  }

  void _toggleNode(String path, int childCount) {
    setState(() {
      final wasExpanded = _isNodeExpanded(path, childCount);
      _expandState[path] = !wasExpanded;
      _searchAutoExpanded.remove(path);
      if (wasExpanded) {
        _userCollapsedPaths.add(path);
      } else {
        _userCollapsedPaths.remove(path);
      }
    });
  }

  void _copyToClipboard() {
    final formatted = JsonViewer.formatData(widget.data);
    Clipboard.setData(ClipboardData(text: formatted)).then((_) {
      if (mounted) {
        ToastNotification.show('Copied to clipboard', contextHint: context);
      }
    });
  }

  TextStyle get _baseTextStyle => InterceptlyTheme.typography.bodyMediumRegular;

  TextSpan _bracketSpan(String text) => TextSpan(
        text: text,
        style: _baseTextStyle.copyWith(color: _punctuationColor),
      );

  // ─────────────────────────────────────────────────────────────
  // Expanded line counting
  // ─────────────────────────────────────────────────────────────

  /// Counts how many lines [value] would occupy when **fully expanded**.
  ///
  /// Used to assign correct real line numbers when a collapsible node
  /// is folded — the line numbers skip the hidden range, matching
  /// VSCode behavior.
  static int _countExpandedLines(dynamic value) {
    if (value == null || value is bool || value is num || value is String) {
      return 1;
    }
    if (value is List) {
      if (value.isEmpty) return 1; // rendered as "[]"
      int total = 2; // opening '[' + closing ']'
      for (final item in value) {
        total += _countExpandedLines(item);
      }
      return total;
    }
    if (value is Map) {
      if (value.isEmpty) return 1; // rendered as "{}"
      int total = 2; // opening '{' + closing '}'
      for (final entry in value.entries) {
        total += _countExpandedLines(entry.value);
      }
      return total;
    }
    return 1; // fallback for unknown types
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.data == null) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          'No Data',
          style: _baseTextStyle.copyWith(
            fontStyle: FontStyle.italic,
            color: InterceptlyTheme.textMuted,
          ),
        ),
      );
    }

    // Reset scroll key for this build pass.
    _activeScrollKey = null;

    final query = widget.searchQuery?.toLowerCase().trim();
    final hasQuery = query != null && query.isNotEmpty;

    // Flatten JSON tree into a sequential line list.
    final lines = <_FlatLine>[];
    _flatten(
      value: widget.data,
      key: null,
      isLast: true,
      indent: 0,
      path: r'$',
      query: hasQuery ? query : null,
      matchOffset: widget.matchOffset,
      realLine: 1,
      output: lines,
    );

    if (lines.isEmpty) return const SizedBox.shrink();

    // Gutter sizing based on the highest real line number (last line).
    final maxRealLine = lines.last.realLineNumber;
    final digitCount = maxRealLine.toString().length;
    // digitCount * 8.0 for digits + 8.0 for spacing between number and fold icon
    final lineNumberWidth = digitCount * 8.0 + 8.0;

    final contentStyle = _baseTextStyle.copyWith(
      fontFamilyFallback: const ['monospace'],
      fontSize: 12,
      height: 1.5,
    );
    const lineHeight = 18.0; // fontSize 12 × height 1.5

    // Schedule scroll-to for the active search match.
    final scrollKey = _activeScrollKey;
    if (scrollKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = scrollKey.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
        }
      });
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DefaultTextStyle(
            style: contentStyle,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Gutter (line numbers + fold icons) ──
                Container(
                  padding: const EdgeInsets.only(right: 4.0),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: InterceptlyTheme.dividerSubtle,
                        width: 1.0,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (int i = 0; i < lines.length; i++)
                        _buildGutterCell(
                          line: lines[i],
                          lineNumberWidth: lineNumberWidth,
                          lineHeight: lineHeight,
                          style: contentStyle,
                        ),
                    ],
                  ),
                ),

                // ── Content (horizontally scrollable) ──
                // Using SelectableRegion for multi-line text selection
                Expanded(
                  child: _SelectableJsonContent(
                    lines: lines,
                    lineHeight: lineHeight,
                    contentStyle: contentStyle,
                  ),
                ),
              ],
            ),
          ),

          // ── Copy button ──
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

  // ─────────────────────────────────────────────────────────────
  // Gutter & Content line builders
  // ─────────────────────────────────────────────────────────────

  /// Builds one gutter row: **real line number** + optional **fold icon**.
  ///
  /// The entire row is tappable for collapsible lines so the touch
  /// target is wide enough on mobile.
  Widget _buildGutterCell({
    required _FlatLine line,
    required double lineNumberWidth,
    required double lineHeight,
    required TextStyle style,
  }) {
    final hasFold = line.collapsible != null;

    Widget cell = SizedBox(
      height: lineHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Line number (real position in the fully-expanded document)
          SizedBox(
            width: lineNumberWidth,
            child: Text(
              '${line.realLineNumber}',
              textAlign: TextAlign.right,
              style: style.copyWith(color: _lineNumberColor),
            ),
          ),
          // Fold icon slot
          SizedBox(
            width: _foldIconWidth,
            height: lineHeight,
            child: hasFold
                ? Center(
                    child: Transform.rotate(
                      angle: line.collapsible!.isExpanded ? 0 : -1.5708,
                      child: const Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: InterceptlyTheme.textMuted,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );

    if (hasFold) {
      cell = GestureDetector(
        onTap: () => _toggleNode(
          line.collapsible!.path,
          line.collapsible!.childCount,
        ),
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: cell,
        ),
      );
    }

    return cell;
  }

  // ─────────────────────────────────────────────────────────────
  // Flatten logic
  // ─────────────────────────────────────────────────────────────

  /// Recursively flatten [value] into sequential [_FlatLine] objects.
  ///
  /// [realLine] is the line number this value starts at in the
  /// fully-expanded document.
  ///
  /// Returns a record with the updated [matchOffset] and the
  /// [nextRealLine] (the line number that follows this value in the
  /// fully-expanded view).
  ({int matchOffset, int nextRealLine}) _flatten({
    required dynamic value,
    required String? key,
    required bool isLast,
    required int indent,
    required String path,
    required String? query,
    required int matchOffset,
    required int realLine,
    required List<_FlatLine> output,
  }) {
    int currentOffset = matchOffset;

    // ── Build key spans ──
    final keySpans = <TextSpan>[];
    if (key != null) {
      final keyText = '"$key"';
      if (query != null) {
        keySpans.addAll(
          JsonViewer.buildHighlightedSpans(
            keyText,
            query,
            currentOffset,
            widget.activeGlobalIndex,
            _keyColor,
          ),
        );
        currentOffset += JsonViewer._countIn(keyText, query);
      } else {
        keySpans.add(TextSpan(
          text: keyText,
          style: _baseTextStyle.copyWith(color: _keyColor),
        ));
      }
      keySpans.add(TextSpan(
        text: ': ',
        style: _baseTextStyle.copyWith(color: _punctuationColor),
      ));
    }

    final commaSpan = isLast
        ? null
        : TextSpan(
            text: ',',
            style: _baseTextStyle.copyWith(color: _punctuationColor),
          );

    // ── Scalars ──
    if (value == null) {
      return _emitLeaf(output, indent, keySpans, 'null', _nullColor,
          currentOffset, query, commaSpan, realLine);
    }
    if (value is bool) {
      return _emitLeaf(output, indent, keySpans, value.toString(), _boolColor,
          currentOffset, query, commaSpan, realLine);
    }
    if (value is num) {
      return _emitLeaf(output, indent, keySpans, value.toString(), _numberColor,
          currentOffset, query, commaSpan, realLine);
    }
    if (value is String) {
      return _emitLeaf(output, indent, keySpans, '"$value"', _stringColor,
          currentOffset, query, commaSpan, realLine);
    }

    // ── List ──
    if (value is List) {
      if (value.isEmpty) {
        output.add(_FlatLine(
          indentLevel: indent,
          realLineNumber: realLine,
          spans: [
            ...keySpans,
            _bracketSpan('[]'),
            if (commaSpan != null) commaSpan,
          ],
        ));
        return (matchOffset: currentOffset, nextRealLine: realLine + 1);
      }
      return _emitCollapsible(
        output: output,
        indent: indent,
        keySpans: keySpans,
        openBracket: '[',
        closeBracket: ']',
        commaSpan: commaSpan,
        path: path,
        childCount: value.length,
        query: query,
        matchOffset: currentOffset,
        realLine: realLine,
        rawValue: value,
        children: value.asMap().entries.map(
              (e) => _ChildEntry(
                key: null,
                value: e.value,
                isLast: e.key == value.length - 1,
                childPath: '$path[${e.key}]',
              ),
            ),
      );
    }

    // ── Map ──
    if (value is Map) {
      if (value.isEmpty) {
        output.add(_FlatLine(
          indentLevel: indent,
          realLineNumber: realLine,
          spans: [
            ...keySpans,
            _bracketSpan('{}'),
            if (commaSpan != null) commaSpan,
          ],
        ));
        return (matchOffset: currentOffset, nextRealLine: realLine + 1);
      }
      final entries = value.entries.toList();
      return _emitCollapsible(
        output: output,
        indent: indent,
        keySpans: keySpans,
        openBracket: '{',
        closeBracket: '}',
        commaSpan: commaSpan,
        path: path,
        childCount: entries.length,
        query: query,
        matchOffset: currentOffset,
        realLine: realLine,
        rawValue: value,
        children: entries.asMap().entries.map(
              (e) => _ChildEntry(
                key: e.value.key.toString(),
                value: e.value.value,
                isLast: e.key == entries.length - 1,
                childPath: '$path.${e.value.key}',
              ),
            ),
      );
    }

    // ── Fallback ──
    return _emitLeaf(output, indent, keySpans, value.toString(),
        _punctuationColor, currentOffset, query, commaSpan, realLine);
  }

  /// Emit a single leaf line (scalar value).
  ({int matchOffset, int nextRealLine}) _emitLeaf(
    List<_FlatLine> output,
    int indent,
    List<TextSpan> keySpans,
    String valueText,
    Color valueColor,
    int matchOffset,
    String? query,
    TextSpan? commaSpan,
    int realLine,
  ) {
    final spans = <TextSpan>[...keySpans];
    bool hasActiveMatch = false;

    if (query != null) {
      final valueSpans = JsonViewer.buildHighlightedSpans(
        valueText,
        query,
        matchOffset,
        widget.activeGlobalIndex,
        valueColor,
      );
      final activeInValue = valueSpans.any(
        (s) => s.style?.backgroundColor == _activeHighlightColor,
      );
      final activeInKey = keySpans.any(_spanHasActiveHighlight);
      hasActiveMatch = activeInValue || activeInKey;
      spans.addAll(valueSpans);
      matchOffset += JsonViewer._countIn(valueText, query);
    } else {
      spans.add(TextSpan(
        text: valueText,
        style: _baseTextStyle.copyWith(color: valueColor),
      ));
    }

    if (commaSpan != null) spans.add(commaSpan);

    output.add(_FlatLine(
      indentLevel: indent,
      realLineNumber: realLine,
      spans: spans,
      hasActiveMatch: hasActiveMatch,
    ));

    return (matchOffset: matchOffset, nextRealLine: realLine + 1);
  }

  /// Emit lines for a collapsible Map or List.
  ///
  /// When expanded: header + children + closing bracket.
  /// When collapsed: single line with `{ … }` / `[ … ]`.
  ///
  /// Collapsed nodes advance [realLine] by the number of lines the
  /// fully-expanded subtree would occupy so siblings get correct
  /// real line numbers.
  ({int matchOffset, int nextRealLine}) _emitCollapsible({
    required List<_FlatLine> output,
    required int indent,
    required List<TextSpan> keySpans,
    required String openBracket,
    required String closeBracket,
    required TextSpan? commaSpan,
    required String path,
    required int childCount,
    required String? query,
    required int matchOffset,
    required int realLine,
    required dynamic rawValue,
    required Iterable<_ChildEntry> children,
  }) {
    int currentOffset = matchOffset;

    // Auto-expand when the active search match falls inside this subtree
    // and the user hasn't manually collapsed it.
    if (query != null &&
        widget.activeGlobalIndex != null &&
        !_userCollapsedPaths.contains(path)) {
      final totalValueMatches = JsonViewer.countMatches(rawValue, query);
      if (totalValueMatches > 0 &&
          widget.activeGlobalIndex! >= currentOffset &&
          widget.activeGlobalIndex! < currentOffset + totalValueMatches) {
        if (!_isNodeExpanded(path, childCount)) {
          _searchAutoExpanded.add(path);
        }
      }
    }

    final expanded = _isNodeExpanded(path, childCount);
    final activeInKey = keySpans.any(_spanHasActiveHighlight);

    if (expanded) {
      // Header: "key": {
      output.add(_FlatLine(
        indentLevel: indent,
        realLineNumber: realLine,
        spans: [...keySpans, _bracketSpan(openBracket)],
        collapsible: _CollapsibleInfo(
          path: path,
          childCount: childCount,
          isExpanded: true,
        ),
        hasActiveMatch: activeInKey,
      ));

      int nextLine = realLine + 1;

      // Children
      for (final child in children) {
        final result = _flatten(
          value: child.value,
          key: child.key,
          isLast: child.isLast,
          indent: indent + 1,
          path: child.childPath,
          query: query,
          matchOffset: currentOffset,
          realLine: nextLine,
          output: output,
        );
        currentOffset = result.matchOffset;
        nextLine = result.nextRealLine;
      }

      // Closing bracket
      output.add(_FlatLine(
        indentLevel: indent,
        realLineNumber: nextLine,
        spans: [
          _bracketSpan(closeBracket),
          if (commaSpan != null) commaSpan,
        ],
      ));

      return (matchOffset: currentOffset, nextRealLine: nextLine + 1);
    } else {
      // Collapsed: "key": { … },
      //
      // The real line number is the opening bracket line. We advance
      // by the total expanded line count so the next sibling picks up
      // the correct real line number.
      final expandedLineCount = _countExpandedLines(rawValue);

      output.add(_FlatLine(
        indentLevel: indent,
        realLineNumber: realLine,
        spans: [
          ...keySpans,
          _bracketSpan(openBracket),
          TextSpan(
            text: ' … ',
            style: _baseTextStyle.copyWith(
              color: InterceptlyTheme.textMuted,
              fontSize: 10,
            ),
          ),
          _bracketSpan(closeBracket),
          if (commaSpan != null) commaSpan,
        ],
        collapsible: _CollapsibleInfo(
          path: path,
          childCount: childCount,
          isExpanded: false,
        ),
        hasActiveMatch: activeInKey,
      ));

      // Advance the match offset past all collapsed children so
      // sibling nodes receive the correct offset.
      if (query != null) {
        for (final child in children) {
          if (child.key != null) {
            currentOffset += JsonViewer._countIn('"${child.key}"', query);
          }
          currentOffset += JsonViewer.countMatches(child.value, query);
        }
      }

      return (
        matchOffset: currentOffset,
        nextRealLine: realLine + expandedLineCount,
      );
    }
  }

  // ── Helpers ──

  static bool _spanHasActiveHighlight(TextSpan span) {
    final style = span.style;
    if (style?.backgroundColor == _activeHighlightColor) {
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

// ─────────────────────────────────────────────────────────────
// Data classes
// ─────────────────────────────────────────────────────────────

/// A single visual line in the flat JSON view.
class _FlatLine {
  /// Indentation depth (0 = root).
  final int indentLevel;

  /// Line number in the **fully-expanded** document.
  ///
  /// When collapsible regions are folded, visible line numbers will
  /// skip the hidden range — matching VSCode behavior.
  final int realLineNumber;

  /// Inline spans forming the visible text content of this line.
  final List<TextSpan> spans;

  /// Non-null when this line opens a collapsible block.
  final _CollapsibleInfo? collapsible;

  /// `true` when this line contains the currently active search match.
  final bool hasActiveMatch;

  const _FlatLine({
    required this.indentLevel,
    required this.realLineNumber,
    required this.spans,
    this.collapsible,
    this.hasActiveMatch = false,
  });
}

/// Metadata attached to a collapsible header line.
class _CollapsibleInfo {
  /// Unique path identifying this node (e.g. `$.data.items[0]`).
  final String path;

  /// Number of direct children (used for the default expand heuristic).
  final int childCount;

  /// Snapshot of the expanded state at build time.
  final bool isExpanded;

  const _CollapsibleInfo({
    required this.path,
    required this.childCount,
    required this.isExpanded,
  });
}

/// A child entry passed to [_emitCollapsible] for iteration.
class _ChildEntry {
  final String? key;
  final dynamic value;
  final bool isLast;

  /// Path string for this child (e.g. `$.items[0]` or `$.data.name`).
  final String childPath;

  const _ChildEntry({
    this.key,
    required this.value,
    this.isLast = false,
    required this.childPath,
  });
}

/// Custom widget that handles text selection across multiple lines using SelectableRegion.
/// SelectableRegion allows selection across multiple widgets without SelectionArea + ScrollView conflict.
class _SelectableJsonContent extends StatefulWidget {
  final List<_FlatLine> lines;
  final double lineHeight;
  final TextStyle contentStyle;

  const _SelectableJsonContent({
    required this.lines,
    required this.lineHeight,
    required this.contentStyle,
  });

  @override
  State<_SelectableJsonContent> createState() => _SelectableJsonContentState();
}

class _SelectableJsonContentState extends State<_SelectableJsonContent> {
  // Global key to get the GlobalKey for SelectableRegion
  final GlobalKey _selectableRegionKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // Build the full text for SelectableRegion
    final allText = StringBuffer();
    final lineStartIndices = <int>[];
    for (final line in widget.lines) {
      lineStartIndices.add(allText.length);
      for (final span in line.spans) {
        allText.write(span.text ?? '');
      }
      allText.writeln();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableRegion(
              key: _selectableRegionKey,
              focusNode: FocusNode(),
              selectionControls: materialTextSelectionControls,
              child: Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < widget.lines.length; i++)
                      _buildLine(i, widget.lines[i]),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLine(int index, _FlatLine line) {
    return Container(
      height: widget.lineHeight,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.only(left: line.indentLevel * 16.0),
      child: Text.rich(
        TextSpan(
          style: widget.contentStyle,
          children: line.spans,
        ),
      ),
    );
  }
}

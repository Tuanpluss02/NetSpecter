// ignore_for_file: constant_identifier_names

import 'dart:math';

import 'package:flutter/material.dart';

/// Draggable FAB widget which is always aligned to
/// the edge of the screen - be it left,top, right,bottom
class DraggableFab extends StatefulWidget {
  const DraggableFab({required this.child, super.key, this.initPosition, this.securityBottom = 0});
  final Widget child;
  final Offset? initPosition;
  final double securityBottom;

  @override
  State<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<DraggableFab> with SingleTickerProviderStateMixin {
  late Size _widgetSize;
  double? _left, _top;
  double _screenWidth = 0.0, _screenHeight = 0.0;
  double? _screenWidthMid, _screenHeightMid;
  final GlobalKey _childKey = GlobalKey();

  late final AnimationController _snapController;
  Animation<Offset>? _snapAnimation;
  late final ValueNotifier<Offset> _positionVN = ValueNotifier(Offset.zero);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _getWidgetSize(context));
    _snapController = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _snapController.addListener(() {
      if (_snapAnimation != null) {
        final v = _snapAnimation!.value;
        _positionVN.value = v;
      }
    });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _getWidgetSize(BuildContext context) {
    final BuildContext? childCtx = _childKey.currentContext;
    final RenderBox? rb = childCtx?.findRenderObject() as RenderBox?;
    if (rb != null) {
      _widgetSize = rb.size;
    } else {
      // Fallback if not laid out yet
      _widgetSize = const Size(44, 44);
    }

    if (widget.initPosition != null) {
      final snapped = _computeSnapped(widget.initPosition!);
      _left = snapped.dx;
      _top = snapped.dy;
      _positionVN.value = snapped;
    } else {
      // default to right-center if no init provided
      final Size screenSize = MediaQuery.of(context).size;
      final Offset defaultCenter = Offset(screenSize.width, screenSize.height / 2);
      final snapped = _computeSnapped(defaultCenter);
      _left = snapped.dx;
      _top = snapped.dy;
      _positionVN.value = snapped;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ValueListenableBuilder<Offset>(
          valueListenable: _positionVN,
          builder: (context, pos, _) {
            _left = pos.dx;
            _top = pos.dy;
            return Positioned(
              left: pos.dx,
              top: pos.dy,
              child: RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    final current = _positionVN.value;
                    final next = Offset(
                      current.dx + details.delta.dx,
                      current.dy + details.delta.dy,
                    );
                    _positionVN.value = next;
                  },
                  onPanEnd: (_) {
                    final double centerX = pos.dx + _widgetSize.width / 2;
                    final double centerY = pos.dy + _widgetSize.height / 2;
                    final target = _computeSnapped(Offset(centerX, centerY));
                    _snapAnimation = Tween<Offset>(
                      begin: pos,
                      end: target,
                    ).animate(CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic));
                    _snapController
                      ..reset()
                      ..forward();
                  },
                  child: KeyedSubtree(key: _childKey, child: widget.child),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // no-op: legacy signature kept for potential compatibility

  // removed legacy setter; updates now flow through _positionVN directly

  /// Compute the snapped left/top (not mutating state)
  Offset _computeSnapped(Offset targetOffset) {
    if (_screenWidthMid == null || _screenHeightMid == null) {
      final Size screenSize = MediaQuery.of(context).size;
      _screenWidth = screenSize.width;
      _screenHeight = screenSize.height;
      _screenWidthMid = _screenWidth / 2;
      _screenHeightMid = _screenHeight / 2;
    }

    double left = _left ?? 0;
    double top = _top ?? 0;
    switch (_getAnchor(targetOffset)) {
      case Anchor.LEFT_FIRST:
        left = 0;
        top = max(
          0,
          min(
            _screenHeight - _widgetSize.height - widget.securityBottom,
            targetOffset.dy - _widgetSize.height / 2,
          ),
        );
        break;
      case Anchor.TOP_FIRST:
        left = max(
          0,
          min(_screenWidth - _widgetSize.width, targetOffset.dx - _widgetSize.width / 2),
        );
        top = 0;
        break;
      case Anchor.RIGHT_SECOND:
        left = _screenWidth - _widgetSize.width;
        top = max(
          0,
          min(
            _screenHeight - _widgetSize.height - widget.securityBottom,
            targetOffset.dy - _widgetSize.height / 2,
          ),
        );
        break;
      case Anchor.TOP_SECOND:
        left = max(
          0,
          min(_screenWidth - _widgetSize.width, targetOffset.dx - _widgetSize.width / 2),
        );
        top = 0;
        break;
      case Anchor.LEFT_THIRD:
        left = 0;
        top = max(
          0,
          min(
            _screenHeight - _widgetSize.height - widget.securityBottom,
            targetOffset.dy - _widgetSize.height / 2,
          ),
        );
        break;
      case Anchor.BOTTOM_THIRD:
        left = max(
          0,
          min(_screenWidth - _widgetSize.width, targetOffset.dx - _widgetSize.width / 2),
        );
        top = _screenHeight - _widgetSize.height - widget.securityBottom;
        break;
      case Anchor.RIGHT_FOURTH:
        left = _screenWidth - _widgetSize.width;
        top = max(
          0,
          min(
            _screenHeight - _widgetSize.height - widget.securityBottom,
            targetOffset.dy - _widgetSize.height / 2,
          ),
        );
        break;
      case Anchor.BOTTOM_FOURTH:
        left = max(
          0,
          min(_screenWidth - _widgetSize.width, targetOffset.dx - _widgetSize.width / 2),
        );
        top = _screenHeight - _widgetSize.height - widget.securityBottom;
        break;
    }
    return Offset(left, top);
  }

  /// Computes the appropriate anchor screen edge for the widget
  Anchor _getAnchor(Offset position) {
    if (position.dx < _screenWidthMid! && position.dy < _screenHeightMid!) {
      return position.dx < position.dy ? Anchor.LEFT_FIRST : Anchor.TOP_FIRST;
    } else if (position.dx >= _screenWidthMid! && position.dy < _screenHeightMid!) {
      return _screenWidth - position.dx < position.dy ? Anchor.RIGHT_SECOND : Anchor.TOP_SECOND;
    } else if (position.dx < _screenWidthMid! && position.dy >= _screenHeightMid!) {
      return position.dx < _screenHeight - position.dy ? Anchor.LEFT_THIRD : Anchor.BOTTOM_THIRD;
    } else {
      return _screenWidth - position.dx < _screenHeight - position.dy
          ? Anchor.RIGHT_FOURTH
          : Anchor.BOTTOM_FOURTH;
    }
  }
}

/// #######################################
/// #       |          #        |         #
/// #    TOP_FIRST     #  TOP_SECOND      #
/// # - LEFT_FIRST     #  RIGHT_SECOND -  #
/// #######################################
/// # - LEFT_THIRD     #   RIGHT_FOURTH - #
/// #  BOTTOM_THIRD    #   BOTTOM_FOURTH  #
/// #     |            #       |          #
/// #######################################
enum Anchor {
  LEFT_FIRST,
  TOP_FIRST,
  RIGHT_SECOND,
  TOP_SECOND,
  LEFT_THIRD,
  BOTTOM_THIRD,
  RIGHT_FOURTH,
  BOTTOM_FOURTH,
}

import 'package:flutter/material.dart';

import '../../core/netspecter_controller.dart';
import 'draggable_fab.dart';
import '../screens/netspecter_screen.dart';

class NetSpecterOverlay extends StatefulWidget {
  NetSpecterOverlay({
    super.key,
    NetSpecter? specter,
    required this.child,
  }) : specter = specter ?? NetSpecter.instance;

  final NetSpecter specter;
  final Widget child;

  @override
  State<NetSpecterOverlay> createState() => _NetSpecterOverlayState();
}

class _NetSpecterOverlayState extends State<NetSpecterOverlay> {
  @override
  void initState() {
    super.initState();
    widget.specter.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final padding = mediaQuery.padding;
    final initPos = Offset(screenSize.width, screenSize.height / 2);

    return Stack(
      children: <Widget>[
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: false,
            child: DraggableFab(
              initPosition: initPos,
              securityBottom: padding.bottom,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Material(
                  color: Colors.red,
                  elevation: 2,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => NetSpecterScreen(
                            specter: widget.specter,
                          ),
                        ),
                      );
                    },
                    customBorder: const CircleBorder(),
                    child: const Center(
                      child: Icon(
                        Icons.bug_report,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/netspecter_controller.dart';
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
    return Stack(
      children: <Widget>[
        widget.child,
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: FloatingActionButton.small(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NetSpecterScreen(specter: widget.specter),
                  ),
                );
              },
              child: const Icon(Icons.network_check_outlined),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Native Swift navigation. Android continues to use the existing Flutter bar.
class IosNavigation extends StatefulWidget {
  const IosNavigation({
    super.key,
    required this.index,
    required this.onChanged,
  });
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<IosNavigation> createState() => _IosNavigationState();
}

class _IosNavigationState extends State<IosNavigation> {
  MethodChannel? channel;

  @override
  void didUpdateWidget(IosNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      channel?.invokeMethod<void>('select', widget.index);
    }
  }

  @override
  void dispose() {
    channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      MediaQuery.paddingOf(context).left + 12,
      0,
      MediaQuery.paddingOf(context).right + 12,
      // The native tab bar also supplies spacing inside its floating capsule.
      // Lower the host by 12 points while retaining home-indicator clearance.
      (MediaQuery.paddingOf(context).bottom - 12).clamp(8.0, double.infinity),
    ),
    child: SizedBox(
      // UITabBar reserves space around its floating glass capsule internally.
      // Give that layout room so the icon and label aren't clipped by the lens.
      height: 80,
      child: UiKitView(
        viewType: 'krzene/native-navigation',
        creationParams: {'index': widget.index},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          final bridge = MethodChannel('krzene/native-navigation/$id');
          channel = bridge;
          bridge.setMethodCallHandler((call) async {
            if (call.method == 'select' && mounted) {
              final value = call.arguments;
              if (value is int && value >= 0 && value < 4) {
                widget.onChanged(value);
              }
            }
          });
          bridge.invokeMethod<void>('select', widget.index);
        },
      ),
    ),
  );
}

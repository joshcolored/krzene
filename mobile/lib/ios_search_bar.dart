import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// UIKit UISearchBar used only by the iOS Search screen.
class IosSearchBar extends StatefulWidget {
  const IosSearchBar({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<IosSearchBar> createState() => _IosSearchBarState();
}

class _IosSearchBarState extends State<IosSearchBar> {
  MethodChannel? channel;

  @override
  void dispose() {
    channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: UiKitView(
      viewType: 'krzene/search-bar',
      creationParams: const {'placeholder': 'Search every movie and show'},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (id) {
        final bridge = MethodChannel('krzene/search-bar/$id');
        channel = bridge;
        bridge.setMethodCallHandler((call) async {
          if (call.method == 'changed' && mounted) {
            widget.onChanged(call.arguments is String ? call.arguments : '');
          }
        });
      },
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// UIKit-owned Browse genre menu. Android keeps the Flutter selector.
class IosGenreMenu extends StatefulWidget {
  const IosGenreMenu({
    super.key,
    required this.genres,
    required this.selectedGenre,
    required this.onSelected,
  });

  final List<String> genres;
  final String? selectedGenre;
  final ValueChanged<String?> onSelected;

  @override
  State<IosGenreMenu> createState() => _IosGenreMenuState();
}

class _IosGenreMenuState extends State<IosGenreMenu> {
  MethodChannel? channel;

  Map<String, Object> get parameters => {
    'genres': widget.genres,
    'selected': widget.selectedGenre ?? '',
  };

  @override
  void didUpdateWidget(IosGenreMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedGenre != widget.selectedGenre ||
        oldWidget.genres.length != widget.genres.length) {
      channel?.invokeMethod<void>('update', parameters);
    }
  }

  @override
  void dispose() {
    channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 46,
    child: UiKitView(
      viewType: 'krzene/genre-menu',
      creationParams: parameters,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (id) {
        final bridge = MethodChannel('krzene/genre-menu/$id');
        channel = bridge;
        bridge.setMethodCallHandler((call) async {
          if (call.method != 'select' || !mounted) return;
          final value = call.arguments;
          widget.onSelected(value is String && value.isNotEmpty ? value : null);
        });
      },
    ),
  );
}

import 'package:flutter/material.dart';
import '../../../../core/theme/eroute_tokens.dart';

class MapControls extends StatelessWidget {
  final VoidCallback? locate, zoomIn, zoomOut;
  final bool locating;
  const MapControls({
    super.key,
    this.locate,
    this.zoomIn,
    this.zoomOut,
    required this.locating,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(ERouteRadius.card),
      border: Border.all(color: Theme.of(context).colorScheme.outline),
      boxShadow: ERouteShadows.raised,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '현재 위치로 이동',
          onPressed: locating ? null : locate,
          icon: locating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location),
        ),
        IconButton(
          tooltip: '지도 확대',
          onPressed: zoomIn,
          icon: const Icon(Icons.add),
        ),
        IconButton(
          tooltip: '지도 축소',
          onPressed: zoomOut,
          icon: const Icon(Icons.remove),
        ),
      ],
    ),
  );
}

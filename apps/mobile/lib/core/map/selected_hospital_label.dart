import 'package:flutter/material.dart';
import '../theme/eroute_tokens.dart';

class SelectedHospitalLabel extends StatelessWidget {
  final String name;
  final VoidCallback onTap;
  const SelectedHospitalLabel({
    super.key,
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: '선택한 병원: $name',
    button: true,
    selected: true,
    child: ExcludeSemantics(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(ERouteRadius.control),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ERouteRadius.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: ERouteSpacing.sm),
            child: Row(
              children: [
                Icon(
                  Icons.local_hospital_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: ERouteSpacing.xs),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ERouteTypography.label,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

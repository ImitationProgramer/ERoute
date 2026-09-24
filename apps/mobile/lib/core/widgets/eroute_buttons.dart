import 'package:flutter/material.dart';
import '../theme/eroute_tokens.dart';

class ERoutePrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget label;
  final IconData? icon;
  const ERoutePrimaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });
  @override
  Widget build(BuildContext context) => icon == null
      ? FilledButton(onPressed: onPressed, child: label)
      : FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: label);
}

class ERouteEmergencyButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final double diameter;
  const ERouteEmergencyButton({
    super.key,
    required this.onPressed,
    this.diameter = 208,
  });
  @override
  Widget build(BuildContext context) {
    final visualDiameter = diameter > 208 ? 208.0 : diameter;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: '119 전화 연결 확인 열기',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: context.eroute.emergency.withValues(alpha: .20),
              blurRadius: 0,
              spreadRadius: 16,
            ),
            BoxShadow(
              color: context.eroute.emergency.withValues(alpha: .12),
              blurRadius: 0,
              spreadRadius: 30,
            ),
          ],
        ),
        child: Material(
          color: context.eroute.emergency,
          shape: const CircleBorder(),
          elevation: 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: diameter,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.call_rounded,
                    size: visualDiameter * .22,
                    color: context.eroute.onEmergency,
                  ),
                  const SizedBox(height: ERouteSpacing.sm),
                  Text(
                    '119 신고',
                    style: TextStyle(
                      color: context.eroute.onEmergency,
                      fontSize: visualDiameter * .11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: ERouteSpacing.xxs),
                  Text(
                    '전화 연결하기',
                    style: TextStyle(
                      color: context.eroute.onEmergency,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
}

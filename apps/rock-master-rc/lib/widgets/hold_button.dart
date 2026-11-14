import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Large multi-touch hold button. Down/up are reported independently so
/// several buttons can be held at once (forward+left, etc.).
class HoldButton extends StatelessWidget {
  const HoldButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.held,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool held;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        HapticFeedback.lightImpact();
        onChanged(true);
      },
      onPointerUp: (_) => onChanged(false),
      onPointerCancel: (_) => onChanged(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        decoration: BoxDecoration(
          color: held ? color : color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withValues(alpha: held ? 1 : 0.45), width: 2),
          boxShadow: held
              ? <BoxShadow>[
                  BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: 1),
                ]
              : const <BoxShadow>[],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 36, color: held ? const Color(0xFF04221E) : color),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: held ? const Color(0xFF04221E) : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

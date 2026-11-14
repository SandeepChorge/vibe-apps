import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Normalized stick position.
///
/// [x] is −1 (left) … +1 (right).
/// [y] is −1 (back / down) … +1 (forward / up). Flutter screen-Y is inverted
/// before this value is produced.
class StickPosition {
  const StickPosition({required this.x, required this.y});

  final double x;
  final double y;

  static const StickPosition origin = StickPosition(x: 0, y: 0);

  bool get isOrigin => x == 0 && y == 0;
}

/// Drive bits derived from a normalized stick position and a deadzone.
class StickDirection {
  const StickDirection({
    required this.forward,
    required this.back,
    required this.left,
    required this.right,
  });

  final bool forward;
  final bool back;
  final bool left;
  final bool right;

  static const StickDirection stopped = StickDirection(
    forward: false,
    back: false,
    left: false,
    right: false,
  );

  static const double defaultDeadzone = 0.25;

  /// [x] and [y] are in −1…1 with +y = forward and +x = right.
  static StickDirection fromNormalized(
    double x,
    double y, {
    double deadzone = defaultDeadzone,
  }) {
    return StickDirection(
      forward: y > deadzone,
      back: y < -deadzone,
      left: x < -deadzone,
      right: x > deadzone,
    );
  }

  bool get any => forward || back || left || right;

  @override
  bool operator ==(Object other) =>
      other is StickDirection &&
      other.forward == forward &&
      other.back == back &&
      other.left == left &&
      other.right == right;

  @override
  int get hashCode => Object.hash(forward, back, left, right);
}

enum JoystickAxis { both, vertical, horizontal }

/// Game-style virtual joystick. The knob springs back to center on release.
///
/// [previewNormalized] is Flutter-style (−1…1, +x right, +y down) and, when
/// set, locks the knob there so mockups can show a deflected stick.
class VirtualJoystick extends StatefulWidget {
  const VirtualJoystick({
    super.key,
    this.axis = JoystickAxis.both,
    this.deadzone = StickDirection.defaultDeadzone,
    this.label,
    this.previewNormalized,
    this.onChanged,
  });

  final JoystickAxis axis;
  final double deadzone;
  final String? label;
  final Offset? previewNormalized;
  final ValueChanged<StickDirection>? onChanged;

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick>
    with SingleTickerProviderStateMixin {
  Offset _offset = Offset.zero;
  late final AnimationController _spring;
  Animation<Offset>? _springAnim;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        final Animation<Offset>? anim = _springAnim;
        if (anim == null) return;
        setState(() => _offset = anim.value);
      });
    if (widget.previewNormalized != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _emitNormalized(widget.previewNormalized!);
      });
    }
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  double _maxTravel(Size size) {
    final double short = math.min(size.width, size.height);
    final double knob = short * 0.16;
    return (short / 2) - knob - 6;
  }

  Offset _previewOffset(Size size) {
    final Offset? n = widget.previewNormalized;
    if (n == null) return Offset.zero;
    final double max = _maxTravel(size);
    Offset o = Offset(
      (n.dx.clamp(-1.0, 1.0)) * max,
      (n.dy.clamp(-1.0, 1.0)) * max,
    );
    return _constrain(o, max);
  }

  Offset _constrain(Offset raw, double max) {
    Offset o = raw;
    switch (widget.axis) {
      case JoystickAxis.vertical:
        o = Offset(0, o.dy);
      case JoystickAxis.horizontal:
        o = Offset(o.dx, 0);
      case JoystickAxis.both:
        break;
    }
    final double d = o.distance;
    if (d > max && d > 0) {
      o = o * (max / d);
    }
    return o;
  }

  StickDirection _directionFor(Offset offset, Size size) {
    final double max = _maxTravel(size);
    if (max <= 0) return StickDirection.stopped;
    final double x = offset.dx / max;
    final double y = -offset.dy / max; // screen down → protocol back
    return StickDirection.fromNormalized(x, y, deadzone: widget.deadzone);
  }

  void _emitNormalized(Offset flutterNorm) {
    widget.onChanged?.call(
      StickDirection.fromNormalized(
        flutterNorm.dx,
        -flutterNorm.dy,
        deadzone: widget.deadzone,
      ),
    );
  }

  void _emit(Offset offset, Size size) {
    widget.onChanged?.call(_directionFor(offset, size));
  }

  void _onDragStart(DragStartDetails d, Size size) {
    if (widget.previewNormalized != null) return;
    _spring.stop();
    _dragging = true;
    _moveTo(d.localPosition, size);
  }

  void _onDragUpdate(DragUpdateDetails d, Size size) {
    if (widget.previewNormalized != null) return;
    _moveTo(d.localPosition, size);
  }

  void _onDragEnd(Size size) {
    if (widget.previewNormalized != null) return;
    _dragging = false;
    _springAnim = Tween<Offset>(begin: _offset, end: Offset.zero).animate(
      CurvedAnimation(parent: _spring, curve: Curves.easeOutCubic),
    );
    _spring.forward(from: 0);
    _emit(Offset.zero, size);
  }

  void _moveTo(Offset local, Size size) {
    final Offset center = size.center(Offset.zero);
    final Offset next = _constrain(local - center, _maxTravel(size));
    setState(() => _offset = next);
    _emit(next, size);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints _) {
        final Widget pad = AspectRatio(
          aspectRatio: widget.axis == JoystickAxis.both
              ? 1
              : (widget.axis == JoystickAxis.vertical ? 0.72 : 1 / 0.72),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints inner) {
              final Size padSize = Size(inner.maxWidth, inner.maxHeight);
              final Offset knob = widget.previewNormalized != null
                  ? _previewOffset(padSize)
                  : _offset;
              final StickDirection dir = widget.previewNormalized != null
                  ? StickDirection.fromNormalized(
                      widget.previewNormalized!.dx,
                      -widget.previewNormalized!.dy,
                      deadzone: widget.deadzone,
                    )
                  : _directionFor(knob, padSize);
              final bool active = _dragging || dir.any;
              final double short = math.min(padSize.width, padSize.height);
              final double knobR = short * 0.16;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (DragStartDetails d) => _onDragStart(d, padSize),
                onPanUpdate: (DragUpdateDetails d) => _onDragUpdate(d, padSize),
                onPanEnd: (_) => _onDragEnd(padSize),
                onPanCancel: () => _onDragEnd(padSize),
                child: CustomPaint(
                  painter: _JoystickPainter(
                    axis: widget.axis,
                    offset: knob,
                    direction: dir,
                    active: active,
                    deadzone: widget.deadzone,
                    knobRadius: knobR,
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        );

        if (widget.label == null) {
          return Center(child: pad);
        }
        return Column(
          children: <Widget>[
            Text(
              widget.label!,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: Center(child: pad)),
          ],
        );
      },
    );
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({
    required this.axis,
    required this.offset,
    required this.direction,
    required this.active,
    required this.deadzone,
    required this.knobRadius,
  });

  final JoystickAxis axis;
  final Offset offset;
  final StickDirection direction;
  final bool active;
  final double deadzone;
  final double knobRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double w = size.width;
    final double h = size.height;
    final double short = math.min(w, h);
    final double inset = 8;
    final RRect track = _track(size, inset);
    final double ringR = axis == JoystickAxis.both ? (short / 2) - inset : 0;

    // Soft outer glow.
    final Paint glow = Paint()
      ..color = AppColors.teal.withValues(alpha: active ? 0.38 : 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    if (axis == JoystickAxis.both) {
      canvas.drawCircle(c, ringR + 2, glow);
    } else {
      canvas.drawRRect(track.inflate(4), glow);
    }

    // Disc / capsule fill.
    final Rect bounds = axis == JoystickAxis.both
        ? Rect.fromCircle(center: c, radius: ringR)
        : track.outerRect;
    final Paint fill = Paint()
      ..shader = RadialGradient(
        colors: const <Color>[
          Color(0xFF1B242E),
          Color(0xFF10161C),
        ],
        radius: 0.85,
      ).createShader(bounds);
    if (axis == JoystickAxis.both) {
      canvas.drawCircle(c, ringR, fill);
    } else {
      canvas.drawRRect(track, fill);
    }

    // Inner hairline ring.
    final Paint innerRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppColors.border.withValues(alpha: 0.9);
    if (axis == JoystickAxis.both) {
      canvas.drawCircle(c, ringR - 10, innerRing);
    } else {
      canvas.drawRRect(track.deflate(10), innerRing);
    }

    // Deadzone hint.
    final Paint dz = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.teal.withValues(alpha: 0.12);
    if (axis == JoystickAxis.both) {
      canvas.drawCircle(c, (ringR - 12) * deadzone, dz);
    }

    // Axis groove for 1-axis sticks.
    final Paint groove = Paint()
      ..color = AppColors.teal.withValues(alpha: 0.16)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (axis == JoystickAxis.vertical) {
      canvas.drawLine(
        Offset(c.dx, track.top + knobRadius + 6),
        Offset(c.dx, track.bottom - knobRadius - 6),
        groove,
      );
    } else if (axis == JoystickAxis.horizontal) {
      canvas.drawLine(
        Offset(track.left + knobRadius + 6, c.dy),
        Offset(track.right - knobRadius - 6, c.dy),
        groove,
      );
    }

    // Glowing teal ring.
    final Paint ringGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = AppColors.teal.withValues(alpha: active ? 0.35 : 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = AppColors.teal.withValues(alpha: active ? 1 : 0.85);
    if (axis == JoystickAxis.both) {
      canvas.drawCircle(c, ringR, ringGlow);
      canvas.drawCircle(c, ringR, ring);
    } else {
      canvas.drawRRect(track, ringGlow);
      canvas.drawRRect(track, ring);
    }

    _paintArrows(canvas, c, axis == JoystickAxis.both ? ringR : (short / 2), size, track);

    // Knob.
    final Offset kc = c + offset;
    final Paint knobGlow = Paint()
      ..color = AppColors.teal.withValues(alpha: active ? 0.45 : 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(kc, knobRadius + 2, knobGlow);

    final Paint knobFill = Paint()
      ..shader = RadialGradient(
        colors: const <Color>[
          Color(0xFF2A3540),
          Color(0xFF151C24),
        ],
        radius: 0.85,
        center: const Alignment(-0.3, -0.35),
      ).createShader(Rect.fromCircle(center: kc, radius: knobRadius));
    canvas.drawCircle(kc, knobRadius, knobFill);

    final Paint knobRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = active ? AppColors.teal : const Color(0xFF3A4754);
    canvas.drawCircle(kc, knobRadius, knobRim);

    final Paint dimple = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = AppColors.teal.withValues(alpha: active ? 0.7 : 0.35);
    canvas.drawCircle(kc, knobRadius * 0.42, dimple);
    canvas.drawCircle(
      kc,
      2.2,
      Paint()..color = AppColors.teal.withValues(alpha: active ? 0.9 : 0.45),
    );
  }

  RRect _track(Size size, double inset) {
    final Radius rad = Radius.circular(math.min(size.width, size.height));
    return RRect.fromLTRBR(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
      rad,
    );
  }

  void _paintArrows(Canvas canvas, Offset c, double r, Size size, RRect track) {
    final bool showV = axis != JoystickAxis.horizontal;
    final bool showH = axis != JoystickAxis.vertical;
    final double reach = axis == JoystickAxis.both ? r * 0.72 : 0;

    if (showV) {
      final double yUp = axis == JoystickAxis.both ? c.dy - reach : track.top + 22;
      final double yDn = axis == JoystickAxis.both ? c.dy + reach : track.bottom - 22;
      _arrow(canvas, Offset(c.dx, yUp), -math.pi / 2, direction.forward);
      _arrow(canvas, Offset(c.dx, yDn), math.pi / 2, direction.back);
    }
    if (showH) {
      final double xL = axis == JoystickAxis.both ? c.dx - reach : track.left + 22;
      final double xR = axis == JoystickAxis.both ? c.dx + reach : track.right - 22;
      _arrow(canvas, Offset(xL, c.dy), math.pi, direction.left);
      _arrow(canvas, Offset(xR, c.dy), 0, direction.right);
    }
  }

  void _arrow(Canvas canvas, Offset at, double angle, bool lit) {
    final double len = lit ? 13.5 : 11;
    final double half = lit ? 9.0 : 7.5;
    final Path path = Path()
      ..moveTo(len, 0)
      ..lineTo(-len * 0.55, half)
      ..lineTo(-len * 0.25, 0)
      ..lineTo(-len * 0.55, -half)
      ..close();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle);
    if (lit) {
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xCC7DFFE8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lit ? const Color(0xFFB8FFF3) : AppColors.teal.withValues(alpha: 0.55),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter old) {
    return old.offset != offset ||
        old.direction != direction ||
        old.active != active ||
        old.axis != axis ||
        old.knobRadius != knobRadius;
  }
}

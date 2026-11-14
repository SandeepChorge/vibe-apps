import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Vehicle types encoded in the official protocol FLAG byte (01 / 02 / 03).
class CarType {
  const CarType({
    required this.flag,
    required this.label,
    required this.kind,
  });

  final int flag;
  final String label;
  final CarKind kind;

  static const List<CarType> all = <CarType>[
    CarType(flag: 1, label: 'Car', kind: CarKind.car),
    CarType(flag: 2, label: 'Dump truck', kind: CarKind.dumpTruck),
    CarType(flag: 3, label: 'Excavator', kind: CarKind.excavator),
  ];
}

enum CarKind { car, dumpTruck, excavator }

class CarTypeSelector extends StatelessWidget {
  const CarTypeSelector({
    super.key,
    required this.flag,
    required this.onChanged,
    this.large = false,
  });

  final int flag;
  final ValueChanged<int> onChanged;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final double padV = large ? 16 : 8;
    final double padH = large ? 10 : 4;
    final double iconSize = large ? 44 : 22;
    final double fontSize = large ? 15 : 10;
    final double radius = large ? 18 : 14;

    return Container(
      padding: EdgeInsets.all(large ? 6 : 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: CarType.all.map((CarType type) {
          final bool selected = flag == type.flag;
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(type.flag),
              borderRadius: BorderRadius.circular(radius - 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: EdgeInsets.symmetric(vertical: padV, horizontal: padH),
                decoration: BoxDecoration(
                  color: selected ? AppColors.teal : Colors.transparent,
                  borderRadius: BorderRadius.circular(radius - 4),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    VehicleIcon(
                      kind: type.kind,
                      size: iconSize,
                      color: selected ? const Color(0xFF04221E) : AppColors.muted,
                    ),
                    SizedBox(height: large ? 8 : 4),
                    Text(
                      type.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: fontSize,
                        height: 1.1,
                        color: selected ? const Color(0xFF04221E) : AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class VehicleIcon extends StatelessWidget {
  const VehicleIcon({
    super.key,
    required this.kind,
    required this.size,
    required this.color,
  });

  final CarKind kind;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _VehiclePainter(kind: kind, color: color),
      ),
    );
  }
}

class _VehiclePainter extends CustomPainter {
  _VehiclePainter({required this.kind, required this.color});

  final CarKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.07).clamp(1.4, 2.6)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case CarKind.car:
        _paintCar(canvas, size, fill, stroke);
      case CarKind.dumpTruck:
        _paintDumpTruck(canvas, size, fill, stroke);
      case CarKind.excavator:
        _paintExcavator(canvas, size, fill, stroke);
    }
  }

  void _wheel(Canvas canvas, Offset c, double r, Paint fill) {
    canvas.drawCircle(c, r, fill);
  }

  void _paintCar(Canvas canvas, Size size, Paint fill, Paint stroke) {
    final double w = size.width;
    final double h = size.height;
    final Path body = Path()
      ..moveTo(w * 0.10, h * 0.66)
      ..lineTo(w * 0.18, h * 0.66)
      ..lineTo(w * 0.28, h * 0.40)
      ..lineTo(w * 0.64, h * 0.40)
      ..lineTo(w * 0.76, h * 0.66)
      ..lineTo(w * 0.90, h * 0.66)
      ..quadraticBezierTo(w * 0.97, h * 0.66, w * 0.97, h * 0.76)
      ..lineTo(w * 0.05, h * 0.76)
      ..quadraticBezierTo(w * 0.05, h * 0.66, w * 0.10, h * 0.66)
      ..close();
    canvas.drawPath(body, fill);
    // Cabin crease
    final Paint crease = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = (size.width * 0.055).clamp(1.2, 2.2)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.30, h * 0.52), Offset(w * 0.66, h * 0.52), crease);
    _wheel(canvas, Offset(w * 0.28, h * 0.82), w * 0.11, fill);
    _wheel(canvas, Offset(w * 0.74, h * 0.82), w * 0.11, fill);
  }

  void _paintDumpTruck(Canvas canvas, Size size, Paint fill, Paint stroke) {
    final double w = size.width;
    final double h = size.height;
    // Cab
    final RRect cab = RRect.fromLTRBR(w * 0.08, h * 0.38, w * 0.38, h * 0.78, Radius.circular(w * 0.06));
    canvas.drawRRect(cab, fill);
    // Raised dump bed
    final Path bed = Path()
      ..moveTo(w * 0.40, h * 0.62)
      ..lineTo(w * 0.46, h * 0.28)
      ..lineTo(w * 0.92, h * 0.22)
      ..lineTo(w * 0.90, h * 0.52)
      ..lineTo(w * 0.44, h * 0.62)
      ..close();
    canvas.drawPath(bed, fill);
    // Chassis
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.10, h * 0.70, w * 0.88, h * 0.78, Radius.circular(w * 0.03)),
      fill,
    );
    _wheel(canvas, Offset(w * 0.26, h * 0.84), w * 0.10, fill);
    _wheel(canvas, Offset(w * 0.62, h * 0.84), w * 0.10, fill);
    _wheel(canvas, Offset(w * 0.80, h * 0.84), w * 0.10, fill);
  }

  void _paintExcavator(Canvas canvas, Size size, Paint fill, Paint stroke) {
    final double w = size.width;
    final double h = size.height;
    // Tracks
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.08, h * 0.70, w * 0.62, h * 0.88, Radius.circular(w * 0.08)),
      fill,
    );
    // Body / house
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.16, h * 0.42, w * 0.52, h * 0.72, Radius.circular(w * 0.06)),
      fill,
    );
    // Cab roof
    canvas.drawRRect(
      RRect.fromLTRBR(w * 0.20, h * 0.30, w * 0.42, h * 0.46, Radius.circular(w * 0.04)),
      fill,
    );
    // Boom
    stroke.strokeWidth = (size.width * 0.10).clamp(2.0, 3.6);
    canvas.drawLine(Offset(w * 0.48, h * 0.48), Offset(w * 0.78, h * 0.22), stroke);
    // Stick
    canvas.drawLine(Offset(w * 0.78, h * 0.22), Offset(w * 0.88, h * 0.58), stroke);
    // Bucket
    final Path bucket = Path()
      ..moveTo(w * 0.80, h * 0.56)
      ..lineTo(w * 0.98, h * 0.58)
      ..lineTo(w * 0.92, h * 0.74)
      ..lineTo(w * 0.78, h * 0.66)
      ..close();
    canvas.drawPath(bucket, fill);
  }

  @override
  bool shouldRepaint(covariant _VehiclePainter old) =>
      old.kind != kind || old.color != color;
}

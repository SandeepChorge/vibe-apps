import 'dart:typed_data';

/// Official LCW_RCcar 10-byte BLE control frame.
///
/// AA 00 02 00 00 00 00  [CTRL]  [AUX]  [FLAG]
///
/// CTRL bits, MSB first:
///   7        light
///   6-5      playMode (official default is binary "10")
///   4        spray
///   3        right
///   2        left
///   1        back
///   0        forward
///
/// Idle / stop with music off is 0x40.
class RcProtocol {
  static const int playModeMusicOff = 0x2; // bits "10"
  static const int minSpeed = 30;
  static const int maxSpeed = 100;
  static const int defaultSpeed = 100;
  static const int defaultFlag = 1;

  static Uint8List build({
    required bool light,
    required bool forward,
    required bool back,
    required bool left,
    required bool right,
    required int speed,
    required int flag,
    bool spray = false,
    int playMode = playModeMusicOff,
  }) {
    final int ctrl = _ctrl(
      light: light,
      playMode: playMode,
      spray: spray,
      right: right,
      left: left,
      back: back,
      forward: forward,
    );
    final int aux = speed.clamp(minSpeed, maxSpeed);
    final int fl = flag.clamp(1, 3);
    return Uint8List.fromList(<int>[
      0xAA,
      0x00,
      0x02,
      0x00,
      0x00,
      0x00,
      0x00,
      ctrl,
      aux,
      fl,
    ]);
  }

  /// Stop / idle frame. Drive bits are clear; lights, speed and flag are kept.
  static Uint8List stop({
    required bool light,
    required int speed,
    required int flag,
  }) {
    return build(
      light: light,
      forward: false,
      back: false,
      left: false,
      right: false,
      speed: speed,
      flag: flag,
    );
  }

  static int _ctrl({
    required bool light,
    required int playMode,
    required bool spray,
    required bool right,
    required bool left,
    required bool back,
    required bool forward,
  }) {
    int ctrl = 0;
    if (light) ctrl |= 1 << 7;
    ctrl |= (playMode & 0x3) << 5;
    if (spray) ctrl |= 1 << 4;
    if (right) ctrl |= 1 << 3;
    if (left) ctrl |= 1 << 2;
    if (back) ctrl |= 1 << 1;
    if (forward) ctrl |= 1 << 0;
    return ctrl;
  }

  static String toHex(List<int> bytes) {
    return bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:rock_master_rc/ble/protocol.dart';

void main() {
  test('idle / stop frame is AA 00 02 00 00 00 00 40 64 01', () {
    final frame = RcProtocol.build(
      light: false,
      forward: false,
      back: false,
      left: false,
      right: false,
      speed: 100,
      flag: 1,
    );
    expect(RcProtocol.toHex(frame), 'AA 00 02 00 00 00 00 40 64 01');
  });

  test('direction and lights packets match the official encoder', () {
    expect(
      RcProtocol.toHex(RcProtocol.build(
        light: false, forward: true, back: false, left: false, right: false, speed: 100, flag: 1,
      )),
      'AA 00 02 00 00 00 00 41 64 01',
    );
    expect(
      RcProtocol.toHex(RcProtocol.build(
        light: false, forward: false, back: true, left: false, right: false, speed: 100, flag: 1,
      )),
      'AA 00 02 00 00 00 00 42 64 01',
    );
    expect(
      RcProtocol.toHex(RcProtocol.build(
        light: false, forward: false, back: false, left: true, right: false, speed: 100, flag: 1,
      )),
      'AA 00 02 00 00 00 00 44 64 01',
    );
    expect(
      RcProtocol.toHex(RcProtocol.build(
        light: false, forward: false, back: false, left: false, right: true, speed: 100, flag: 1,
      )),
      'AA 00 02 00 00 00 00 48 64 01',
    );
    expect(
      RcProtocol.toHex(RcProtocol.build(
        light: false, forward: true, back: false, left: true, right: false, speed: 100, flag: 1,
      )),
      'AA 00 02 00 00 00 00 45 64 01',
    );
    expect(
      RcProtocol.toHex(RcProtocol.build(
        light: true, forward: false, back: false, left: false, right: false, speed: 100, flag: 1,
      )),
      'AA 00 02 00 00 00 00 C0 64 01',
    );
    expect(
      RcProtocol.toHex(RcProtocol.build(
        light: false, forward: true, back: false, left: false, right: false, speed: 30, flag: 1,
      )),
      'AA 00 02 00 00 00 00 41 1E 01',
    );
    expect(
      RcProtocol.toHex(RcProtocol.build(
        light: false, forward: true, back: false, left: false, right: false, speed: 50, flag: 2,
      )),
      'AA 00 02 00 00 00 00 41 32 02',
    );
  });

  test('speed is clamped to 30–100', () {
    expect(RcProtocol.build(
      light: false, forward: false, back: false, left: false, right: false, speed: 0, flag: 1,
    )[8], 30);
    expect(RcProtocol.build(
      light: false, forward: false, back: false, left: false, right: false, speed: 255, flag: 1,
    )[8], 100);
  });
}

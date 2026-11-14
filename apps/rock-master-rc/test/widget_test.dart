import 'package:flutter_test/flutter_test.dart';
import 'package:rock_master_rc/ble/protocol.dart';

void main() {
  // Full widget tests need a BLE platform; protocol packing is covered in
  // protocol_test.dart. This file only asserts the package loads.
  test('protocol helper is available', () {
    expect(RcProtocol.defaultSpeed, 100);
  });
}

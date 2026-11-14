import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rock_master_rc/ble/scan_list.dart';

BluetoothDevice _device(String id) {
  return BluetoothDevice(remoteId: DeviceIdentifier(id));
}

void main() {
  test(
    'location banner is only for Android 11 and older with services off',
    () {
      expect(
        showAndroidLocationBanner(sdkInt: 30, locationServicesEnabled: false),
        isTrue,
      );
      expect(
        showAndroidLocationBanner(sdkInt: 29, locationServicesEnabled: false),
        isTrue,
      );
      expect(
        showAndroidLocationBanner(sdkInt: 30, locationServicesEnabled: true),
        isFalse,
      );
      expect(
        showAndroidLocationBanner(sdkInt: 31, locationServicesEnabled: false),
        isFalse,
      );
      expect(
        showAndroidLocationBanner(sdkInt: null, locationServicesEnabled: false),
        isFalse,
      );
    },
  );

  test('merge keeps one row per remote id and prefers the scan', () {
    final BluetoothDevice car = _device('AA:BB:CC:DD:EE:FF');
    final BluetoothDevice other = _device('11:22:33:44:55:66');
    final List<ScanEntry> merged = mergeScanEntries(
      systemConnected: <ScanEntry>[
        ScanEntry(device: car, name: 'YC_CAR_DEMO', systemConnected: true),
      ],
      bonded: <ScanEntry>[
        ScanEntry(device: car, name: 'YC_CAR_DEMO', paired: true),
        ScanEntry(device: other, name: 'Other remote', paired: true),
      ],
      scanned: <ScanEntry>[
        ScanEntry(device: car, name: 'YC_CAR_DEMO', rssi: -42),
        ScanEntry(device: other, name: '11:22:33:44:55:66', rssi: -80),
      ],
    );

    expect(merged, hasLength(2));
    expect(merged.first.name, 'YC_CAR_DEMO');
    expect(merged.first.isSuggested, isTrue);
    expect(merged.first.paired, isTrue);
    expect(merged.first.systemConnected, isTrue);
    expect(merged.first.rssi, -42);
    expect(merged.last.name, 'Other remote');
    expect(merged.last.paired, isTrue);
    expect(merged.last.rssi, -80);
    expect(merged.last.systemConnected, isFalse);
  });

  test('a bonded car that is not advertising is still listed', () {
    final BluetoothDevice car = _device('AA:BB:CC:DD:EE:FF');
    final List<ScanEntry> merged = mergeScanEntries(
      systemConnected: const <ScanEntry>[],
      bonded: <ScanEntry>[
        ScanEntry(device: car, name: 'YC_CAR_DEMO', paired: true),
      ],
      scanned: const <ScanEntry>[],
    );
    expect(merged.single.isSuggested, isTrue);
    expect(merged.single.paired, isTrue);
    expect(merged.single.rssi, isNull);
  });
}

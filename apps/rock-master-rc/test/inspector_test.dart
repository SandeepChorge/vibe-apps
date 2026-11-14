import 'package:flutter_test/flutter_test.dart';
import 'package:rock_master_rc/ble/inspector.dart';
import 'package:rock_master_rc/ble/protocol.dart';
import 'package:rock_master_rc/ble/rc_controller.dart';

const String kBatteryService = '0000180f-0000-1000-8000-00805f9b34fb';
const String kBatteryLevel = '00002a19-0000-1000-8000-00805f9b34fb';
const String kCarService = '0000fff0-0000-1000-8000-00805f9b34fb';
const String kCarNotify = '0000fff1-0000-1000-8000-00805f9b34fb';
const String kCarWrite = '0000fff2-0000-1000-8000-00805f9b34fb';

void main() {
  test('short UUIDs recognise the battery service and level', () {
    expect(isBatteryServiceUuid('180F'), isTrue);
    expect(isBatteryServiceUuid(kBatteryService), isTrue);
    expect(isBatteryServiceUuid('0000180F00001000800000805f9b34fb'), isTrue);
    expect(isBatteryServiceUuid(kCarService), isFalse);
    expect(isBatteryLevelUuid('2a19'), isTrue);
    expect(isBatteryLevelUuid(kBatteryLevel), isTrue);
    expect(isBatteryLevelUuid(kBatteryService), isFalse);
    expect(bleShortUuid('not-a-uuid'), isNull);
    expect(bleFriendlyName(kBatteryLevel), 'Battery Level');
    expect(bleUuidLabel(kCarNotify), 'FFF1 Car notify');
  });

  test('property labels use read, write, writeNoResp, notify, indicate', () {
    expect(
      const BleCharProperties(
        read: true,
        write: true,
        writeNoResp: true,
        notify: true,
        indicate: true,
      ).label,
      'read, write, writeNoResp, notify, indicate',
    );
    expect(
      const BleCharProperties(read: true, notify: true).label,
      'read, notify',
    );
    expect(
      const BleCharProperties(write: true, writeNoResp: true).label,
      'write, writeNoResp',
    );
    expect(const BleCharProperties().label, 'none');
  });

  test('battery level byte is a percent from 0 to 100', () {
    expect(BatterySample.interpret(<int>[87]).percent, 87);
    expect(BatterySample.interpret(<int>[87]).detail, '87%');
    expect(BatterySample.interpret(<int>[0]).percent, 0);
    expect(BatterySample.interpret(<int>[100]).percent, 100);
    expect(BatterySample.interpret(<int>[0x57]).percent, 87);
    expect(BatterySample.interpret(<int>[87, 0xFF]).percent, 87);
    expect(BatterySample.interpret(<int>[101]).percent, isNull);
    expect(
      BatterySample.interpret(<int>[101]).detail,
      contains('outside 0–100'),
    );
    expect(BatterySample.interpret(<int>[]).detail, 'empty value');
  });

  test('hex and ascii formatting', () {
    expect(RcProtocol.toHex(<int>[0x57, 0x00, 0x41]), '57 00 41');
    expect(bleAscii(<int>[0x57, 0x00, 0x41]), 'W.A');
    expect(bleAscii(<int>[]), isEmpty);
    expect(
      formatBleTime(DateTime.utc(2026, 11, 14, 10, 18, 2, 123)),
      '10:18:02.123',
    );
  });

  test('changed-bytes hint names differing indexes and length', () {
    expect(
      changedBytesHint(<int>[0x00, 0xAD], <int>[0x00, 0xAE]),
      'changed bytes: 1 AD→AE',
    );
    expect(changedBytesHint(<int>[1, 2, 3], <int>[1, 2, 3]), isNull);
    expect(
      changedBytesHint(<int>[1, 2, 3], <int>[1, 9]),
      'changed bytes: len 3→2, 1 02→09',
    );
    expect(
      changedBytesHint(<int>[1, 2], <int>[1, 2, 3]),
      'changed bytes: len 2→3',
    );
  });

  test('notification log is newest first, counted, and capped at 500', () {
    final BleInspector inspector = BleInspector();
    addTearDown(inspector.dispose);
    final String notifyKey = bleCharKey(
      serviceUuid: kCarService,
      characteristicUuid: kCarNotify,
      instanceId: 0,
    );
    final String batteryKey = bleCharKey(
      serviceUuid: kBatteryService,
      characteristicUuid: kBatteryLevel,
      instanceId: 0,
    );
    final DateTime firstAt = DateTime.utc(2026, 11, 14, 10, 18, 1);
    final DateTime secondAt = DateTime.utc(2026, 11, 14, 10, 18, 2, 50);

    inspector.recordPacket(
      key: notifyKey,
      characteristicUuid: kCarNotify,
      bytes: <int>[0x10, 0x00],
      at: firstAt,
    );
    inspector.recordPacket(
      key: batteryKey,
      characteristicUuid: kBatteryLevel,
      bytes: <int>[87],
      at: firstAt,
    );
    inspector.recordPacket(
      key: notifyKey,
      characteristicUuid: kCarNotify,
      bytes: <int>[0x10, 0x01],
      at: secondAt,
    );

    expect(inspector.packets, hasLength(3));
    expect(inspector.packets.first.characteristicUuid, kCarNotify);
    expect(inspector.packets.first.changedBytes, 'changed bytes: 1 00→01');
    expect(inspector.packets[1].changedBytes, isNull);
    expect(inspector.packets[1].bytes, <int>[87]);
    expect(inspector.batteryPercent, 87);
    expect(inspector.packetCounts[notifyKey], 2);
    expect(inspector.packetCounts[batteryKey], 1);
    expect(inspector.totalPackets, 3);
    expect(
      inspector.countsLine(),
      'FFF1 Car notify × 2   2A19 Battery Level × 1',
    );

    inspector.clearPackets();
    expect(inspector.packets, isEmpty);
    expect(inspector.totalPackets, 0);
    expect(inspector.batteryPercent, 87);

    inspector.recordPacket(
      key: notifyKey,
      characteristicUuid: kCarNotify,
      bytes: <int>[0x10, 0x01],
      at: secondAt,
    );
    expect(inspector.packets.single.changedBytes, isNull);

    for (int i = 0; i < 505; i++) {
      inspector.recordPacket(
        key: notifyKey,
        characteristicUuid: kCarNotify,
        bytes: <int>[i & 0xFF],
        at: DateTime.utc(2026, 1, 1, 0, 0, 0, i % 1000),
      );
    }
    expect(inspector.packets, hasLength(kBlePacketLogCap));
    expect(inspector.totalPackets, 506);
    // One packet was recorded before the 505-item burst, so six oldest rows
    // drop and the oldest row kept is byte 5.
    expect(inspector.packets.first.bytes, <int>[504 & 0xFF]);
    expect(inspector.packets.last.bytes, <int>[5]);
  });

  test('read values stay on the characteristic and out of the packet log', () {
    final BleInspector inspector = BleInspector();
    addTearDown(inspector.dispose);
    final String batteryKey = bleCharKey(
      serviceUuid: kBatteryService,
      characteristicUuid: kBatteryLevel,
      instanceId: 0,
    );
    inspector.setServices(<BleServiceView>[
      BleServiceView(
        uuid: kBatteryService,
        primary: true,
        characteristics: <BleCharView>[
          BleCharView(
            key: batteryKey,
            serviceUuid: kBatteryService,
            uuid: kBatteryLevel,
            instanceId: 0,
            properties: const BleCharProperties(read: true, notify: true),
          ),
        ],
      ),
    ]);
    expect(inspector.batteryServicePresent, isTrue);
    expect(inspector.batteryLevelPresent, isTrue);
    inspector.applyRead(batteryKey, <int>[0x57]);
    expect(inspector.batteryPercent, 87);
    expect(inspector.charByKey(batteryKey)!.value, <int>[0x57]);
    expect(bleAscii(inspector.charByKey(batteryKey)!.value!), 'W');
    expect(inspector.packets, isEmpty);

    final String text = inspector.copyText(deviceName: 'YC_CAR_DEMO');
    expect(text, contains('Device: YC_CAR_DEMO'));
    expect(text, contains('Battery: 87%'));
    expect(text, contains('hex 57'));
    expect(text, contains('ascii W'));
    expect(text, contains('read, notify'));
    expect(text, contains('No notifications yet.'));
  });

  test(
    'read echo filter keeps real notifications and drops the read payload',
    () {
      final BleReadEchoFilter filter = BleReadEchoFilter();
      const String key = 'battery';
      expect(filter.onValue(key, <int>[1]), <List<int>>[
        <int>[1],
      ]);

      filter.begin(key);
      expect(filter.onValue(key, <int>[9, 9]), isEmpty);
      expect(filter.onValue(key, <int>[87]), isEmpty);
      expect(filter.finish(key, <int>[87]), <List<int>>[
        <int>[9, 9],
      ]);
      // That 87 was the read echo, so a later copy is a real notification.
      expect(filter.onValue(key, <int>[87]), <List<int>>[
        <int>[87],
      ]);

      filter.begin(key);
      expect(filter.finish(key, <int>[4]), isEmpty);
      expect(filter.onValue(key, <int>[4]), isEmpty);

      filter.begin(key);
      expect(filter.finish(key, <int>[5]), isEmpty);
      filter.expireEcho(key);
      expect(filter.onValue(key, <int>[5]), <List<int>>[
        <int>[5],
      ]);

      filter.begin(key);
      filter.onValue(key, <int>[3]);
      expect(filter.fail(key), <List<int>>[
        <int>[3],
      ]);
    },
  );

  test('drive frames stay at 100 ms and ignore the inspector log', () {
    final RcController controller = RcController.preview();
    addTearDown(controller.dispose);
    expect(RcController.commandInterval, const Duration(milliseconds: 100));

    controller.inspector.recordPacket(
      key: 'notify',
      characteristicUuid: kCarNotify,
      bytes: <int>[0xDE, 0xAD],
      at: DateTime.utc(2026, 11, 14, 10, 0, 0),
    );
    controller.setForward(true);
    expect(controller.lastHex, 'AA 00 02 00 00 00 00 41 64 01');
    expect(controller.inspector.packets, hasLength(1));

    controller.setLight(true);
    controller.setForward(false);
    controller.setBack(false);
    controller.setLeft(false);
    controller.setRight(false);
    expect(
      RcProtocol.toHex(controller.currentFrame()),
      RcProtocol.toHex(
        RcProtocol.stop(
          light: true,
          speed: RcProtocol.defaultSpeed,
          flag: RcProtocol.defaultFlag,
        ),
      ),
    );
    expect(controller.inspector.packets.single.hex, 'DE AD');
    expect(controller.inspector.totalPackets, 1);
  });
}

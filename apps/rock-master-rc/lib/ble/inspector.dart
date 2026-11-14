import 'package:flutter/foundation.dart';

import 'protocol.dart';

/// Bluetooth SIG Battery Service and Battery Level (16-bit UUIDs).
const String kBatteryServiceUuid = '180f';
const String kBatteryLevelUuid = '2a19';

/// How many notification packets the debug log keeps. Older rows are dropped.
const int kBlePacketLogCap = 500;

/// Short gap after an inspector GATT operation so the 100 ms drive loop can
/// take flutter_blue_plus's per-device mutex before the next read or subscribe.
const Duration kInspectorGattGap = Duration(milliseconds: 120);

/// Assigned-number UUIDs the car is known to use, plus the standard battery ones.
String? bleFriendlyName(String uuid) {
  return switch (bleShortUuid(uuid)) {
    '1800' => 'Generic Access',
    '1801' => 'Generic Attribute',
    '180a' => 'Device Information',
    '180f' => 'Battery Service',
    '2a00' => 'Device Name',
    '2a01' => 'Appearance',
    '2a19' => 'Battery Level',
    '2a29' => 'Manufacturer Name',
    'fff0' => 'Car service',
    'fff1' => 'Car notify',
    'fff2' => 'Car write',
    _ => null,
  };
}

/// 16-bit Bluetooth UUID (`180f`) or null when [uuid] is not that short form.
///
/// Accepts `180f`, `0000180f-0000-1000-8000-00805f9b34fb`, and the same value
/// without dashes.
String? bleShortUuid(String uuid) {
  final String raw = uuid.trim().toLowerCase();
  if (RegExp(r'^[0-9a-f]{4}$').hasMatch(raw)) return raw;
  final String n = raw.replaceAll('-', '');
  if (n.length == 32 &&
      n.startsWith('0000') &&
      n.substring(8) == '00001000800000805f9b34fb') {
    final String short = n.substring(4, 8);
    if (RegExp(r'^[0-9a-f]{4}$').hasMatch(short)) return short;
  }
  return null;
}

bool isBatteryServiceUuid(String uuid) =>
    bleShortUuid(uuid) == kBatteryServiceUuid;

bool isBatteryLevelUuid(String uuid) => bleShortUuid(uuid) == kBatteryLevelUuid;

String bleUuidLabel(String uuid) {
  final String? name = bleFriendlyName(uuid);
  final String? short = bleShortUuid(uuid);
  if (short == null) return uuid;
  final String hex = short.toUpperCase();
  if (name == null) return hex;
  return '$hex $name';
}

String bleCharKey({
  required String serviceUuid,
  required String characteristicUuid,
  required int instanceId,
}) {
  return '$serviceUuid|$characteristicUuid|$instanceId';
}

/// `HH:mm:ss.SSS` from the fields of [t] (no timezone conversion).
String formatBleTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
}

/// Printable ASCII, with any other byte shown as `.`.
String bleAscii(List<int> bytes) {
  final StringBuffer out = StringBuffer();
  for (final int b in bytes) {
    final int v = b & 0xFF;
    if (v >= 0x20 && v <= 0x7E) {
      out.writeCharCode(v);
    } else {
      out.write('.');
    }
  }
  return out.toString();
}

/// Battery Level is a uint8 percent, 0–100. Other values are not a percent.
class BatterySample {
  const BatterySample({this.percent, required this.detail});

  final int? percent;
  final String detail;

  static BatterySample interpret(List<int> bytes) {
    if (bytes.isEmpty) {
      return const BatterySample(detail: 'empty value');
    }
    final int v = bytes[0] & 0xFF;
    if (v <= 100) {
      return BatterySample(percent: v, detail: '$v%');
    }
    return BatterySample(detail: 'byte $v is outside 0–100');
  }
}

class BleCharProperties {
  const BleCharProperties({
    this.read = false,
    this.write = false,
    this.writeNoResp = false,
    this.notify = false,
    this.indicate = false,
  });

  final bool read;
  final bool write;
  final bool writeNoResp;
  final bool notify;
  final bool indicate;

  bool get notifies => notify || indicate;

  /// Active properties, in the order read, write, writeNoResp, notify, indicate.
  String get label {
    final List<String> parts = <String>[
      if (read) 'read',
      if (write) 'write',
      if (writeNoResp) 'writeNoResp',
      if (notify) 'notify',
      if (indicate) 'indicate',
    ];
    return parts.isEmpty ? 'none' : parts.join(', ');
  }
}

class BleCharView {
  BleCharView({
    required this.key,
    required this.serviceUuid,
    required this.uuid,
    required this.instanceId,
    required this.properties,
  });

  final String key;
  final String serviceUuid;
  final String uuid;
  final int instanceId;
  final BleCharProperties properties;

  List<int>? value;
  String? readError;

  bool get isBatteryLevel => isBatteryLevelUuid(uuid);
}

class BleServiceView {
  BleServiceView({
    required this.uuid,
    required this.primary,
    required this.characteristics,
  });

  final String uuid;
  final bool primary;
  final List<BleCharView> characteristics;

  bool get isBatteryService => isBatteryServiceUuid(uuid);
}

class BlePacket {
  BlePacket({
    required this.at,
    required this.key,
    required this.characteristicUuid,
    required this.bytes,
    required this.changedBytes,
  });

  final DateTime at;
  final String key;
  final String characteristicUuid;
  final List<int> bytes;
  final String? changedBytes;

  int get length => bytes.length;

  String get hex => bytes.isEmpty ? '' : RcProtocol.toHex(bytes);
}

/// Hint describing which bytes changed between two consecutive packets.
///
/// Null when the payloads are identical. Length changes are included.
String? changedBytesHint(List<int> previous, List<int> next) {
  if (_bytesEqual(previous, next)) return null;
  final List<String> parts = <String>[];
  if (previous.length != next.length) {
    parts.add('len ${previous.length}→${next.length}');
  }
  final int shared = previous.length < next.length
      ? previous.length
      : next.length;
  for (int i = 0; i < shared; i++) {
    final int a = previous[i] & 0xFF;
    final int b = next[i] & 0xFF;
    if (a != b) {
      parts.add('$i ${_hexByte(a)}→${_hexByte(b)}');
    }
  }
  if (parts.isEmpty) return null;
  return 'changed bytes: ${parts.join(', ')}';
}

/// Drops the `onValueReceived` echo of a GATT read so a read is not logged
/// as a notification. A different payload that arrives during the read is kept.
class BleReadEchoFilter {
  final Map<String, int> _open = <String, int>{};
  final Map<String, List<List<int>>> _buffered = <String, List<List<int>>>{};
  final Map<String, List<int>> _echo = <String, List<int>>{};

  void begin(String key) {
    _open[key] = (_open[key] ?? 0) + 1;
  }

  /// Notifications to log now. Empty when [value] was buffered or was the echo.
  List<List<int>> onValue(String key, List<int> value) {
    final List<int> owned = List<int>.from(value);
    if ((_open[key] ?? 0) > 0) {
      _buffered.putIfAbsent(key, () => <List<int>>[]).add(owned);
      return const <List<int>>[];
    }
    final List<int>? echo = _echo[key];
    if (echo != null && _bytesEqual(echo, owned)) {
      _echo.remove(key);
      return const <List<int>>[];
    }
    return <List<int>>[owned];
  }

  /// Call when the read completes. Drops one buffered copy of [value].
  List<List<int>> finish(String key, List<int> value) {
    _close(key);
    final List<List<int>> buffered = _buffered.remove(key) ?? <List<int>>[];
    final List<int> owned = List<int>.from(value);
    final List<List<int>> real = <List<int>>[];
    bool dropped = false;
    for (final List<int> packet in buffered) {
      if (!dropped && _bytesEqual(packet, owned)) {
        dropped = true;
        continue;
      }
      real.add(packet);
    }
    if (!dropped) _echo[key] = owned;
    return real;
  }

  /// Call when the read throws. Buffered values are real notifications.
  List<List<int>> fail(String key) {
    _close(key);
    final List<List<int>> buffered = _buffered.remove(key) ?? <List<int>>[];
    return buffered;
  }

  void expireEcho(String key) {
    _echo.remove(key);
  }

  void reset() {
    _open.clear();
    _buffered.clear();
    _echo.clear();
  }

  void _close(String key) {
    final int left = (_open[key] ?? 1) - 1;
    if (left <= 0) {
      _open.remove(key);
    } else {
      _open[key] = left;
    }
  }
}

/// GATT snapshot, battery reading, and the notification log for the debug screen.
class BleInspector extends ChangeNotifier {
  List<BleServiceView> services = <BleServiceView>[];
  final List<BlePacket> packets = <BlePacket>[];
  final Map<String, int> packetCounts = <String, int>{};
  final Map<String, String> countLabels = <String, String>{};
  final Set<String> subscribedKeys = <String>{};
  final Map<String, String> subscribeErrors = <String, String>{};

  int? batteryPercent;
  String? batteryDetail;
  bool reading = false;
  String? statusMessage;

  final Map<String, List<int>> _previous = <String, List<int>>{};

  bool get batteryServicePresent =>
      services.any((BleServiceView s) => s.isBatteryService);

  bool get batteryLevelPresent => services.any(
    (BleServiceView s) =>
        s.characteristics.any((BleCharView c) => c.isBatteryLevel),
  );

  int get totalPackets =>
      packetCounts.values.fold<int>(0, (int sum, int n) => sum + n);

  BleCharView? charByKey(String key) {
    for (final BleServiceView service in services) {
      for (final BleCharView characteristic in service.characteristics) {
        if (characteristic.key == key) return characteristic;
      }
    }
    return null;
  }

  BleCharView? get batteryLevel {
    for (final BleServiceView service in services) {
      for (final BleCharView characteristic in service.characteristics) {
        if (characteristic.isBatteryLevel) return characteristic;
      }
    }
    return null;
  }

  void reset() {
    services = <BleServiceView>[];
    packets.clear();
    packetCounts.clear();
    countLabels.clear();
    subscribedKeys.clear();
    subscribeErrors.clear();
    _previous.clear();
    batteryPercent = null;
    batteryDetail = null;
    reading = false;
    statusMessage = null;
    notifyListeners();
  }

  void setServices(List<BleServiceView> next) {
    services = next;
    notifyListeners();
  }

  void markSubscribed(String key) {
    subscribeErrors.remove(key);
    subscribedKeys.add(key);
    notifyListeners();
  }

  void setSubscribeError(String key, String message) {
    subscribeErrors[key] = message;
    notifyListeners();
  }

  void setReading(bool value) {
    reading = value;
    notifyListeners();
  }

  void setStatus(String? message) {
    statusMessage = message;
    notifyListeners();
  }

  void applyRead(String key, List<int> bytes) {
    final BleCharView? characteristic = charByKey(key);
    if (characteristic == null) return;
    characteristic.value = List<int>.from(bytes);
    characteristic.readError = null;
    if (characteristic.isBatteryLevel) {
      final BatterySample sample = BatterySample.interpret(bytes);
      batteryPercent = sample.percent;
      batteryDetail = sample.detail;
    }
    notifyListeners();
  }

  void applyReadError(String key, String message) {
    final BleCharView? characteristic = charByKey(key);
    if (characteristic == null) return;
    characteristic.readError = message;
    notifyListeners();
  }

  void recordPacket({
    required String key,
    required String characteristicUuid,
    required List<int> bytes,
    DateTime? at,
  }) {
    final List<int> owned = List<int>.from(bytes);
    final List<int>? previous = _previous[key];
    final String? hint = previous == null
        ? null
        : changedBytesHint(previous, owned);
    _previous[key] = owned;
    packetCounts[key] = (packetCounts[key] ?? 0) + 1;
    countLabels[key] = bleUuidLabel(characteristicUuid);
    packets.insert(
      0,
      BlePacket(
        at: at ?? DateTime.now(),
        key: key,
        characteristicUuid: characteristicUuid,
        bytes: owned,
        changedBytes: hint,
      ),
    );
    if (packets.length > kBlePacketLogCap) {
      packets.removeRange(kBlePacketLogCap, packets.length);
    }
    if (isBatteryLevelUuid(characteristicUuid)) {
      final BatterySample sample = BatterySample.interpret(owned);
      batteryPercent = sample.percent;
      batteryDetail = sample.detail;
    }
    notifyListeners();
  }

  void clearPackets() {
    packets.clear();
    packetCounts.clear();
    countLabels.clear();
    _previous.clear();
    notifyListeners();
  }

  String countsLine() {
    if (packetCounts.isEmpty) return 'No notifications yet.';
    final List<MapEntry<String, int>> entries = packetCounts.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) {
        final int byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return a.key.compareTo(b.key);
      });
    return entries
        .map(
          (MapEntry<String, int> e) =>
              '${countLabels[e.key] ?? e.key} × ${e.value}',
        )
        .join('   ');
  }

  String copyText({String deviceName = ''}) {
    final StringBuffer out = StringBuffer()
      ..writeln('Rock Master RC BLE inspector')
      ..writeln('Device: ${deviceName.isEmpty ? '—' : deviceName}');
    if (batteryLevelPresent) {
      out.writeln('Battery: ${batteryDetail ?? 'no value yet'}');
    } else if (batteryServicePresent) {
      out.writeln(
        'Battery: service 180F present, Battery Level 2A19 not found',
      );
    } else {
      out.writeln(
        'Battery: no standard Battery Service 180F or Battery Level 2A19',
      );
    }
    out.writeln();
    out.writeln('Services');
    if (services.isEmpty) {
      out.writeln('(none)');
    }
    for (final BleServiceView service in services) {
      final String kind = service.primary ? 'primary' : 'included';
      out.writeln('${service.uuid}  ${bleUuidLabel(service.uuid)}  $kind');
      for (final BleCharView characteristic in service.characteristics) {
        final String instance = characteristic.instanceId == 0
            ? ''
            : '  #${characteristic.instanceId}';
        out.writeln(
          '  ${characteristic.uuid}  ${bleUuidLabel(characteristic.uuid)}  ${characteristic.properties.label}$instance',
        );
        if (characteristic.value != null) {
          final List<int> value = characteristic.value!;
          out.writeln(
            '    hex ${value.isEmpty ? '(empty)' : RcProtocol.toHex(value)}',
          );
          final String ascii = bleAscii(value);
          out.writeln('    ascii ${ascii.isEmpty ? '(empty)' : ascii}');
        }
        if (characteristic.readError != null) {
          out.writeln('    read failed: ${characteristic.readError}');
        }
        final String? subscribeError = subscribeErrors[characteristic.key];
        if (subscribeError != null) {
          out.writeln('    subscribe failed: $subscribeError');
        }
      }
    }
    out.writeln();
    out.writeln('Notifications (newest first)');
    final int total = totalPackets;
    if (total > packets.length) {
      out.writeln(
        '${countsLine()}  (showing latest ${packets.length} of $total)',
      );
    } else {
      out.writeln(countsLine());
    }
    for (final BlePacket packet in packets) {
      final String hex = packet.hex.isEmpty ? '(empty)' : packet.hex;
      out.writeln(
        '${formatBleTime(packet.at)}  ${packet.characteristicUuid}  ${packet.length} bytes  $hex',
      );
      if (packet.changedBytes != null) {
        out.writeln('  ${packet.changedBytes}');
      }
    }
    return out.toString().trimRight();
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if ((a[i] & 0xFF) != (b[i] & 0xFF)) return false;
  }
  return true;
}

String _hexByte(int b) =>
    (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();

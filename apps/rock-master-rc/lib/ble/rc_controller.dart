import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'inspector.dart';
import 'protocol.dart';

const String kSuggestedDeviceName = 'YC_CAR_DEMO';

class ScanEntry {
  ScanEntry({required this.device, required this.rssi, required this.name});

  final BluetoothDevice device;
  final int rssi;
  final String name;

  bool get isSuggested => name == kSuggestedDeviceName;
}

class RcController extends ChangeNotifier with WidgetsBindingObserver {
  /// Drive frames are written on this period. Inspector reads and extra
  /// subscriptions yield for at least this long so they do not hold the radio.
  static const Duration commandInterval = Duration(milliseconds: 100);

  RcController() {
    WidgetsBinding.instance.addObserver(this);
    _adapterSub = FlutterBluePlus.adapterState.listen((
      BluetoothAdapterState s,
    ) {
      adapterState = s;
      notifyListeners();
    });
  }

  /// In-memory controller for widget tests and UI mockups. Does not touch BLE.
  RcController.preview({String name = 'YC_CAR_DEMO'}) : _preview = true {
    connected = true;
    deviceName = name;
    lastHex = RcProtocol.toHex(currentFrame());
  }

  BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;
  bool scanning = false;
  bool connecting = false;
  bool connected = false;
  bool discovering = false;
  String? statusMessage;
  String? errorMessage;

  final Map<DeviceIdentifier, ScanEntry> _results =
      <DeviceIdentifier, ScanEntry>{};
  List<ScanEntry> get devices {
    final List<ScanEntry> list = _results.values.toList();
    list.sort((ScanEntry a, ScanEntry b) {
      if (a.isSuggested != b.isSuggested) return a.isSuggested ? -1 : 1;
      return b.rssi.compareTo(a.rssi);
    });
    return list;
  }

  BluetoothDevice? device;
  String deviceName = '';
  Guid? serviceUuid;
  Guid? writeUuid;
  Guid? notifyUuid;
  bool usedFallbackDiscovery = false;
  String discoveryNotes = '';

  bool light = false;
  bool forward = false;
  bool back = false;
  bool left = false;
  bool right = false;
  int speed = RcProtocol.defaultSpeed;
  int flag = RcProtocol.defaultFlag;

  /// User preference. Actual write mode is [lastWriteWithoutResponse].
  bool preferWriteWithResponse = true;
  bool lastWriteWithoutResponse = false;
  String lastHex = '';
  int writeFailures = 0;

  bool _preview = false;

  /// GATT table, battery percent, and the notification log. Notifies on its
  /// own so a packet does not rebuild the drive controls.
  final BleInspector inspector = BleInspector();

  BluetoothCharacteristic? _writeChar;
  Timer? _ticker;
  bool _writeInFlight = false;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  final Map<String, StreamSubscription<List<int>>> _packetSubs =
      <String, StreamSubscription<List<int>>>{};
  final Set<String> _notifyEnabled = <String>{};
  final BleReadEchoFilter _readEchoes = BleReadEchoFilter();
  List<BluetoothCharacteristic> _discoveredChars = <BluetoothCharacteristic>[];
  bool _readAllInFlight = false;
  int _inspectSession = 0;
  Future<void>? _backgroundInspect;

  bool get bluetoothOn => adapterState == BluetoothAdapterState.on;

  String get connectionLabel {
    if (connecting) return 'Connecting…';
    if (discovering) return 'Discovering services…';
    if (connected) return 'Connected';
    return 'Disconnected';
  }

  // ---------------------------------------------------------------------------
  // Permissions & scan
  // ---------------------------------------------------------------------------

  Future<bool> requestPermissions() async {
    errorMessage = null;
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid) {
        final Map<Permission, PermissionStatus> statuses = await <Permission>[
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
        final bool scanOk =
            statuses[Permission.bluetoothScan]?.isGranted != false;
        final bool connectOk =
            statuses[Permission.bluetoothConnect]?.isGranted != false;
        // Location is only required on older Android; if it is denied on API 31+
        // (not in the active manifest) the request is a no-op / granted.
        if (!scanOk || !connectOk) {
          final bool loc =
              statuses[Permission.locationWhenInUse]?.isGranted ?? false;
          if (!loc && !scanOk) {
            errorMessage = 'Bluetooth and Location permissions are required to scan on this Android version.';
            notifyListeners();
            return false;
          }
          if (!scanOk || !connectOk) {
            errorMessage = 'Bluetooth permission was denied. Enable it in system settings.';
            notifyListeners();
            return false;
          }
        }
      } else if (Platform.isIOS) {
        final PermissionStatus st = await Permission.bluetooth.request();
        if (!st.isGranted && !st.isLimited) {
          errorMessage =
              'Bluetooth permission was denied. Enable it in Settings.';
          notifyListeners();
          return false;
        }
      }
      return true;
    } catch (e) {
      errorMessage = 'Could not request Bluetooth permissions: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> startScan() async {
    errorMessage = null;
    if (!await requestPermissions()) return;

    if (adapterState == BluetoothAdapterState.off) {
      try {
        if (Platform.isAndroid) {
          await FlutterBluePlus.turnOn();
        }
      } catch (e) {
        errorMessage = 'Turn on Bluetooth and try again.';
        notifyListeners();
        return;
      }
    }

    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      errorMessage = 'Bluetooth is off. Please turn it on.';
      notifyListeners();
      return;
    }

    await _scanSub?.cancel();
    _results.clear();
    scanning = true;
    statusMessage = 'Scanning for cars…';
    notifyListeners();

    _scanSub = FlutterBluePlus.onScanResults.listen(
      (List<ScanResult> results) {
        for (final ScanResult r in results) {
          final String name = _deviceName(r.device, r.advertisementData);
          if (name.isEmpty) continue;
          _results[r.device.remoteId] = ScanEntry(
            device: r.device,
            rssi: r.rssi,
            name: name,
          );
        }
        notifyListeners();
      },
      onError: (Object e) {
        errorMessage = 'Scan failed: $e';
        scanning = false;
        notifyListeners();
      },
    );

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidScanMode: AndroidScanMode.lowLatency,
        androidUsesFineLocation: false,
        androidCheckLocationServices: false,
        continuousUpdates: true,
      );
    } catch (e) {
      // Some older Androids still want location services on.
      try {
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 15),
          androidScanMode: AndroidScanMode.lowLatency,
          androidUsesFineLocation: true,
          androidCheckLocationServices: true,
          continuousUpdates: true,
        );
      } catch (e2) {
        errorMessage = 'Scan failed: $e2';
        scanning = false;
        notifyListeners();
        return;
      }
    }

    // Mark scanning false when the adapter stops, even if timeout already fired.
    unawaited(
      FlutterBluePlus.isScanning.where((bool s) => !s).first.then((_) {
        scanning = false;
        statusMessage = _results.isEmpty
            ? 'No named BLE devices found. Try again.'
            : 'Scan complete.';
        notifyListeners();
      }),
    );
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    scanning = false;
    notifyListeners();
  }

  static String _deviceName(BluetoothDevice d, AdvertisementData? adv) {
    if (d.platformName.trim().isNotEmpty) return d.platformName.trim();
    if (d.advName.trim().isNotEmpty) return d.advName.trim();
    final String? a = adv?.advName;
    if (a != null && a.trim().isNotEmpty) return a.trim();
    return '';
  }

  // ---------------------------------------------------------------------------
  // Connect & discover
  // ---------------------------------------------------------------------------

  Future<bool> connect(ScanEntry entry) async {
    errorMessage = null;
    _inspectSession++;
    _cancelPacketSubs();
    _readEchoes.reset();
    _discoveredChars = <BluetoothCharacteristic>[];
    _readAllInFlight = false;
    inspector.reset();
    await stopScan();
    connecting = true;
    discovering = false;
    connected = false;
    usedFallbackDiscovery = false;
    discoveryNotes = '';
    serviceUuid = null;
    writeUuid = null;
    notifyUuid = null;
    _writeChar = null;
    device = entry.device;
    deviceName = entry.name;
    statusMessage = 'Connecting to ${entry.name}…';
    notifyListeners();

    await _connSub?.cancel();
    try {
      await entry.device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 12),
      );
    } catch (e) {
      connecting = false;
      errorMessage = 'Connection failed: $e';
      notifyListeners();
      return false;
    }

    _connSub = entry.device.connectionState.listen((
      BluetoothConnectionState s,
    ) {
      final bool now = s == BluetoothConnectionState.connected;
      if (connected && !now) {
        _inspectSession++;
        _cancelPacketSubs();
        connected = false;
        connecting = false;
        discovering = false;
        _stopTicker();
        statusMessage = 'Disconnected';
        notifyListeners();
      }
    });

    discovering = true;
    statusMessage = 'Discovering services…';
    notifyListeners();

    try {
      final List<BluetoothService> services = await entry.device
          .discoverServices();
      final _Endpoints? endpoints = _pickEndpoints(services);
      if (endpoints == null) {
        await entry.device.disconnect();
        connecting = false;
        discovering = false;
        errorMessage = 'No writable BLE characteristic found. You can report the service list from nRF Connect.';
        notifyListeners();
        return false;
      }

      _writeChar = endpoints.write;
      serviceUuid = endpoints.service.uuid;
      writeUuid = endpoints.write.characteristicUuid;
      notifyUuid = endpoints.notify?.characteristicUuid;
      usedFallbackDiscovery = endpoints.fallback;
      discoveryNotes = endpoints.notes;
      _publishServices(services);

      if (endpoints.notify != null) {
        final String? notifyError = await _ensureNotify(endpoints.notify!);
        if (notifyError != null) {
          discoveryNotes =
              '${discoveryNotes.isEmpty ? '' : '$discoveryNotes; '}notify subscribe failed: $notifyError';
        }
      }

      connecting = false;
      discovering = false;
      connected = true;
      lastHex = '';
      writeFailures = 0;
      statusMessage = 'Connected to ${entry.name}';
      _startTicker();
      notifyListeners();
      final int session = _inspectSession;
      _backgroundInspect = _inspectRest(services, session);
      return true;
    } catch (e) {
      connecting = false;
      discovering = false;
      errorMessage = 'Service discovery failed: $e';
      try {
        await entry.device.disconnect();
      } catch (_) {}
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect({bool sendStopFirst = true}) async {
    _inspectSession++;
    _stopTicker();
    _cancelPacketSubs();
    if (sendStopFirst && connected) {
      forward = back = left = right = false;
      await _writeFrame(
        RcProtocol.stop(light: light, speed: speed, flag: flag),
        force: true,
      );
    }
    try {
      await device?.disconnect();
    } catch (_) {}
    connected = false;
    connecting = false;
    discovering = false;
    _writeChar = null;
    statusMessage = 'Disconnected';
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Drive state
  // ---------------------------------------------------------------------------

  void setForward(bool v) {
    forward = v;
    notifyListeners();
    unawaited(sendNow());
  }

  void setBack(bool v) {
    back = v;
    notifyListeners();
    unawaited(sendNow());
  }

  void setLeft(bool v) {
    left = v;
    notifyListeners();
    unawaited(sendNow());
  }

  void setRight(bool v) {
    right = v;
    notifyListeners();
    unawaited(sendNow());
  }

  /// Update all drive bits in one write. Used by the virtual joysticks.
  void setMotion({
    required bool forward,
    required bool back,
    required bool left,
    required bool right,
  }) {
    if (this.forward == forward &&
        this.back == back &&
        this.left == left &&
        this.right == right) {
      return;
    }
    this.forward = forward;
    this.back = back;
    this.left = left;
    this.right = right;
    notifyListeners();
    unawaited(sendNow());
  }

  void setLight(bool v) {
    light = v;
    notifyListeners();
    unawaited(sendNow());
  }

  void setSpeed(int v) {
    speed = v.clamp(RcProtocol.minSpeed, RcProtocol.maxSpeed);
    notifyListeners();
    unawaited(sendNow());
  }

  void setFlag(int v) {
    flag = v.clamp(1, 3);
    notifyListeners();
    unawaited(sendNow());
  }

  void setPreferWriteWithResponse(bool v) {
    preferWriteWithResponse = v;
    notifyListeners();
  }

  Uint8List currentFrame() {
    return RcProtocol.build(
      light: light,
      forward: forward,
      back: back,
      left: left,
      right: right,
      speed: speed,
      flag: flag,
    );
  }

  Future<void> sendNow() async {
    if (_preview) {
      lastHex = RcProtocol.toHex(currentFrame());
      notifyListeners();
      return;
    }
    await _writeFrame(currentFrame());
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(commandInterval, (_) {
      unawaited(_writeFrame(currentFrame()));
    });
    unawaited(_writeFrame(currentFrame()));
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _writeFrame(List<int> bytes, {bool force = false}) async {
    final BluetoothCharacteristic? ch = _writeChar;
    if (ch == null || !connected) return;
    if (_writeInFlight && !force) return;
    _writeInFlight = true;
    lastHex = RcProtocol.toHex(bytes);
    final bool without = _shouldWriteWithoutResponse(ch);
    lastWriteWithoutResponse = without;
    notifyListeners();
    try {
      await ch.write(bytes, withoutResponse: without, timeout: 4);
      writeFailures = 0;
    } catch (e) {
      writeFailures += 1;
      if (writeFailures == 1 || writeFailures % 8 == 0) {
        errorMessage = 'Write failed: $e';
      }
      notifyListeners();
    } finally {
      _writeInFlight = false;
    }
  }

  bool _shouldWriteWithoutResponse(BluetoothCharacteristic ch) {
    final CharacteristicProperties p = ch.properties;
    if (preferWriteWithResponse) {
      if (p.write) return false;
      if (p.writeWithoutResponse) return true;
      return false;
    }
    if (p.writeWithoutResponse) return true;
    if (p.write) return false;
    return true;
  }

  // ---------------------------------------------------------------------------
  // Service selection
  // ---------------------------------------------------------------------------

  static bool isPreferredService(Guid uuid) {
    final String s = uuid.str128.toLowerCase();
    return s.contains('0000ffe0-') ||
        s.contains('0000fff0-') ||
        uuid.str.toLowerCase() == 'ffe0' ||
        uuid.str.toLowerCase() == 'fff0';
  }

  static bool _isWritable(BluetoothCharacteristic c) =>
      c.properties.write || c.properties.writeWithoutResponse;

  static bool _isNotifiable(BluetoothCharacteristic c) =>
      c.properties.notify || c.properties.indicate;

  static _Endpoints? _pickEndpoints(List<BluetoothService> services) {
    final List<_Endpoints> exact = <_Endpoints>[];
    for (final BluetoothService svc in services) {
      if (!svc.isPrimary) continue;
      if (svc.characteristics.length != 2) continue;
      BluetoothCharacteristic? write;
      BluetoothCharacteristic? notify;
      for (final BluetoothCharacteristic c in svc.characteristics) {
        if (_isWritable(c) && write == null) write = c;
        if (_isNotifiable(c) && notify == null) notify = c;
      }
      if (write != null && notify != null) {
        exact.add(
          _Endpoints(
            service: svc,
            write: write,
            notify: notify,
            fallback: false,
            notes:
                'Matched primary service with notify + write '
                        '${isPreferredService(svc.uuid) ? '(preferred FFE0/FFF0 style)' : ''}'
                    .trim(),
          ),
        );
      }
    }
    if (exact.isNotEmpty) {
      exact.sort((a, b) {
        final int pa = isPreferredService(a.service.uuid) ? 0 : 1;
        final int pb = isPreferredService(b.service.uuid) ? 0 : 1;
        return pa.compareTo(pb);
      });
      return exact.first;
    }

    // Fallback: any service (prefer primary, prefer FFE0/FFF0) with a writable char.
    final List<_Endpoints> fallbacks = <_Endpoints>[];
    for (final BluetoothService svc in services) {
      BluetoothCharacteristic? write;
      BluetoothCharacteristic? notify;
      for (final BluetoothCharacteristic c in svc.characteristics) {
        if (_isWritable(c) && write == null) write = c;
        if (_isNotifiable(c) && notify == null) notify = c;
      }
      if (write == null) continue;
      fallbacks.add(
        _Endpoints(
          service: svc,
          write: write,
          notify: notify,
          fallback: true,
          notes:
              'Fallback: first writable characteristic '
              '${isPreferredService(svc.uuid) ? '(preferred FFE0/FFF0 style service)' : 'on ${svc.uuid.str128}'}',
        ),
      );
    }
    if (fallbacks.isEmpty) return null;
    fallbacks.sort((a, b) {
      int score(_Endpoints e) {
        int s = 0;
        if (isPreferredService(e.service.uuid)) s -= 8;
        if (e.service.isPrimary) s -= 4;
        if (e.notify != null) s -= 2;
        return s;
      }

      return score(a).compareTo(score(b));
    });
    return fallbacks.first;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (connected) {
        forward = back = left = right = false;
        unawaited(
          _writeFrame(
            RcProtocol.stop(light: light, speed: speed, flag: flag),
            force: true,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // BLE inspector (reads and extra subscriptions). Drive writes do not call this.
  // ---------------------------------------------------------------------------

  Future<void> readAllReadable() async {
    if (_preview) {
      inspector.setStatus('Connect to the car to read characteristics.');
      return;
    }
    if (!connected) {
      inspector.setStatus('Not connected.');
      return;
    }
    if (_readAllInFlight) return;
    final Future<void>? pending = _backgroundInspect;
    if (pending != null) {
      inspector.setReading(true);
      inspector.setStatus('Waiting for the connection reads to finish…');
      try {
        await pending;
      } catch (_) {}
    }
    if (!connected || _preview) {
      inspector.setReading(false);
      return;
    }
    final List<BluetoothCharacteristic> targets = _discoveredChars
        .where((BluetoothCharacteristic c) => c.properties.read)
        .toList();
    if (targets.isEmpty) {
      inspector.setReading(false);
      inspector.setStatus('No readable characteristics.');
      return;
    }
    _readAllInFlight = true;
    final int session = _inspectSession;
    inspector.setReading(true);
    int ok = 0;
    int failed = 0;
    for (int i = 0; i < targets.length; i++) {
      if (session != _inspectSession || !connected) break;
      final BluetoothCharacteristic characteristic = targets[i];
      inspector.setStatus('Reading ${i + 1} of ${targets.length}…');
      try {
        final List<int> value = await _readForInspector(
          characteristic,
          session,
        );
        if (session != _inspectSession) break;
        inspector.applyRead(_charKey(characteristic), value);
        ok += 1;
      } catch (e) {
        if (session != _inspectSession) break;
        inspector.applyReadError(_charKey(characteristic), '$e');
        failed += 1;
      }
      if (i != targets.length - 1 && session == _inspectSession && connected) {
        await Future<void>.delayed(kInspectorGattGap);
      }
    }
    _readAllInFlight = false;
    if (session != _inspectSession) return;
    inspector.setReading(false);
    inspector.setStatus(
      'Read $ok characteristic${ok == 1 ? '' : 's'}'
      '${failed == 0 ? '' : ', $failed failed'}.',
    );
  }

  void _publishServices(List<BluetoothService> services) {
    _discoveredChars = <BluetoothCharacteristic>[
      for (final BluetoothService service in services)
        ...service.characteristics,
    ];
    inspector.setServices(<BleServiceView>[
      for (final BluetoothService service in services)
        BleServiceView(
          uuid: service.uuid.str128,
          primary: service.isPrimary,
          characteristics: <BleCharView>[
            for (final BluetoothCharacteristic characteristic
                in service.characteristics)
              BleCharView(
                key: _charKey(characteristic),
                serviceUuid: service.uuid.str128,
                uuid: characteristic.characteristicUuid.str128,
                instanceId: characteristic.instanceId,
                properties: BleCharProperties(
                  read: characteristic.properties.read,
                  write: characteristic.properties.write,
                  writeNoResp: characteristic.properties.writeWithoutResponse,
                  notify: characteristic.properties.notify,
                  indicate: characteristic.properties.indicate,
                ),
              ),
          ],
        ),
    ]);
  }

  String _charKey(BluetoothCharacteristic characteristic) {
    return bleCharKey(
      serviceUuid: characteristic.serviceUuid.str128,
      characteristicUuid: characteristic.characteristicUuid.str128,
      instanceId: characteristic.instanceId,
    );
  }

  /// Subscribe to notify/indicate characteristics other than the drive one,
  /// then read Battery Level when it is readable. Yields between GATT ops so
  /// [_writeFrame] can keep the 100 ms cadence.
  Future<void> _inspectRest(
    List<BluetoothService> services,
    int session,
  ) async {
    for (final BluetoothService service in services) {
      for (final BluetoothCharacteristic characteristic
          in service.characteristics) {
        if (!characteristic.properties.notify &&
            !characteristic.properties.indicate) {
          continue;
        }
        if (session != _inspectSession || !connected) return;
        await _ensureNotify(characteristic, timeout: 2);
        if (session != _inspectSession || !connected) return;
        await Future<void>.delayed(kInspectorGattGap);
      }
    }
    if (session != _inspectSession || !connected) return;
    await _readBattery(session);
  }

  Future<void> _readBattery(int session) async {
    BluetoothCharacteristic? battery;
    for (final BluetoothCharacteristic characteristic in _discoveredChars) {
      if (isBatteryLevelUuid(characteristic.characteristicUuid.str128) &&
          characteristic.properties.read) {
        battery = characteristic;
        break;
      }
    }
    if (battery == null || session != _inspectSession || !connected) return;
    try {
      final List<int> value = await _readForInspector(battery, session);
      if (session != _inspectSession) return;
      inspector.applyRead(_charKey(battery), value);
    } catch (e) {
      if (session != _inspectSession) return;
      inspector.applyReadError(_charKey(battery), '$e');
    }
  }

  /// Returns an error string when enabling notifications fails.
  /// The drive characteristic uses the default timeout so connect behavior
  /// matches the previous single subscribe.
  Future<String?> _ensureNotify(
    BluetoothCharacteristic characteristic, {
    int timeout = 15,
  }) async {
    final String key = _charKey(characteristic);
    if (!_packetSubs.containsKey(key)) {
      final int session = _inspectSession;
      final StreamSubscription<List<int>> sub = characteristic.onValueReceived
          .listen(
            (List<int> value) {
              if (session != _inspectSession) return;
              _onIncoming(characteristic, value);
            },
            onError: (Object error) {
              if (session != _inspectSession) return;
              inspector.setSubscribeError(key, 'notification error: $error');
            },
          );
      _packetSubs[key] = sub;
      characteristic.device.cancelWhenDisconnected(sub);
    }
    if (_notifyEnabled.contains(key) || characteristic.isNotifying) {
      _notifyEnabled.add(key);
      inspector.markSubscribed(key);
      return null;
    }
    try {
      final bool indicateOnly =
          !kIsWeb &&
          Platform.isAndroid &&
          characteristic.properties.indicate &&
          !characteristic.properties.notify;
      await characteristic.setNotifyValue(
        true,
        timeout: timeout,
        forceIndications: indicateOnly,
      );
      _notifyEnabled.add(key);
      inspector.markSubscribed(key);
      return null;
    } catch (e) {
      inspector.setSubscribeError(key, '$e');
      return '$e';
    }
  }

  void _onIncoming(BluetoothCharacteristic characteristic, List<int> value) {
    final String key = _charKey(characteristic);
    final List<List<int>> packets = _readEchoes.onValue(key, value);
    for (final List<int> packet in packets) {
      inspector.recordPacket(
        key: key,
        characteristicUuid: characteristic.characteristicUuid.str128,
        bytes: packet,
      );
    }
  }

  Future<List<int>> _readForInspector(
    BluetoothCharacteristic characteristic,
    int session,
  ) async {
    final String key = _charKey(characteristic);
    _readEchoes.begin(key);
    try {
      final List<int> value = await characteristic.read(timeout: 2);
      final List<List<int>> extra = _readEchoes.finish(key, value);
      if (session == _inspectSession) {
        for (final List<int> packet in extra) {
          inspector.recordPacket(
            key: key,
            characteristicUuid: characteristic.characteristicUuid.str128,
            bytes: packet,
          );
        }
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 300), () {
            if (session == _inspectSession) _readEchoes.expireEcho(key);
          }),
        );
      }
      return value;
    } catch (e) {
      final List<List<int>> extra = _readEchoes.fail(key);
      if (session == _inspectSession) {
        for (final List<int> packet in extra) {
          inspector.recordPacket(
            key: key,
            characteristicUuid: characteristic.characteristicUuid.str128,
            bytes: packet,
          );
        }
      }
      rethrow;
    }
  }

  void _cancelPacketSubs() {
    final List<StreamSubscription<List<int>>> subs = _packetSubs.values
        .toList();
    _packetSubs.clear();
    _notifyEnabled.clear();
    for (final StreamSubscription<List<int>> sub in subs) {
      unawaited(sub.cancel());
    }
  }

  @override
  void dispose() {
    _inspectSession++;
    if (!_preview) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _stopTicker();
    _cancelPacketSubs();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _connSub?.cancel();
    if (connected && !_preview) {
      unawaited(disconnect(sendStopFirst: true));
    }
    inspector.dispose();
    super.dispose();
  }
}

class _Endpoints {
  _Endpoints({
    required this.service,
    required this.write,
    required this.notify,
    required this.fallback,
    required this.notes,
  });

  final BluetoothService service;
  final BluetoothCharacteristic write;
  final BluetoothCharacteristic? notify;
  final bool fallback;
  final String notes;
}

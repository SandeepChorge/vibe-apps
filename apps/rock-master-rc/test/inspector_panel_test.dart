import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rock_master_rc/ble/inspector.dart';
import 'package:rock_master_rc/ble/rc_controller.dart';
import 'package:rock_master_rc/control_mode.dart';
import 'package:rock_master_rc/screens/control_screen.dart';
import 'package:rock_master_rc/theme.dart';

const String kBatteryService = '0000180f-0000-1000-8000-00805f9b34fb';
const String kBatteryLevel = '00002a19-0000-1000-8000-00805f9b34fb';
const String kCarService = '0000fff0-0000-1000-8000-00805f9b34fb';
const String kCarNotify = '0000fff1-0000-1000-8000-00805f9b34fb';
const String kCarWrite = '0000fff2-0000-1000-8000-00805f9b34fb';

void main() {
  testWidgets('debug screen shows the BLE inspector, copy, and clear', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            final Map<dynamic, dynamic> args =
                call.arguments as Map<dynamic, dynamic>;
            clipboardText = args['text'] as String?;
            return null;
          case 'Clipboard.getData':
            return <String, dynamic>{'text': clipboardText};
          case 'Clipboard.hasStrings':
            return <String, bool>{
              'value': clipboardText != null && clipboardText!.isNotEmpty,
            };
          default:
            return null;
        }
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final RcController controller = RcController.preview();
    addTearDown(controller.dispose);

    final String batteryKey = bleCharKey(
      serviceUuid: kBatteryService,
      characteristicUuid: kBatteryLevel,
      instanceId: 0,
    );
    final String notifyKey = bleCharKey(
      serviceUuid: kCarService,
      characteristicUuid: kCarNotify,
      instanceId: 0,
    );
    final String writeKey = bleCharKey(
      serviceUuid: kCarService,
      characteristicUuid: kCarWrite,
      instanceId: 0,
    );
    controller.inspector.setServices(<BleServiceView>[
      BleServiceView(
        uuid: kCarService,
        primary: true,
        characteristics: <BleCharView>[
          BleCharView(
            key: notifyKey,
            serviceUuid: kCarService,
            uuid: kCarNotify,
            instanceId: 0,
            properties: const BleCharProperties(notify: true),
          ),
          BleCharView(
            key: writeKey,
            serviceUuid: kCarService,
            uuid: kCarWrite,
            instanceId: 0,
            properties: const BleCharProperties(write: true, writeNoResp: true),
          ),
        ],
      ),
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
    controller.inspector.applyRead(batteryKey, <int>[0x57]);
    controller.inspector.markSubscribed(notifyKey);
    controller.inspector.markSubscribed(batteryKey);
    final DateTime at = DateTime.utc(2026, 11, 14, 10, 18, 2, 123);
    controller.inspector.recordPacket(
      key: notifyKey,
      characteristicUuid: kCarNotify,
      bytes: <int>[0xDE, 0xAD],
      at: at,
    );
    controller.inspector.recordPacket(
      key: notifyKey,
      characteristicUuid: kCarNotify,
      bytes: <int>[0xDE, 0xAE],
      at: at,
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: ControlScreen(
          controller: controller,
          initialMode: ControlMode.buttons,
          persistMode: false,
          persistLayout: false,
          lockOrientation: false,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('debug-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ble-inspector')), findsOneWidget);
    expect(find.text('87%'), findsWidgets);
    expect(find.text('Battery Service'), findsOneWidget);
    expect(find.text('Battery Level'), findsOneWidget);
    expect(find.text('read, notify'), findsOneWidget);
    expect(find.text('write, writeNoResp'), findsOneWidget);
    expect(find.text('hex  57'), findsWidgets);
    expect(find.text('ascii  W'), findsOneWidget);
    expect(find.text('changed bytes: 1 AD→AE'), findsOneWidget);
    expect(find.textContaining('FFF1 Car notify × 2'), findsOneWidget);
    expect(find.text('DE AE'), findsOneWidget);

    final ScrollableState sheet = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('debug-sheet-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    sheet.position.jumpTo(sheet.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.byKey(const Key('ble-copy-button')));
    await tester.pump();
    await tester.pump();
    final ClipboardData? copied = await Clipboard.getData(Clipboard.kTextPlain);
    expect(copied?.text, contains('Battery: 87%'));
    expect(copied?.text, contains('DE AE'));
    expect(copied?.text, contains('changed bytes: 1 AD→AE'));
    expect(copied?.text, contains(kBatteryService));

    await tester.tap(find.byKey(const Key('ble-clear-button')));
    await tester.pump();
    expect(find.text('DE AE'), findsNothing);
    expect(find.text('87%'), findsWidgets);
    expect(find.text('No notifications yet.'), findsOneWidget);

    sheet.position.jumpTo(0);
    await tester.pump();
    await tester.tap(find.byKey(const Key('ble-read-all-button')));
    await tester.pump();
    expect(
      find.text('Connect to the car to read characteristics.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

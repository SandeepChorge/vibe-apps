import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rock_master_rc/ble/rc_controller.dart';
import 'package:rock_master_rc/screens/scan_screen.dart';
import 'package:rock_master_rc/theme.dart';

void main() {
  testWidgets(
    'scan screen shows paired car and the Android 11 location banner',
    (WidgetTester tester) async {
      final RcController controller = RcController.preview();
      addTearDown(controller.dispose);
      controller.adapterState = BluetoothAdapterState.off;
      controller.androidSdkInt = 30;
      controller.locationServicesEnabled = false;
      controller.debugSeedScanEntries(<ScanEntry>[
        ScanEntry(
          device: BluetoothDevice(
            remoteId: const DeviceIdentifier('AA:BB:CC:DD:EE:FF'),
          ),
          name: 'YC_CAR_DEMO',
          paired: true,
          systemConnected: true,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ScanScreen(
            controller: controller,
            autostart: false,
            lockOrientation: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Find your car'), findsOneWidget);
      expect(find.text('YC_CAR_DEMO'), findsOneWidget);
      expect(find.text('SUGGESTED'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Paired'), findsOneWidget);
      expect(find.byKey(const Key('bluetooth-off-banner')), findsOneWidget);
      expect(
        find.text(
          'Turn on Location: Android 11 and older needs Location on to find Bluetooth devices',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('open-location-settings')), findsOneWidget);
    },
  );
}

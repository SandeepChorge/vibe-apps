import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rock_master_rc/ble/rc_controller.dart';
import 'package:rock_master_rc/control_mode.dart';
import 'package:rock_master_rc/screens/control_screen.dart';
import 'package:rock_master_rc/theme.dart';
import 'package:rock_master_rc/widgets/car_type_selector.dart';

const Size kLogicalSize = Size(1280, 576);
const double kPixelRatio = 2;
final String kOutDir = '${Directory.current.path}/build/mockups/v102';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
  });

  testWidgets('render 1.0.2 layout and vehicle-type mockups', (WidgetTester tester) async {
    tester.view.physicalSize = Size(
      kLogicalSize.width * kPixelRatio,
      kLogicalSize.height * kPixelRatio,
    );
    tester.view.devicePixelRatio = kPixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _shot(
      tester,
      '01-joystick-edit-unlocked.png',
      mode: ControlMode.joystick,
      editing: true,
      controlsOnRight: false,
    );
    await _shot(
      tester,
      '02-joystick-locked-right.png',
      mode: ControlMode.joystick,
      editing: false,
      controlsOnRight: true,
    );
    await _shot(
      tester,
      '03-buttons-swapped.png',
      mode: ControlMode.buttons,
      editing: false,
      controlsOnRight: true,
    );
    await _shot(
      tester,
      '04-dual-sticks-swapped.png',
      mode: ControlMode.dualSticks,
      editing: false,
      throttleOnLeft: false,
    );
    await _closeUp(tester, '05-vehicle-type-selector.png');
  });
}

Future<void> _shot(
  WidgetTester tester,
  String filename, {
  required ControlMode mode,
  bool editing = false,
  bool controlsOnRight = false,
  bool throttleOnLeft = true,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  final RcController controller = RcController.preview();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    RepaintBoundary(
      key: ValueKey<String>('mockup-root-$filename'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: ControlScreen(
          key: ValueKey<String>('screen-$filename'),
          controller: controller,
          initialMode: mode,
          persistMode: false,
          persistLayout: false,
          lockOrientation: false,
          initialEditing: editing,
          initialControlsOnRight: controlsOnRight,
          initialThrottleOnLeft: throttleOnLeft,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (editing) {
    expect(find.text('Swap sides'), findsWidgets);
    expect(find.text('Lock layout'), findsOneWidget);
  } else {
    expect(find.text('Edit layout'), findsOneWidget);
  }
  await _writePng(tester, filename);
}

Future<void> _closeUp(WidgetTester tester, String filename) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  await tester.pumpWidget(
    RepaintBoundary(
      key: ValueKey<String>('mockup-root-$filename'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text(
                      'VEHICLE TYPE',
                      style: TextStyle(
                        color: AppColors.teal,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose the model that matches your car. The app still sends the original 01, 02, or 03 flag.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 14),
                    ),
                    const SizedBox(height: 28),
                    CarTypeSelector(
                      flag: 1,
                      onChanged: (_) {},
                      large: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  expect(find.text('Car'), findsOneWidget);
  expect(find.text('Dump truck'), findsOneWidget);
  expect(find.text('Excavator'), findsOneWidget);
  await _writePng(tester, filename);
}

Future<void> _writePng(WidgetTester tester, String filename) async {
  final RenderRepaintBoundary boundary = tester.renderObject(
    find.byKey(ValueKey<String>('mockup-root-$filename')),
  );
  late Uint8List png;
  late int width;
  late int height;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: kPixelRatio);
    final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('toByteData returned null for $filename');
    }
    width = image.width;
    height = image.height;
    png = bytes.buffer.asUint8List();
    image.dispose();
  });
  final File out = File('$kOutDir/$filename');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(png);
  // ignore: avoid_print
  print('wrote ${out.path} ${out.lengthSync()} bytes  $width x $height');
}

String _materialFontsDir() {
  final String root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final String dir = '$root/bin/cache/artifacts/material_fonts';
  if (root.isEmpty || !Directory(dir).existsSync()) {
    throw StateError(
      'Material fonts not found at $dir. Run with `flutter test` so FLUTTER_ROOT is set.',
    );
  }
  return dir;
}

Future<void> _loadFonts() async {
  final String dir = _materialFontsDir();
  Future<ByteData> load(String name) async {
    final Uint8List data = File('$dir/$name').readAsBytesSync();
    return ByteData.sublistView(data);
  }

  final FontLoader roboto = FontLoader('Roboto');
  for (final String name in <String>[
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    roboto.addFont(load(name));
  }
  await roboto.load();

  final FontLoader mono = FontLoader('monospace');
  mono.addFont(load('Roboto-Regular.ttf'));
  await mono.load();

  final FontLoader icons = FontLoader('MaterialIcons');
  icons.addFont(load('MaterialIcons-Regular.otf'));
  await icons.load();
}

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
import 'package:rock_master_rc/widgets/virtual_joystick.dart';

const Size kLogicalSize = Size(1280, 576);
const double kPixelRatio = 2;
final String kOutDir = '${Directory.current.path}/build/mockups';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
  });

  test('deadzone mapping: 25% threshold and diagonals', () {
    expect(StickDirection.fromNormalized(0, 0), StickDirection.stopped);
    expect(StickDirection.fromNormalized(0.25, 0.25), StickDirection.stopped);
    expect(
      StickDirection.fromNormalized(0, 0.26),
      const StickDirection(forward: true, back: false, left: false, right: false),
    );
    expect(
      StickDirection.fromNormalized(0, -0.26),
      const StickDirection(forward: false, back: true, left: false, right: false),
    );
    expect(
      StickDirection.fromNormalized(-0.7, -0.7),
      const StickDirection(forward: false, back: true, left: true, right: false),
    );
    // Flutter preview Offset(-0.72, -0.72) is up-left → forward + left
    final StickDirection upLeft = StickDirection.fromNormalized(-0.72, 0.72);
    expect(upLeft.forward, isTrue);
    expect(upLeft.left, isTrue);
    expect(upLeft.back, isFalse);
    expect(upLeft.right, isFalse);
  });

  testWidgets('render control-mode mockups', (WidgetTester tester) async {
    tester.view.physicalSize = Size(
      kLogicalSize.width * kPixelRatio,
      kLogicalSize.height * kPixelRatio,
    );
    tester.view.devicePixelRatio = kPixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _shot(
      tester,
      '01-buttons.png',
      mode: ControlMode.buttons,
    );
    await _shot(
      tester,
      '02-joystick-rest.png',
      mode: ControlMode.joystick,
    );
    await _shot(
      tester,
      '03-joystick-up-left.png',
      mode: ControlMode.joystick,
      previewJoystick: const Offset(-0.72, -0.72),
    );
    await _shot(
      tester,
      '04-dual-sticks.png',
      mode: ControlMode.dualSticks,
    );
    await _shot(
      tester,
      '05-controls-picker.png',
      mode: ControlMode.buttons,
      openModePicker: true,
    );
  });
}

Future<void> _shot(
  WidgetTester tester,
  String filename, {
  required ControlMode mode,
  Offset? previewJoystick,
  Offset? previewThrottle,
  Offset? previewSteering,
  bool openModePicker = false,
}) async {
  final RcController controller = RcController.preview();
  addTearDown(controller.dispose);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

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
          previewJoystick: previewJoystick,
          previewThrottle: previewThrottle,
          previewSteering: previewSteering,
          openModePicker: openModePicker,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (openModePicker) {
    expect(find.text('Joystick'), findsOneWidget);
    expect(find.text('Dual sticks'), findsOneWidget);
  }

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
  print("wrote ${out.path} ${out.lengthSync()} bytes  $width x $height");
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

  // Theme uses fontFamily: 'Roboto', but monospace hex falls back to the
  // default test font unless we also load a family named 'monospace'.
  final FontLoader mono = FontLoader('monospace');
  mono.addFont(load('Roboto-Regular.ttf'));
  await mono.load();

  final FontLoader icons = FontLoader('MaterialIcons');
  icons.addFont(load('MaterialIcons-Regular.otf'));
  await icons.load();
}

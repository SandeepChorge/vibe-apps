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

const Size kLogicalSize = Size(1280, 576);
const double kPixelRatio = 2;
final String kOutDir = '${Directory.current.path}/build/mockups/v102b';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFonts();
  });

  test('button column order parse accepts all 6 permutations', () {
    const List<List<ButtonColumn>> perms = <List<ButtonColumn>>[
      <ButtonColumn>[ButtonColumn.forwardBack, ButtonColumn.settings, ButtonColumn.leftRight],
      <ButtonColumn>[ButtonColumn.forwardBack, ButtonColumn.leftRight, ButtonColumn.settings],
      <ButtonColumn>[ButtonColumn.settings, ButtonColumn.forwardBack, ButtonColumn.leftRight],
      <ButtonColumn>[ButtonColumn.settings, ButtonColumn.leftRight, ButtonColumn.forwardBack],
      <ButtonColumn>[ButtonColumn.leftRight, ButtonColumn.settings, ButtonColumn.forwardBack],
      <ButtonColumn>[ButtonColumn.leftRight, ButtonColumn.forwardBack, ButtonColumn.settings],
    ];
    for (final List<ButtonColumn> order in perms) {
      expect(ButtonColumn.parse(ButtonColumn.encode(order)), order);
    }
    expect(ButtonColumn.parse(null), ButtonColumn.defaultOrder);
    expect(ButtonColumn.parse('nope'), ButtonColumn.defaultOrder);
  });

  testWidgets('render 1.0.2b buttons-column reorder mockups', (WidgetTester tester) async {
    tester.view.physicalSize = Size(
      kLogicalSize.width * kPixelRatio,
      kLogicalSize.height * kPixelRatio,
    );
    tester.view.devicePixelRatio = kPixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _shot(
      tester,
      '01-buttons-edit-unlocked.png',
      editing: true,
      order: ButtonColumn.defaultOrder,
      expectUnlocked: true,
    );
    await _shot(
      tester,
      '02-buttons-locked-steer-settings-drive.png',
      editing: false,
      order: const <ButtonColumn>[
        ButtonColumn.leftRight,
        ButtonColumn.settings,
        ButtonColumn.forwardBack,
      ],
    );
    await _shot(
      tester,
      '03-buttons-locked-drive-steer-settings.png',
      editing: false,
      order: const <ButtonColumn>[
        ButtonColumn.forwardBack,
        ButtonColumn.leftRight,
        ButtonColumn.settings,
      ],
    );
  });
}

Future<void> _shot(
  WidgetTester tester,
  String filename, {
  required bool editing,
  required List<ButtonColumn> order,
  bool expectUnlocked = false,
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
          initialMode: ControlMode.buttons,
          persistMode: false,
          persistLayout: false,
          lockOrientation: false,
          initialEditing: editing,
          initialButtonOrder: order,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('FORWARD'), findsOneWidget);
  expect(find.text('LEFT'), findsOneWidget);
  expect(find.text('Car'), findsOneWidget);
  if (expectUnlocked) {
    expect(find.text('Lock layout'), findsOneWidget);
    expect(find.text('FORWARD / BACK'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('LEFT / RIGHT'), findsOneWidget);
    expect(find.textContaining('drag a column'), findsOneWidget);
  } else {
    expect(find.text('Edit layout'), findsOneWidget);
    expect(find.text('FORWARD / BACK'), findsNothing);
  }
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

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'ble/rc_controller.dart';
import 'screens/scan_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const RockMasterApp());
}

class RockMasterApp extends StatefulWidget {
  const RockMasterApp({super.key});

  @override
  State<RockMasterApp> createState() => _RockMasterAppState();
}

class _RockMasterAppState extends State<RockMasterApp> {
  late final RcController _controller = RcController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rock Master RC',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: ScanScreen(controller: _controller),
    );
  }
}

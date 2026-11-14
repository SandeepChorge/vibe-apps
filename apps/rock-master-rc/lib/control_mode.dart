import 'package:shared_preferences/shared_preferences.dart';

enum ControlMode {
  buttons,
  joystick,
  dualSticks;

  String get id => name;

  String get label => switch (this) {
        ControlMode.buttons => 'Buttons',
        ControlMode.joystick => 'Joystick',
        ControlMode.dualSticks => 'Dual sticks',
      };

  String get subtitle => switch (this) {
        ControlMode.buttons => 'Four hold buttons for forward, back, left and right',
        ControlMode.joystick => 'One circular stick — drag to drive, release to stop',
        ControlMode.dualSticks => 'Throttle and steering sticks — like an RC transmitter',
      };

  static ControlMode fromId(String? id) => switch (id) {
        'joystick' => ControlMode.joystick,
        'dualSticks' || 'dual' => ControlMode.dualSticks,
        _ => ControlMode.buttons,
      };
}

class ControlModeStore {
  static const String key = 'control_mode';

  static Future<ControlMode> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return ControlMode.fromId(prefs.getString(key));
  }

  static Future<void> save(ControlMode mode) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, mode.id);
  }
}

/// The three independently reorderable columns in Buttons mode.
enum ButtonColumn {
  settings,
  forwardBack,
  leftRight;

  String get id => name;

  String get label => switch (this) {
        ButtonColumn.settings => 'Settings',
        ButtonColumn.forwardBack => 'Forward / Back',
        ButtonColumn.leftRight => 'Left / Right',
      };

  int get flex => this == ButtonColumn.settings ? 4 : 3;

  static const List<ButtonColumn> defaultOrder = <ButtonColumn>[
    ButtonColumn.forwardBack,
    ButtonColumn.settings,
    ButtonColumn.leftRight,
  ];

  static List<ButtonColumn> parse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return List<ButtonColumn>.from(defaultOrder);
    }
    final List<ButtonColumn> list = raw
        .split(',')
        .map((String id) => ButtonColumn.values.asNameMap()[id])
        .whereType<ButtonColumn>()
        .toList();
    if (list.length == 3 && list.toSet().length == 3) return list;
    return List<ButtonColumn>.from(defaultOrder);
  }

  static String encode(List<ButtonColumn> order) =>
      order.map((ButtonColumn c) => c.id).join(',');
}

/// Per-mode layout preferences.
///
/// Buttons: any order of the three columns (settings, forward/back, left/right).
/// Joystick: swap the stick with the settings panel.
/// Dual sticks: swap throttle and steering only.
class LayoutStore {
  static String controlsOnRightKey(ControlMode mode) =>
      'layout_${mode.id}_controlsOnRight';

  static String throttleOnLeftKey(ControlMode mode) =>
      'layout_${mode.id}_throttleOnLeft';

  static Future<bool> loadControlsOnRight(ControlMode mode) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(controlsOnRightKey(mode)) ?? false;
  }

  static Future<bool> loadThrottleOnLeft(ControlMode mode) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(throttleOnLeftKey(mode)) ?? true;
  }

  static Future<void> saveControlsOnRight(ControlMode mode, bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(controlsOnRightKey(mode), value);
  }

  static Future<void> saveThrottleOnLeft(ControlMode mode, bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(throttleOnLeftKey(mode), value);
  }

  static const String buttonOrderKey = 'layout_buttons_order';

  static Future<List<ButtonColumn>> loadButtonOrder() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return ButtonColumn.parse(prefs.getString(buttonOrderKey));
  }

  static Future<void> saveButtonOrder(List<ButtonColumn> order) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(buttonOrderKey, ButtonColumn.encode(order));
  }
}

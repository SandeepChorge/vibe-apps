import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../ble/rc_controller.dart';
import '../ble/protocol.dart';
import '../control_mode.dart';
import '../theme.dart';
import '../widgets/car_type_selector.dart';
import '../widgets/debug_panel.dart';
import '../widgets/hold_button.dart';
import '../widgets/virtual_joystick.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({
    super.key,
    required this.controller,
    this.initialMode,
    this.persistMode = true,
    this.persistLayout = true,
    this.initialEditing = false,
    this.initialControlsOnRight,
    this.initialThrottleOnLeft,
    this.initialButtonOrder,
    this.previewJoystick,
    this.previewThrottle,
    this.previewSteering,
    this.openModePicker = false,
    this.lockOrientation = true,
  });

  final RcController controller;
  final ControlMode? initialMode;
  final bool persistMode;
  final bool persistLayout;
  final bool initialEditing;
  final bool? initialControlsOnRight;
  final bool? initialThrottleOnLeft;
  final List<ButtonColumn>? initialButtonOrder;

  /// Flutter-style normalized offset (−1…1, +y down) to freeze the joystick
  /// knob for mockups. `null` means at rest (or interactive).
  final Offset? previewJoystick;
  final Offset? previewThrottle;
  final Offset? previewSteering;
  final bool openModePicker;
  final bool lockOrientation;

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  late ControlMode _mode;
  bool _pickerOpened = false;
  late bool _editing;
  late bool _controlsOnRight;
  late bool _throttleOnLeft;
  late List<ButtonColumn> _buttonOrder;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode ?? ControlMode.buttons;
    _editing = widget.initialEditing;
    _controlsOnRight = widget.initialControlsOnRight ?? false;
    _throttleOnLeft = widget.initialThrottleOnLeft ?? true;
    _buttonOrder = List<ButtonColumn>.from(
      widget.initialButtonOrder ?? ButtonColumn.defaultOrder,
    );
    if (widget.lockOrientation) {
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (widget.persistMode && widget.initialMode == null) {
      ControlModeStore.load().then((ControlMode m) {
        if (mounted) {
          setState(() => _mode = m);
          _loadLayout();
        }
      });
    }
    if (widget.persistLayout &&
        widget.initialControlsOnRight == null &&
        widget.initialThrottleOnLeft == null &&
        widget.initialButtonOrder == null) {
      _loadLayout();
    }
    if (widget.openModePicker) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_pickerOpened) {
          _pickerOpened = true;
          _openModePicker();
        }
      });
    }
  }

  @override
  void didUpdateWidget(ControlScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMode != null && widget.initialMode != _mode) {
      _mode = widget.initialMode!;
    }
    if (widget.initialEditing != oldWidget.initialEditing) {
      _editing = widget.initialEditing;
    }
    if (widget.initialControlsOnRight != null) {
      _controlsOnRight = widget.initialControlsOnRight!;
    }
    if (widget.initialThrottleOnLeft != null) {
      _throttleOnLeft = widget.initialThrottleOnLeft!;
    }
    if (widget.initialButtonOrder != null) {
      _buttonOrder = List<ButtonColumn>.from(widget.initialButtonOrder!);
    }
    if (widget.openModePicker && !_pickerOpened) {
      _pickerOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openModePicker();
      });
    }
  }

  Future<void> _loadLayout() async {
    if (!widget.persistLayout) return;
    final bool right = await LayoutStore.loadControlsOnRight(_mode);
    final bool throttleLeft = await LayoutStore.loadThrottleOnLeft(_mode);
    final List<ButtonColumn> buttons = await LayoutStore.loadButtonOrder();
    if (!mounted) return;
    setState(() {
      _controlsOnRight = right;
      _throttleOnLeft = throttleLeft;
      _buttonOrder = buttons;
    });
  }

  Future<void> _persistLayout() async {
    if (!widget.persistLayout) return;
    await LayoutStore.saveControlsOnRight(_mode, _controlsOnRight);
    await LayoutStore.saveThrottleOnLeft(_mode, _throttleOnLeft);
    await LayoutStore.saveButtonOrder(_buttonOrder);
  }

  @override
  void dispose() {
    if (widget.lockOrientation) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    super.dispose();
  }

  Future<void> _leave() async {
    widget.controller.setMotion(
      forward: false,
      back: false,
      left: false,
      right: false,
    );
    await widget.controller.disconnect(sendStopFirst: true);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _setMode(ControlMode mode) async {
    widget.controller.setMotion(
      forward: false,
      back: false,
      left: false,
      right: false,
    );
    setState(() => _mode = mode);
    if (widget.persistMode) {
      await ControlModeStore.save(mode);
    }
    if (widget.initialControlsOnRight == null &&
        widget.initialThrottleOnLeft == null &&
        widget.initialButtonOrder == null) {
      await _loadLayout();
    }
  }

  Future<void> _toggleEditing() async {
    if (_editing) {
      await _persistLayout();
    }
    if (mounted) setState(() => _editing = !_editing);
  }

  Future<void> _swapSides() async {
    setState(() {
      if (_mode == ControlMode.dualSticks) {
        _throttleOnLeft = !_throttleOnLeft;
      } else {
        _controlsOnRight = !_controlsOnRight;
      }
    });
    await _persistLayout();
  }

  Future<void> _moveButtonColumn(int index, int delta) async {
    final int next = index + delta;
    if (next < 0 || next >= _buttonOrder.length) return;
    setState(() {
      final ButtonColumn col = _buttonOrder.removeAt(index);
      _buttonOrder.insert(next, col);
    });
    await _persistLayout();
  }

  Future<void> _onReorderButtons(int oldIndex, int newIndex) async {
    setState(() {
      final ButtonColumn col = _buttonOrder.removeAt(oldIndex);
      _buttonOrder.insert(newIndex, col);
    });
    await _persistLayout();
  }

  void _applyStick(StickDirection d) {
    widget.controller.setMotion(
      forward: d.forward,
      back: d.back,
      left: d.left,
      right: d.right,
    );
  }

  void _openModePicker() {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xCC05070A),
      builder: (BuildContext ctx) {
        return Dialog(
          backgroundColor: AppColors.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: AppColors.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(Icons.sports_esports, color: AppColors.teal, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'CONTROLS',
                        style: TextStyle(
                          color: AppColors.teal,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose how you drive the car. Your choice is remembered.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  ...ControlMode.values.map((ControlMode m) {
                    final bool selected = m == _mode;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ModeTile(
                        mode: m,
                        selected: selected,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _setMode(m);
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openDebug() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        final double h = MediaQuery.sizeOf(ctx).height;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: h * 0.85),
            child: SingleChildScrollView(
              key: const Key('debug-sheet-scroll'),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: DebugPanel(controller: widget.controller),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final RcController c = widget.controller;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) _leave();
      },
      child: AnimatedBuilder(
        animation: c,
        builder: (BuildContext context, _) {
          if (!c.connected && !c.connecting && !c.discovering) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && Navigator.of(context).canPop()) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('Disconnected from the car')),
                );
                Navigator.of(context).pop();
              }
            });
          }
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  children: <Widget>[
                    _TopBar(
                      name: c.deviceName,
                      status: c.connectionLabel,
                      connected: c.connected,
                      editing: _editing,
                      onBack: _leave,
                      onToggleEdit: _toggleEditing,
                      onControls: _openModePicker,
                      onDebug: _openDebug,
                    ),
                    if (_editing) ...<Widget>[
                      const SizedBox(height: 6),
                      _EditBanner(
                        message: switch (_mode) {
                          ControlMode.buttons =>
                            'Layout unlocked — drag a column or use the arrows, then lock',
                          ControlMode.dualSticks =>
                            'Layout unlocked — swap throttle and steering, then lock',
                          ControlMode.joystick =>
                            'Layout unlocked — swap sides, then lock',
                        },
                        onSwap: _mode == ControlMode.buttons ? null : _swapSides,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Expanded(child: _buildBody(c)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(RcController c) {
    switch (_mode) {
      case ControlMode.buttons:
        return _buildButtons(c);
      case ControlMode.joystick:
        return _splitControlsAndSettings(
          controls: VirtualJoystick(
            previewNormalized: widget.previewJoystick,
            onChanged: _applyStick,
          ),
          controlsLabel: 'Joystick',
          settings: _CenterPanel(controller: c),
        );
      case ControlMode.dualSticks:
        return _buildDual(c);
    }
  }

  Widget _buildButtons(RcController c) {
    Widget pane(ButtonColumn col, int index) {
      final Widget body = switch (col) {
        ButtonColumn.settings => _CenterPanel(controller: c),
        ButtonColumn.forwardBack => _ForwardBackColumn(controller: c),
        ButtonColumn.leftRight => _LeftRightColumn(controller: c),
      };
      if (!_editing) return body;
      return _EditFrame(
        editing: true,
        label: col.label,
        trailing: _ColumnReorderControls(
          index: index,
          count: _buttonOrder.length,
          onMoveLeft: () => _moveButtonColumn(index, -1),
          onMoveRight: () => _moveButtonColumn(index, 1),
          dragHandle: ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Icon(Icons.drag_indicator, color: Color(0xFF04221E), size: 20),
            ),
          ),
        ),
        child: body,
      );
    }

    if (!_editing) {
      return Row(
        children: <Widget>[
          for (int i = 0; i < _buttonOrder.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 12),
            Expanded(flex: _buttonOrder[i].flex, child: pane(_buttonOrder[i], i)),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 12;
        final double usable = constraints.maxWidth - gap * (_buttonOrder.length - 1);
        return ReorderableListView(
          scrollDirection: Axis.horizontal,
          buildDefaultDragHandles: false,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          onReorderItem: (int oldIndex, int newIndex) {
            _onReorderButtons(oldIndex, newIndex);
          },
          proxyDecorator: (Widget child, int index, Animation<double> animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (BuildContext context, Widget? child) {
                final double t = Curves.easeInOut.transform(animation.value);
                return Transform.scale(scale: 1 + 0.02 * t, child: child);
              },
              child: child,
            );
          },
          children: <Widget>[
            for (int i = 0; i < _buttonOrder.length; i++)
              SizedBox(
                key: ValueKey<ButtonColumn>(_buttonOrder[i]),
                width: usable * (_buttonOrder[i].flex / 10) + (i < _buttonOrder.length - 1 ? gap : 0),
                child: Padding(
                  padding: EdgeInsets.only(right: i < _buttonOrder.length - 1 ? gap : 0),
                  child: pane(_buttonOrder[i], i),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _splitControlsAndSettings({
    required Widget controls,
    required String controlsLabel,
    required Widget settings,
  }) {
    final Widget controlPane = _EditFrame(
      editing: _editing,
      label: controlsLabel,
      child: controls,
    );
    final Widget settingsPane = _EditFrame(
      editing: _editing,
      label: 'Settings',
      child: settings,
    );
    final Widget gap = _editing
        ? _SwapSidesButton(onPressed: _swapSides)
        : const SizedBox(width: 12);
    if (_controlsOnRight) {
      return Row(
        children: <Widget>[
          Expanded(flex: 3, child: settingsPane),
          gap,
          Expanded(flex: 5, child: controlPane),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(flex: 5, child: controlPane),
        gap,
        Expanded(flex: 3, child: settingsPane),
      ],
    );
  }

  Widget _buildDual(RcController c) {
    final Widget throttle = _EditFrame(
      editing: _editing,
      label: 'Throttle',
      child: VirtualJoystick(
        axis: JoystickAxis.vertical,
        label: 'THROTTLE',
        previewNormalized: widget.previewThrottle,
        onChanged: (StickDirection d) {
          widget.controller.setMotion(
            forward: d.forward,
            back: d.back,
            left: c.left,
            right: c.right,
          );
        },
      ),
    );
    final Widget steering = _EditFrame(
      editing: _editing,
      label: 'Steering',
      child: VirtualJoystick(
        axis: JoystickAxis.horizontal,
        label: 'STEERING',
        previewNormalized: widget.previewSteering,
        onChanged: (StickDirection d) {
          widget.controller.setMotion(
            forward: c.forward,
            back: c.back,
            left: d.left,
            right: d.right,
          );
        },
      ),
    );
    return Row(
      children: <Widget>[
        Expanded(flex: 3, child: _throttleOnLeft ? throttle : steering),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: _CenterPanel(controller: c)),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: _throttleOnLeft ? steering : throttle),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.name,
    required this.status,
    required this.connected,
    required this.editing,
    required this.onBack,
    required this.onToggleEdit,
    required this.onControls,
    required this.onDebug,
  });

  final String name;
  final String status;
  final bool connected;
  final bool editing;
  final VoidCallback onBack;
  final VoidCallback onToggleEdit;
  final VoidCallback onControls;
  final VoidCallback onDebug;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.text),
        ),
        const Text(
          'ROCK MASTER RC',
          style: TextStyle(
            color: AppColors.teal,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (connected ? AppColors.teal : AppColors.rose).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            status,
            style: TextStyle(
              color: connected ? AppColors.teal : AppColors.rose,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Spacer(),
        TextButton.icon(
          key: const Key('edit-layout-button'),
          onPressed: onToggleEdit,
          icon: Icon(editing ? Icons.lock_open_rounded : Icons.lock_outline_rounded, size: 18),
          label: Text(editing ? 'Lock layout' : 'Edit layout'),
          style: TextButton.styleFrom(
            foregroundColor: editing ? AppColors.amber : AppColors.muted,
          ),
        ),
        TextButton.icon(
          key: const Key('controls-button'),
          onPressed: onControls,
          icon: const Icon(Icons.sports_esports, size: 18),
          label: const Text('Controls'),
          style: TextButton.styleFrom(foregroundColor: AppColors.teal),
        ),
        TextButton.icon(
          key: const Key('debug-button'),
          onPressed: onDebug,
          icon: const Icon(Icons.bug_report_outlined, size: 18),
          label: const Text('Debug'),
          style: TextButton.styleFrom(foregroundColor: AppColors.amber),
        ),
      ],
    );
  }
}

class _EditBanner extends StatelessWidget {
  const _EditBanner({required this.message, this.onSwap});

  final String message;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.lock_open_rounded, color: AppColors.amber, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.amber,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onSwap != null)
            TextButton.icon(
              key: const Key('swap-sides-button'),
              onPressed: onSwap,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Swap sides'),
              style: TextButton.styleFrom(foregroundColor: AppColors.amber),
            ),
        ],
      ),
    );
  }
}

class _SwapSidesButton extends StatelessWidget {
  const _SwapSidesButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Material(
            color: AppColors.amber,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.swap_horiz_rounded, color: Color(0xFF04221E), size: 26),
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Swap\nsides',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.amber,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditFrame extends StatelessWidget {
  const _EditFrame({
    required this.editing,
    required this.label,
    required this.child,
    this.trailing,
  });

  final bool editing;
  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (!editing) return child;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: _DashedRRectPainter(
              color: AppColors.amber.withValues(alpha: 0.85),
              radius: 20,
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, trailing == null ? 26 : 38, 8, 8),
            child: child,
          ),
        ),
        Positioned(
          top: 4,
          left: 8,
          right: 4,
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF04221E),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
        ),
      ],
    );
  }
}

class _ColumnReorderControls extends StatelessWidget {
  const _ColumnReorderControls({
    required this.index,
    required this.count,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.dragHandle,
  });

  final int index;
  final int count;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final Widget dragHandle;

  @override
  Widget build(BuildContext context) {
    final bool canLeft = index > 0;
    final bool canRight = index < count - 1;
    return Material(
      color: AppColors.amber,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          dragHandle,
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              key: Key('column-left-$index'),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: 'Move left',
              onPressed: canLeft ? onMoveLeft : null,
              icon: Icon(
                Icons.chevron_left_rounded,
                size: 20,
                color: canLeft ? const Color(0xFF04221E) : const Color(0xFF04221E).withValues(alpha: 0.3),
              ),
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              key: Key('column-right-$index'),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: 'Move right',
              onPressed: canRight ? onMoveRight : null,
              icon: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: canRight ? const Color(0xFF04221E) : const Color(0xFF04221E).withValues(alpha: 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3),
      Radius.circular(radius),
    );
    final Path path = Path()..addRRect(rrect);
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    const double dash = 7;
    const double gap = 5;
    for (final PathMetric metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final double end = (dist + dash).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

class _ForwardBackColumn extends StatelessWidget {
  const _ForwardBackColumn({required this.controller});

  final RcController controller;

  @override
  Widget build(BuildContext context) {
    final RcController c = controller;
    return Column(
      children: <Widget>[
        Expanded(
          child: HoldButton(
            label: 'FORWARD',
            icon: Icons.keyboard_arrow_up_rounded,
            color: AppColors.teal,
            held: c.forward,
            onChanged: c.setForward,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: HoldButton(
            label: 'BACK',
            icon: Icons.keyboard_arrow_down_rounded,
            color: AppColors.rose,
            held: c.back,
            onChanged: c.setBack,
          ),
        ),
      ],
    );
  }
}

class _LeftRightColumn extends StatelessWidget {
  const _LeftRightColumn({required this.controller});

  final RcController controller;

  @override
  Widget build(BuildContext context) {
    final RcController c = controller;
    return Column(
      children: <Widget>[
        Expanded(
          child: HoldButton(
            label: 'LEFT',
            icon: Icons.keyboard_arrow_left_rounded,
            color: AppColors.blue,
            held: c.left,
            onChanged: c.setLeft,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: HoldButton(
            label: 'RIGHT',
            icon: Icons.keyboard_arrow_right_rounded,
            color: AppColors.amber,
            held: c.right,
            onChanged: c.setRight,
          ),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ControlMode mode;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (mode) {
        ControlMode.buttons => Icons.grid_view_rounded,
        ControlMode.joystick => Icons.control_camera,
        ControlMode.dualSticks => Icons.tune_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.teal.withValues(alpha: 0.14) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.teal : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? AppColors.teal : AppColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _icon,
                color: selected ? const Color(0xFF04221E) : AppColors.teal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    mode.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: selected ? AppColors.teal : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mode.subtitle,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppColors.teal, size: 22)
            else
              const Icon(Icons.circle_outlined, color: AppColors.border, size: 22),
          ],
        ),
      ),
    );
  }
}

class _CenterPanel extends StatelessWidget {
  const _CenterPanel({required this.controller});

  final RcController controller;

  @override
  Widget build(BuildContext context) {
    final RcController c = controller;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                'SPEED',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                '${c.speed}',
                style: const TextStyle(
                  color: AppColors.teal,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          Slider(
            min: RcProtocol.minSpeed.toDouble(),
            max: RcProtocol.maxSpeed.toDouble(),
            divisions: RcProtocol.maxSpeed - RcProtocol.minSpeed,
            value: c.speed.toDouble(),
            label: '${c.speed}',
            onChanged: (double v) => c.setSpeed(v.round()),
          ),
          _LightToggle(on: c.light, onChanged: c.setLight),
          const SizedBox(height: 8),
          CarTypeSelector(flag: c.flag, onChanged: c.setFlag),
          const Spacer(),
          Text(
            c.lastHex.isEmpty ? 'Waiting to send…' : c.lastHex,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontFamily: 'monospace',
              fontSize: 11,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _LightToggle extends StatelessWidget {
  const _LightToggle({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!on),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: on ? AppColors.amber.withValues(alpha: 0.2) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? AppColors.amber : AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              on ? Icons.lightbulb : Icons.lightbulb_outline,
              color: on ? AppColors.amber : AppColors.muted,
              size: 20,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                on ? 'LIGHTS ON' : 'LIGHTS',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: on ? AppColors.amber : AppColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

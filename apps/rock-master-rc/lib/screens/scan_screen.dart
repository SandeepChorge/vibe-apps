import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../ble/rc_controller.dart';
import '../theme.dart';
import 'control_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.controller,
    this.autostart = true,
    this.lockOrientation = true,
  });

  final RcController controller;
  final bool autostart;
  final bool lockOrientation;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.lockOrientation) {
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    if (widget.autostart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.startScan();
      });
    }
  }

  Future<void> _onTap(ScanEntry entry) async {
    final bool ok = await widget.controller.connect(entry);
    if (!mounted) return;
    if (ok) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ControlScreen(controller: widget.controller),
        ),
      );
      // Coming back from the control screen — resume scanning.
      if (mounted && !widget.controller.connected) {
        widget.controller.startScan();
      }
    } else if (widget.controller.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(widget.controller.errorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final RcController c = widget.controller;
    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, _) {
        final List<ScanEntry> devices = c.devices;
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'ROCK MASTER RC',
                    style: TextStyle(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.4,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Find your car',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    c.bluetoothOn
                        ? 'Named BLE devices nearby. YC_CAR_DEMO is highlighted when seen.'
                        : 'Bluetooth is off. Turn it on to scan.',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: c.scanning ? c.stopScan : c.startScan,
                          icon: Icon(
                            c.scanning ? Icons.stop : Icons.bluetooth_searching,
                          ),
                          label: Text(c.scanning ? 'Stop scan' : 'Scan again'),
                          style: FilledButton.styleFrom(
                            backgroundColor: c.scanning
                                ? AppColors.surfaceAlt
                                : AppColors.teal,
                            foregroundColor: c.scanning
                                ? AppColors.text
                                : const Color(0xFF04221E),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _StatusPill(
                        scanning: c.scanning,
                        bluetoothOn: c.bluetoothOn,
                        count: devices.length,
                      ),
                    ],
                  ),
                  if (c.showBluetoothOffBanner) ...<Widget>[
                    const SizedBox(height: 12),
                    const _HintBanner(
                      key: Key('bluetooth-off-banner'),
                      icon: Icons.bluetooth_disabled,
                      color: AppColors.rose,
                      message: 'Bluetooth is off. Turn it on to find the car.',
                    ),
                  ],
                  if (c.showLocationBanner) ...<Widget>[
                    const SizedBox(height: 12),
                    _HintBanner(
                      key: const Key('location-services-banner'),
                      icon: Icons.location_off_outlined,
                      color: AppColors.amber,
                      message: 'Turn on Location: Android 11 and older needs Location on to find Bluetooth devices',
                      actionLabel: 'Open settings',
                      onAction: c.openLocationSettings,
                    ),
                  ],
                  if (c.errorMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      c.errorMessage!,
                      style: const TextStyle(
                        color: AppColors.rose,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Expanded(
                    child: devices.isEmpty
                        ? Center(
                            child: Text(
                              c.scanning
                                  ? 'Listening for cars…'
                                  : 'No named devices yet.',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                          )
                        : ListView.separated(
                            itemCount: devices.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (BuildContext context, int i) {
                              final ScanEntry e = devices[i];
                              return _DeviceTile(
                                entry: e,
                                busy: c.connecting,
                                onTap: () => _onTap(e),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HintBanner extends StatelessWidget {
  const _HintBanner({
    super.key,
    required this.icon,
    required this.color,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              key: const Key('open-location-settings'),
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: color),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, this.filled = false});

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? const Color(0xFF04221E) : color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.scanning,
    required this.bluetoothOn,
    required this.count,
  });

  final bool scanning;
  final bool bluetoothOn;
  final int count;

  @override
  Widget build(BuildContext context) {
    final String label = !bluetoothOn
        ? 'BT off'
        : scanning
        ? 'Scanning'
        : '$count found';
    final Color color = !bluetoothOn
        ? AppColors.rose
        : scanning
        ? AppColors.amber
        : AppColors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          if (scanning)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.amber,
              ),
            )
          else
            Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.entry,
    required this.busy,
    required this.onTap,
  });

  final ScanEntry entry;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool suggested = entry.isSuggested;
    return Material(
      color: suggested
          ? AppColors.teal.withValues(alpha: 0.10)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: suggested ? AppColors.teal : AppColors.border,
              width: suggested ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (suggested ? AppColors.teal : AppColors.blue)
                      .withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  suggested ? Icons.star : Icons.directions_car_filled,
                  color: suggested ? AppColors.teal : AppColors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        Text(
                          entry.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppColors.text,
                          ),
                        ),
                        if (suggested)
                          const _Tag(
                            label: 'SUGGESTED',
                            color: AppColors.teal,
                            filled: true,
                          ),
                        if (entry.systemConnected)
                          const _Tag(label: 'Connected', color: AppColors.teal),
                        if (entry.paired)
                          const _Tag(label: 'Paired', color: AppColors.amber),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.rssi == null
                          ? entry.device.remoteId.str
                          : '${entry.device.remoteId.str}  ·  ${entry.rssi} dBm',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

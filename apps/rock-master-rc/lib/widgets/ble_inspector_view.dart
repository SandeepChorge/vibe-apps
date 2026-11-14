import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../ble/inspector.dart';
import '../ble/protocol.dart';
import '../ble/rc_controller.dart';
import '../theme.dart';

class BleInspectorView extends StatelessWidget {
  const BleInspectorView({super.key, required this.controller});

  final RcController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller.inspector,
      builder: (BuildContext context, _) {
        final BleInspector inspector = controller.inspector;
        return Container(
          key: const Key('ble-inspector'),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Icon(
                    Icons.bluetooth_searching,
                    color: AppColors.teal,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'BLE INSPECTOR',
                    style: TextStyle(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Every service and characteristic on the car. Drive frames stay on the 100 ms loop.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              _BatteryCallout(inspector: inspector),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('ble-read-all-button'),
                onPressed: (!controller.connected || inspector.reading)
                    ? null
                    : controller.readAllReadable,
                icon: Icon(
                  inspector.reading
                      ? Icons.hourglass_top
                      : Icons.download_outlined,
                  size: 18,
                ),
                label: Text(
                  inspector.reading ? 'Reading…' : 'Read all readable',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: const Color(0xFF04221E),
                  disabledBackgroundColor: AppColors.surfaceAlt,
                  disabledForegroundColor: AppColors.muted,
                ),
              ),
              if (inspector.statusMessage != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  inspector.statusMessage!,
                  key: const Key('ble-read-status'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
              const SizedBox(height: 12),
              if (inspector.services.isEmpty)
                Text(
                  controller.connected ? 'No services discovered yet.' : 'Connect to a car to inspect BLE services and notifications.',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                )
              else
                for (final BleServiceView service
                    in inspector.services) ...<Widget>[
                  _ServiceBlock(service: service, inspector: inspector),
                  const SizedBox(height: 8),
                ],
              const Divider(color: AppColors.border, height: 20),
              _PacketLog(controller: controller, inspector: inspector),
            ],
          ),
        );
      },
    );
  }
}

class _BatteryCallout extends StatelessWidget {
  const _BatteryCallout({required this.inspector});

  final BleInspector inspector;

  @override
  Widget build(BuildContext context) {
    final bool found =
        inspector.batteryServicePresent || inspector.batteryLevelPresent;
    final BleCharView? level = inspector.batteryLevel;
    final String headline;
    final String detail;
    if (inspector.batteryPercent != null) {
      headline = '${inspector.batteryPercent}%';
      final List<int>? value = level?.value;
      final String hex = value == null
          ? ''
          : ' · hex ${value.isEmpty ? '(empty)' : RcProtocol.toHex(value)}';
      detail = 'Battery Level 2A19$hex';
    } else if (level != null && level.readError != null) {
      headline = '—';
      detail = 'Battery Level 2A19 read failed: ${level.readError}';
    } else if (level != null && inspector.batteryDetail != null) {
      headline = '—';
      detail = 'Battery Level 2A19 · ${inspector.batteryDetail}';
    } else if (level != null) {
      headline = '…';
      detail = level.properties.read
          ? 'Battery Level 2A19 found. Reading the percent.'
          : 'Battery Level 2A19 found. Waiting for a notification.';
    } else if (inspector.batteryServicePresent) {
      headline = '—';
      detail =
          'Battery Service 180F is present. Battery Level 2A19 was not found.';
    } else if (inspector.services.isEmpty) {
      headline = '—';
      detail = 'Battery Service 180F / Battery Level 2A19 shows here when the car exposes it.';
    } else {
      headline = 'Not found';
      detail =
          'No standard Battery Service (180F) or Battery Level (2A19). '
          'Any other battery byte will show up in the reads or the notification log.';
    }
    return Container(
      key: const Key('ble-battery-callout'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: found ? AppColors.teal.withValues(alpha: 0.10) : AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: found ? AppColors.teal : AppColors.border,
          width: found ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'BATTERY',
            style: TextStyle(
              color: AppColors.teal,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            headline,
            key: const Key('ble-battery-value'),
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceBlock extends StatelessWidget {
  const _ServiceBlock({required this.service, required this.inspector});

  final BleServiceView service;
  final BleInspector inspector;

  @override
  Widget build(BuildContext context) {
    final bool highlight = service.isBatteryService;
    final String? name = bleFriendlyName(service.uuid);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.teal.withValues(alpha: 0.08)
            : AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? AppColors.teal : AppColors.border,
          width: highlight ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                bleShortUuid(service.uuid)?.toUpperCase() ?? 'SERVICE',
                style: const TextStyle(
                  color: AppColors.teal,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              if (name != null) ...<Widget>[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              Text(
                service.primary ? 'primary' : 'included',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              if (highlight) ...<Widget>[
                const SizedBox(width: 8),
                const Text(
                  'BATTERY',
                  style: TextStyle(
                    color: AppColors.teal,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          SelectableText(
            service.uuid,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          for (final BleCharView characteristic in service.characteristics)
            _CharBlock(
              characteristic: characteristic,
              subscribeError: inspector.subscribeErrors[characteristic.key],
            ),
        ],
      ),
    );
  }
}

class _CharBlock extends StatelessWidget {
  const _CharBlock({
    required this.characteristic,
    required this.subscribeError,
  });

  final BleCharView characteristic;
  final String? subscribeError;

  @override
  Widget build(BuildContext context) {
    final bool highlight = characteristic.isBatteryLevel;
    final String? name = bleFriendlyName(characteristic.uuid);
    final List<int>? value = characteristic.value;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.teal.withValues(alpha: 0.12)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight ? AppColors.teal : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                bleShortUuid(characteristic.uuid)?.toUpperCase() ?? 'CHAR',
                style: const TextStyle(
                  color: AppColors.amber,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              if (name != null) ...<Widget>[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              if (characteristic.instanceId != 0)
                Text(
                  '#${characteristic.instanceId}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              if (highlight) ...<Widget>[
                const SizedBox(width: 8),
                const Text(
                  'BATTERY',
                  style: TextStyle(
                    color: AppColors.teal,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ],
          ),
          SelectableText(
            characteristic.uuid,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            characteristic.properties.label,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (value != null) ...<Widget>[
            const SizedBox(height: 4),
            SelectableText(
              'hex  ${value.isEmpty ? '(empty)' : RcProtocol.toHex(value)}',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            SelectableText(
              'ascii  ${bleAscii(value).isEmpty ? '(empty)' : bleAscii(value)}',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            if (highlight && characteristic.readError == null)
              Text(
                BatterySample.interpret(value).detail,
                style: const TextStyle(
                  color: AppColors.teal,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
          if (characteristic.readError != null)
            Text(
              'read failed: ${characteristic.readError}',
              style: const TextStyle(color: AppColors.rose, fontSize: 11),
            ),
          if (subscribeError != null)
            Text(
              'subscribe failed: $subscribeError',
              style: const TextStyle(color: AppColors.rose, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _PacketLog extends StatelessWidget {
  const _PacketLog({required this.controller, required this.inspector});

  final RcController controller;
  final BleInspector inspector;

  @override
  Widget build(BuildContext context) {
    final int total = inspector.totalPackets;
    final String showing = total > inspector.packets.length
        ? '$total packets, showing the latest ${inspector.packets.length}'
        : '$total packets';
    return Column(
      key: const Key('ble-packet-log'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'NOTIFICATIONS',
          style: TextStyle(
            color: AppColors.amber,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Newest first. ${inspector.subscribedKeys.isEmpty ? 'Not subscribed yet.' : 'Listening on ${inspector.subscribedKeys.length} notify/indicate characteristic${inspector.subscribedKeys.length == 1 ? '' : 's'}.'} $showing.',
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          inspector.countsLine(),
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            TextButton.icon(
              key: const Key('ble-copy-button'),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: inspector.copyText(deviceName: controller.deviceName),
                  ),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('Copied BLE inspector')),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
              style: TextButton.styleFrom(foregroundColor: AppColors.amber),
            ),
            TextButton.icon(
              key: const Key('ble-clear-button'),
              onPressed: inspector.clearPackets,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Clear'),
              style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            ),
          ],
        ),
        for (final BlePacket packet in inspector.packets)
          _PacketTile(packet: packet),
      ],
    );
  }
}

class _PacketTile extends StatelessWidget {
  const _PacketTile({required this.packet});

  final BlePacket packet;

  @override
  Widget build(BuildContext context) {
    final String hex = packet.hex.isEmpty ? '(empty)' : packet.hex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${formatBleTime(packet.at)}   ${bleUuidLabel(packet.characteristicUuid)}   ${packet.length} bytes',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          SelectableText(
            hex,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontFamily: 'monospace',
              letterSpacing: 0.4,
            ),
          ),
          if (packet.changedBytes != null)
            Text(
              packet.changedBytes!,
              style: const TextStyle(
                color: AppColors.amber,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          Text(
            packet.characteristicUuid,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

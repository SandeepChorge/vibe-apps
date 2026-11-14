import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/rc_controller.dart';
import '../theme.dart';
import 'ble_inspector_view.dart';

class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key, required this.controller});

  final RcController controller;

  String _uuid(Guid? g) => g == null ? '—' : g.str128;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
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
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.bug_report_outlined,
                        color: AppColors.amber,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'DEBUG',
                        style: TextStyle(
                          color: AppColors.amber,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      if (controller.usedFallbackDiscovery)
                        const Text(
                          'fallback discovery',
                          style: TextStyle(
                            color: AppColors.amber,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _row('Service', _uuid(controller.serviceUuid)),
                  _row('Write char', _uuid(controller.writeUuid)),
                  _row('Notify char', _uuid(controller.notifyUuid)),
                  _row(
                    'Last frame',
                    controller.lastHex.isEmpty ? '—' : controller.lastHex,
                    mono: true,
                    copyable: controller.lastHex.isNotEmpty,
                  ),
                  if (controller.discoveryNotes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        controller.discoveryNotes,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  // Own Material so the switch ink is not painted under the card.
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Write with response',
                        style: TextStyle(fontSize: 13, color: AppColors.text),
                      ),
                      subtitle: Text(
                        controller.lastWriteWithoutResponse
                            ? 'Currently sending write-without-response'
                            : 'Currently sending write-with-response',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                      value: controller.preferWriteWithResponse,
                      activeThumbColor: AppColors.teal,
                      onChanged: controller.setPreferWriteWithResponse,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            BleInspectorView(controller: controller),
          ],
        );
      },
    );
  }

  Widget _row(
    String label,
    String value, {
    bool mono = false,
    bool copyable = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontFamily: mono ? 'monospace' : null,
                letterSpacing: mono ? 0.4 : 0,
              ),
            ),
          ),
          if (copyable)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(Icons.copy, size: 14, color: AppColors.muted),
              onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            ),
        ],
      ),
    );
  }
}

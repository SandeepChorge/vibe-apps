import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android SDK and location-settings helpers. iOS and tests get a no-op.
class AndroidSystem {
  static const MethodChannel channel = MethodChannel(
    'com.rockmaster.rock_master_rc/system',
  );

  static Future<int?> sdkInt() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return await channel.invokeMethod<int>('sdkInt');
    } catch (_) {
      return null;
    }
  }

  /// Opens the system Location switch screen. Returns false when the intent
  /// could not be started so the caller can fall back to app settings.
  static Future<bool> openLocationSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? opened = await channel.invokeMethod<bool>(
        'openLocationSettings',
      );
      return opened ?? false;
    } catch (_) {
      return false;
    }
  }
}

Future<void> openLocationSettingsOrAppSettings() async {
  if (await AndroidSystem.openLocationSettings()) return;
  try {
    await openAppSettings();
  } catch (_) {}
}

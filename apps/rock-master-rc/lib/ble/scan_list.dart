import 'package:flutter_blue_plus/flutter_blue_plus.dart';

const String kSuggestedDeviceName = 'YC_CAR_DEMO';

/// One row on the scan screen. [rssi] is null for devices that are paired or
/// connected at the OS level and were not seen in an advertisement.
class ScanEntry {
  ScanEntry({
    required this.device,
    required this.name,
    this.rssi,
    this.paired = false,
    this.systemConnected = false,
  });

  final BluetoothDevice device;
  final String name;
  final int? rssi;
  final bool paired;
  final bool systemConnected;

  bool get isSuggested => name == kSuggestedDeviceName;

  String get remoteId => device.remoteId.str;

  /// Fold [other] into this entry. Flags are combined. A real name wins over
  /// the remote id, and a scan result's rssi wins over "not seen".
  ScanEntry copyMerged(ScanEntry other) {
    return ScanEntry(
      device: other.rssi != null ? other.device : device,
      name: preferDeviceName(name, other.name, remoteId),
      rssi: other.rssi ?? rssi,
      paired: paired || other.paired,
      systemConnected: systemConnected || other.systemConnected,
    );
  }
}

/// Android 11 and older (API 30 and below) return no BLE advertisements while
/// system Location services are off, even when the location permission is granted.
bool showAndroidLocationBanner({
  required int? sdkInt,
  required bool locationServicesEnabled,
}) {
  if (sdkInt == null || sdkInt > 30) return false;
  return !locationServicesEnabled;
}

String preferDeviceName(String current, String incoming, String remoteId) {
  final String kept = current.trim();
  final String next = incoming.trim();
  final bool keptReal = kept.isNotEmpty && kept != remoteId;
  final bool nextReal = next.isNotEmpty && next != remoteId;
  if (nextReal) return next;
  if (keptReal) return kept;
  if (next.isNotEmpty) return next;
  if (kept.isNotEmpty) return kept;
  return remoteId;
}

/// Dedup by remote id. Later lists overlay earlier ones: system-connected,
/// then bonded, then live scan results.
List<ScanEntry> mergeScanEntries({
  required List<ScanEntry> systemConnected,
  required List<ScanEntry> bonded,
  required List<ScanEntry> scanned,
}) {
  final Map<String, ScanEntry> byId = <String, ScanEntry>{};
  void add(ScanEntry entry) {
    final String id = entry.remoteId;
    final ScanEntry? existing = byId[id];
    byId[id] = existing == null ? entry : existing.copyMerged(entry);
  }

  for (final ScanEntry entry in systemConnected) {
    add(entry);
  }
  for (final ScanEntry entry in bonded) {
    add(entry);
  }
  for (final ScanEntry entry in scanned) {
    add(entry);
  }

  final List<ScanEntry> list = byId.values.toList();
  list.sort(_compareEntries);
  return list;
}

int _compareEntries(ScanEntry a, ScanEntry b) {
  if (a.isSuggested != b.isSuggested) return a.isSuggested ? -1 : 1;
  if (a.systemConnected != b.systemConnected) {
    return a.systemConnected ? -1 : 1;
  }
  if (a.paired != b.paired) return a.paired ? -1 : 1;
  return (b.rssi ?? -1000).compareTo(a.rssi ?? -1000);
}

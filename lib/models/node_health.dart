import 'package:flutter/material.dart';

import '../utils/firestore_parse.dart';

/// Board health a node writes to `health/{nodeId}/info` in the Realtime
/// Database every 30 s: power, Wi-Fi, memory and sensor status.
class NodeHealth {
  /// Older than this and the report is shown as out of date.
  static const Duration staleAfter = Duration(minutes: 2);

  final DateTime? time;
  final int? uptimeSeconds;
  final String? restartReason;
  final int? starts;
  final String? firmware;

  /// Only when a battery sensor is fitted.
  final int? batteryPercent;
  final double? batteryVolts;
  final bool? charging;

  final String? wifiName;
  final int? rssi;
  final String? ip;
  final String? network;
  final int? channel;

  /// Devices on the node's own FireDetector Wi-Fi (the camera).
  final int? hotspotClients;

  final int? freeMemory;
  final int? lowestFreeMemory;
  final int? freePsram;
  final double? chipTemperature;

  final int? uploadsSent;
  final int? uploadsFailed;
  final int? cameraFrames;

  /// Seconds since the last camera photo; -1 when none has arrived.
  final int? cameraAgeSeconds;
  final int? aiMilliseconds;
  final String? smokeSensor;
  final bool? dht1Ok;
  final bool? dht2Ok;
  final String? lora;
  final int? loraSent;
  final String? thingSpeak;

  /// "lora" when the node has no internet of its own and a LoRa gateway
  /// uploads for it; then [gateway], [loraRssi] and [loraSnr] describe the link.
  final String? link;
  final String? gateway;
  final int? loraRssi;
  final double? loraSnr;

  bool get viaLora => link == 'lora';

  const NodeHealth({
    this.time,
    this.uptimeSeconds,
    this.restartReason,
    this.starts,
    this.firmware,
    this.batteryPercent,
    this.batteryVolts,
    this.charging,
    this.wifiName,
    this.rssi,
    this.ip,
    this.network,
    this.channel,
    this.hotspotClients,
    this.freeMemory,
    this.lowestFreeMemory,
    this.freePsram,
    this.chipTemperature,
    this.uploadsSent,
    this.uploadsFailed,
    this.cameraFrames,
    this.cameraAgeSeconds,
    this.aiMilliseconds,
    this.smokeSensor,
    this.dht1Ok,
    this.dht2Ok,
    this.lora,
    this.loraSent,
    this.thingSpeak,
    this.link,
    this.gateway,
    this.loraRssi,
    this.loraSnr,
  });

  factory NodeHealth.fromMap(Map<Object?, Object?> map) {
    int? asInt(Object? value) => parseDoubleOrNull(value)?.round();
    bool? asBool(Object? value) => value is bool ? value : null;
    final ts = map['ts'];

    return NodeHealth(
      time: ts is num ? DateTime.fromMillisecondsSinceEpoch(ts.toInt()) : null,
      uptimeSeconds: asInt(map['up']),
      restartReason: parseStringOrNull(map['boot']),
      starts: asInt(map['boots']),
      firmware: parseStringOrNull(map['fw']),
      batteryPercent: asInt(map['bat']),
      batteryVolts: parseDoubleOrNull(map['batV']),
      charging: asBool(map['chg']),
      wifiName: parseStringOrNull(map['ssid']),
      rssi: asInt(map['rssi']),
      ip: parseStringOrNull(map['ip']),
      network: parseStringOrNull(map['net']),
      channel: asInt(map['ch']),
      hotspotClients: asInt(map['apc']),
      freeMemory: asInt(map['heap']),
      lowestFreeMemory: asInt(map['minHeap']),
      freePsram: asInt(map['psram']),
      chipTemperature: parseDoubleOrNull(map['chipT']),
      uploadsSent: asInt(map['sent']),
      uploadsFailed: asInt(map['failed']),
      cameraFrames: asInt(map['frames']),
      cameraAgeSeconds: asInt(map['camAge']),
      aiMilliseconds: asInt(map['aiMs']),
      smokeSensor: parseStringOrNull(map['mq']),
      dht1Ok: asBool(map['dht1']),
      dht2Ok: asBool(map['dht2']),
      lora: parseStringOrNull(map['lora']),
      loraSent: asInt(map['loraTx']),
      thingSpeak: parseStringOrNull(map['tsp']),
      link: parseStringOrNull(map['link']),
      gateway: parseStringOrNull(map['gw']),
      loraRssi: asInt(map['lrssi']),
      loraSnr: parseDoubleOrNull(map['lsnr']),
    );
  }

  bool isStaleAt(DateTime now) {
    final t = time;
    return t == null || now.difference(t) > staleAfter;
  }

  bool get hasBattery => batteryPercent != null || batteryVolts != null;

  /// Why the board last started, in plain words.
  String get restartText {
    switch (restartReason) {
      case 'power-on':
        return 'Switched on or power came back';
      case 'brownout':
        return 'Power dipped too low';
      case 'software':
        return 'Restarted itself to recover the connection';
      case 'crash':
        return 'Recovered from a software crash';
      case 'watchdog':
        return 'Restarted after it stopped responding';
      case 'reset-button':
        return 'Reset button pressed';
      case 'usb':
        return 'Restarted over USB (new firmware)';
      case 'deep-sleep':
        return 'Woke from sleep';
      default:
        return 'Unknown';
    }
  }

  /// Advice when the restart points at a problem, else null.
  String? get restartAdvice {
    switch (restartReason) {
      case 'brownout':
        return 'The power supply is too weak. Use a 5 V 2 A adapter and a short, good USB cable.';
      case 'crash':
      case 'watchdog':
        return 'The board recovered by itself. If this keeps happening, check the power supply.';
      default:
        return null;
    }
  }

  /// 0-4 bars and a word for the Wi-Fi signal.
  static (int, String) signal(int rssi) {
    if (rssi >= -55) return (4, 'Excellent');
    if (rssi >= -67) return (3, 'Good');
    if (rssi >= -75) return (2, 'Fair');
    if (rssi >= -85) return (1, 'Weak');
    return (0, 'Very weak');
  }

  /// 0-4 bars and a word for a LoRa signal (SF10 hears down to about -132 dBm).
  static (int, String) loraSignal(int rssi) {
    if (rssi >= -100) return (4, 'Excellent');
    if (rssi >= -110) return (3, 'Good');
    if (rssi >= -120) return (2, 'Fair');
    if (rssi >= -128) return (1, 'Weak');
    return (0, 'Very weak');
  }

  static Color signalColor(int bars) => bars >= 3
      ? Colors.green
      : bars == 2
      ? Colors.orange
      : Colors.red;

  /// Share of cloud uploads that got through, 0-100.
  int? get uploadSuccessPercent {
    final sent = uploadsSent, failed = uploadsFailed;
    if (sent == null || failed == null || sent + failed == 0) return null;
    return (sent * 100 / (sent + failed)).round();
  }

  /// Network name as the app shows it.
  String get networkLabel {
    switch (network) {
      case 'hotspot':
        return 'Laptop hotspot';
      case 'pg':
        return 'Backup Wi-Fi';
      case 'custom':
        return 'Saved network';
      default:
        return 'Wi-Fi';
    }
  }
}

/// "45 s", "12 min", "3 h 5 min", "2 days 4 h".
String uptimeLabel(int seconds) {
  if (seconds < 60) return '$seconds s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  if (hours < 24) {
    final m = minutes % 60;
    return '$hours h${m == 0 ? '' : ' $m min'}';
  }
  final days = hours ~/ 24;
  final h = hours % 24;
  return '$days day${days == 1 ? '' : 's'}${h == 0 ? '' : ' $h h'}';
}

/// "182 KB", "7.9 MB".
String memoryLabel(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).round()} KB';
}

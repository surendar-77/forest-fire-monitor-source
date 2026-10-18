import 'package:cloud_firestore/cloud_firestore.dart';

/// Lenient readers for Firestore fields. Device data is written by firmware
/// and Python scripts, so numbers may arrive as strings and fields may be
/// missing; these never throw.

double parseDouble(dynamic value, double fallback) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

double? parseDoubleOrNull(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '');
}

int parseInt(dynamic value, int fallback) {
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool parseBool(dynamic value, bool fallback) {
  if (value is bool) {
    return value;
  }

  return fallback;
}

String parseString(dynamic value, String fallback) {
  if (value == null) {
    return fallback;
  }

  final result = value.toString();

  return result.isEmpty ? fallback : result;
}

String? parseStringOrNull(dynamic value) {
  if (value == null) {
    return null;
  }

  final result = value.toString();

  return result.isEmpty ? null : result;
}

DateTime? parseDateTimeOrNull(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is DateTime) {
    return value;
  }

  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }

  return DateTime.tryParse(value?.toString() ?? '');
}

DateTime parseDateTime(dynamic value) {
  return parseDateTimeOrNull(value) ?? DateTime.now();
}

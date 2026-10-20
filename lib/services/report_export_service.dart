import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/alert_model.dart';
import '../models/reading_model.dart';
import '../utils/alert_report.dart';
import '../utils/alert_timeline.dart';
import '../utils/friendly.dart';

/// Builds incident reports for officers: CSV for spreadsheets and PDF for
/// filing, and the sensor readings behind the graphs as CSV. All are shared
/// through the platform share sheet (a download on the web).
class ReportExportService {
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  static final DateFormat _secondFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  static const List<String> _headers = [
    'Alert ID',
    'Node',
    'Type',
    'Severity',
    'Status',
    'Detected',
    'Confirmed',
    'Acknowledged by',
    'Acknowledged at',
    'Minutes to acknowledge',
    'Responder verdict',
    'Resolved by',
    'Resolved at',
    'Minutes to resolve',
    'Outcome',
    'Camera AI %',
    'Fire %',
    'Smoke %',
    'Temperature °C',
    'Humidity %',
    'Latitude',
    'Longitude',
    'Details',
    'Notes',
  ];

  static String _minutes(Duration? d) =>
      d == null || d.isNegative ? '' : (d.inSeconds / 60).toStringAsFixed(1);

  static List<List<Object?>> _rows(List<AlertModel> alerts) {
    return alerts.map((alert) {
      return [
        alert.id,
        alert.deviceId,
        alert.type,
        alert.severity,
        alert.status,
        _dateFormat.format(alert.detectedAt),
        _formatOptional(alert.confirmedAt),
        alert.acknowledgedBy ?? '',
        _formatOptional(alert.acknowledgedAt),
        _minutes(alert.timeToAcknowledge),
        alert.verdict == null
            ? ''
            : (alert.verdict == AlertVerdict.real ? 'Real fire' : 'False alarm'),
        alert.resolvedBy ?? '',
        _formatOptional(alert.resolvedAt),
        _minutes(alert.timeToResolve),
        alert.outcome == null ? '' : AlertOutcome.label(alert.outcome),
        alert.aiConfidence == null ? '' : (alert.aiConfidence! * 100).toStringAsFixed(0),
        alert.fireProbability.toStringAsFixed(0),
        alert.smokeProbability.toStringAsFixed(0),
        alert.temperature.toStringAsFixed(1),
        alert.humidity.toStringAsFixed(0),
        alert.latitude.toStringAsFixed(6),
        alert.longitude.toStringAsFixed(6),
        alert.message ?? '',
        alert.notes ?? '',
      ];
    }).toList();
  }

  static String _formatOptional(DateTime? time) {
    return time == null ? '' : _dateFormat.format(time);
  }

  static String buildCsv(List<AlertModel> alerts) {
    return Csv().encode([_headers, ..._rows(alerts)]);
  }

  static String _fileStem(String scope) {
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    return 'fire_alerts_${scope}_$stamp';
  }

  static Future<void> _shareText(String text, String fileName, String subject) {
    return SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            // BOM so Excel opens °C and other symbols correctly.
            utf8.encode('﻿$text'),
            mimeType: 'text/csv',
            name: fileName,
          ),
        ],
        fileNameOverrides: [fileName],
        subject: subject,
      ),
    );
  }

  static Future<void> shareCsv(
    List<AlertModel> alerts, {
    String scope = 'all',
  }) {
    return _shareText(
      buildCsv(alerts),
      '${_fileStem(scope)}.csv',
      'Forest fire alert report',
    );
  }

  // ----------------------------------------------------------
  // Sensor readings (the data behind the graphs)
  // ----------------------------------------------------------

  static const List<String> readingHeaders = [
    'Time',
    'Temperature zone 1 °C',
    'Temperature zone 2 °C',
    'Humidity zone 1 %',
    'Humidity zone 2 %',
    'Smoke sensor 1 (MQ-2)',
    'Smoke sensor 2 (MQ-2)',
    'Camera fire %',
    'Camera smoke %',
    'Camera AI class',
    'Camera AI confidence %',
    'Fire risk score',
  ];

  static String _num(double? v, int decimals) =>
      v == null ? '' : v.toStringAsFixed(decimals);

  /// Oldest first, one row per reading (or per hour for hourly data).
  static String buildReadingsCsv(List<ReadingModel> readings) {
    final sorted = [...readings]..sort((a, b) => a.time.compareTo(b.time));
    return Csv().encode([
      readingHeaders,
      for (final r in sorted)
        [
          _secondFormat.format(r.time.toLocal()),
          _num(r.temperature, 1),
          _num(r.temperature2, 1),
          _num(r.humidity, 1),
          _num(r.humidity2, 1),
          _num(r.smoke1 ?? r.smoke, 0),
          _num(r.smoke2, 0),
          _num(r.fireProbability, 1),
          _num(r.smokeProbability, 1),
          r.aiClass ?? '',
          _num(r.aiConfidence == null ? null : r.aiConfidence! * 100, 1),
          _num(r.riskScore, 0),
        ],
    ]);
  }

  static Future<void> shareReadingsCsv(
    List<ReadingModel> readings, {
    required String nodeId,
    required String nodeName,
    required String rangeLabel,
    bool hourly = false,
  }) {
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final kind = hourly ? 'hourly' : 'readings';
    return _shareText(
      buildReadingsCsv(readings),
      '${nodeId}_${kind}_${rangeLabel}_$stamp.csv',
      '$nodeName sensor data ($rangeLabel)',
    );
  }

  // ----------------------------------------------------------
  // PDF report: summary, then every alert
  // ----------------------------------------------------------

  static Future<void> sharePdf(
    List<AlertModel> alerts, {
    String scope = 'all',
    String title = 'Forest Fire Alert Report',
    DateTime? from,
    DateTime? to,
    Map<String, String> sensorNames = const {},
  }) async {
    final document = pw.Document();
    final generated = _dateFormat.format(DateTime.now());
    final end = to ?? DateTime.now();
    final start = from ??
        (alerts.isEmpty
            ? end
            : alerts.map((a) => a.detectedAt).reduce((a, b) => a.isBefore(b) ? a : b));
    final report = AlertReport.of(alerts, from: start, to: end.add(const Duration(seconds: 1)));
    String name(String id) => sensorNames[id] ?? id;

    pw.Widget stat(String label, String value) => pw.Container(
      width: 120,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ],
      ),
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${DateFormat('d MMM yyyy').format(start)} - ${DateFormat('d MMM yyyy').format(end)}'
              '  ·  generated $generated',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 12),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              stat('alerts', '${report.total}'),
              stat('fire / smoke (camera)', '${report.fireAndSmoke}'),
              stat('sensor problems / offline', '${report.sensorProblems}'),
              stat('still open', '${report.open}'),
              stat(
                'typical time to acknowledge',
                report.medianAcknowledge == null ? '-' : elapsedLabel(report.medianAcknowledge!),
              ),
              stat(
                'typical time to resolve',
                report.medianResolve == null ? '-' : elapsedLabel(report.medianResolve!),
              ),
              stat(
                'false alarms (judged camera alerts)',
                report.falseAlarmPercent == null ? '-' : '${report.falseAlarmPercent}%',
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          if (report.byType.isNotEmpty)
            pw.Text(
              'By type: ${report.byType.map((e) => '${alertTitle(e.key)} ${e.value}').join(' · ')}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          if (report.bySensor.isNotEmpty)
            pw.Text(
              'By sensor: ${report.bySensor.map((e) => '${name(e.key)} ${e.value}').join(' · ')}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Detected',
              'Sensor',
              'What',
              'Level',
              'Status',
              'Acknowledged',
              'Resolved',
              'Outcome',
              'Camera %',
              'Notes',
            ],
            data: report.alerts.map((alert) {
              String by(String? who, Duration? d) => who == null
                  ? ''
                  : '$who${d == null || d.isNegative ? '' : ' (+${elapsedLabel(d)})'}';
              return [
                _dateFormat.format(alert.detectedAt),
                name(alert.deviceId),
                alertTitle(alert.type),
                levelLabel(alert.severity),
                alertStatusLabel(alert.status),
                by(alert.acknowledgedBy, alert.timeToAcknowledge),
                by(alert.resolvedBy, alert.timeToResolve),
                alert.outcome != null
                    ? AlertOutcome.label(alert.outcome)
                    : alert.verdict == null
                    ? ''
                    : (alert.verdict == AlertVerdict.real ? 'Real fire' : 'False alarm'),
                alert.aiConfidence == null ? '' : (alert.aiConfidence! * 100).toStringAsFixed(0),
                alert.notes ?? alert.message ?? '',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red700),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await document.save(),
      filename: '${_fileStem(scope)}.pdf',
      subject: title,
    );
  }
}

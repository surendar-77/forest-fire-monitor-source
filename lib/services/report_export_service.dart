import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/alert_model.dart';

/// Builds incident reports for officers: CSV for spreadsheets and PDF for
/// filing, both shared through the platform share sheet (download on web).
class ReportExportService {
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  static const List<String> _headers = [
    'Alert ID',
    'Node',
    'Type',
    'Severity',
    'Status',
    'Detected',
    'Acknowledged by',
    'Acknowledged at',
    'Resolved by',
    'Resolved at',
    'Fire %',
    'Smoke %',
    'Temperature °C',
    'Humidity %',
    'Latitude',
    'Longitude',
    'Notes',
  ];

  static List<List<Object?>> _rows(List<AlertModel> alerts) {
    return alerts.map((alert) {
      return [
        alert.id,
        alert.deviceId,
        alert.type,
        alert.severity,
        alert.status,
        _dateFormat.format(alert.detectedAt),
        alert.acknowledgedBy ?? '',
        _formatOptional(alert.acknowledgedAt),
        alert.resolvedBy ?? '',
        _formatOptional(alert.resolvedAt),
        alert.fireProbability.toStringAsFixed(0),
        alert.smokeProbability.toStringAsFixed(0),
        alert.temperature.toStringAsFixed(1),
        alert.humidity.toStringAsFixed(0),
        alert.latitude.toStringAsFixed(6),
        alert.longitude.toStringAsFixed(6),
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

  static Future<void> shareCsv(List<AlertModel> alerts, {String scope = 'all'}) {
    final fileName = '${_fileStem(scope)}.csv';

    return SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(buildCsv(alerts)),
            mimeType: 'text/csv',
            name: fileName,
          ),
        ],
        fileNameOverrides: [fileName],
        subject: 'Forest fire alert report',
      ),
    );
  }

  static Future<void> sharePdf(
    List<AlertModel> alerts, {
    String scope = 'all',
    String title = 'Forest Fire Alert Report',
  }) async {
    final document = pw.Document();
    final generated = _dateFormat.format(DateTime.now());

    final open = alerts.where((alert) => alert.isOpen).length;
    final critical = alerts.where((a) => a.severity == 'CRITICAL').length;

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
              'Generated $generated  ·  ${alerts.length} alerts  ·  '
              '$open open  ·  $critical critical',
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
          pw.TableHelper.fromTextArray(
            headers: const [
              'Detected',
              'Node',
              'Type',
              'Severity',
              'Status',
              'Ack by',
              'Resolved by',
              'Fire %',
              'Smoke %',
              'Temp °C',
              'Notes',
            ],
            data: alerts.map((alert) {
              return [
                _dateFormat.format(alert.detectedAt),
                alert.deviceId,
                alert.type,
                alert.severity,
                alert.status,
                alert.acknowledgedBy ?? '',
                alert.resolvedBy ?? '',
                alert.fireProbability.toStringAsFixed(0),
                alert.smokeProbability.toStringAsFixed(0),
                alert.temperature.toStringAsFixed(1),
                alert.notes ?? '',
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

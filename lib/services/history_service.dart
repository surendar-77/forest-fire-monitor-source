import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/reading_model.dart';

enum HistoryRange {
  hour(Duration(hours: 1), '1H'),
  day(Duration(hours: 24), '24H'),
  week(Duration(days: 7), '7D');

  const HistoryRange(this.duration, this.label);

  final Duration duration;
  final String label;

  /// Raw readings arrive about once a minute. Loading a day of them would
  /// cost up to 1,440 Firestore reads per view, a big share of the free
  /// plan's 50,000/day, so longer ranges use hourly rollups (24 per day).
  bool get usesHourlyRollup => this != HistoryRange.hour;
}

class HistoryService {
  HistoryService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<List<ReadingModel>> load(String nodeId, HistoryRange range) async {
    final since = Timestamp.fromDate(DateTime.now().subtract(range.duration));
    final node = _firestore.collection('devices').doc(nodeId);

    if (range.usesHourlyRollup) {
      final snapshot = await node
          .collection('hourly')
          .where('hour', isGreaterThanOrEqualTo: since)
          .orderBy('hour')
          .get();

      final hourly = snapshot.docs
          .map((doc) => ReadingModel.fromHourly(doc.data()))
          .toList();

      // The backend writes each hour's rollup when the hour ends; fill in
      // the current hour from raw readings so the chart reaches "now".
      final now = DateTime.now().toUtc();
      final hourStart = DateTime.utc(now.year, now.month, now.day, now.hour);
      final recent = await node
          .collection('readings')
          .where('ts', isGreaterThanOrEqualTo: Timestamp.fromDate(hourStart))
          .orderBy('ts')
          .limit(120)
          .get();

      return [
        ...hourly.where((r) => r.time.isBefore(hourStart)),
        ...recent.docs.map((doc) => ReadingModel.fromReading(doc.data())),
      ];
    }

    final snapshot = await node
        .collection('readings')
        .where('ts', isGreaterThanOrEqualTo: since)
        .orderBy('ts')
        .limit(2000)
        .get();

    return snapshot.docs
        .map((doc) => ReadingModel.fromReading(doc.data()))
        .toList();
  }
}

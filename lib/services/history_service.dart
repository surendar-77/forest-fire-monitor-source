import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/reading_model.dart';

enum HistoryRange {
  hour(Duration(hours: 1), '1H'),
  day(Duration(hours: 24), '24H'),
  week(Duration(days: 7), '7D');

  const HistoryRange(this.duration, this.label);

  final Duration duration;
  final String label;

  /// Raw readings arrive about once a minute; a week of them is too many
  /// documents to load, so the week view uses hourly rollups.
  bool get usesHourlyRollup => this == HistoryRange.week;
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

      return snapshot.docs
          .map((doc) => ReadingModel.fromHourly(doc.data()))
          .toList();
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

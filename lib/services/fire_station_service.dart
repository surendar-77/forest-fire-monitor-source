import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/firestore_parse.dart';

/// A fire station told about serious alerts by Telegram.
class FireStation {
  final String id;
  final String name;
  final String telegramChatId;
  final String? phone;
  final double? latitude;
  final double? longitude;

  const FireStation({
    required this.id,
    required this.name,
    required this.telegramChatId,
    this.phone,
    this.latitude,
    this.longitude,
  });

  bool get hasLocation => latitude != null && longitude != null;

  factory FireStation.fromFirestore(String id, Map<String, dynamic> data) {
    return FireStation(
      id: id,
      name: parseString(data['name'], 'Station'),
      telegramChatId: parseString(data['telegramChatId'], ''),
      phone: parseStringOrNull(data['phone']),
      latitude: parseDoubleOrNull(data['latitude']),
      longitude: parseDoubleOrNull(data['longitude']),
    );
  }
}

/// Someone (a person or a group) who has messaged the bot.
class TelegramChat {
  final String chatId;
  final String name;
  final String? username;
  final String type;
  final DateTime? lastMessageAt;

  const TelegramChat({
    required this.chatId,
    required this.name,
    this.username,
    required this.type,
    this.lastMessageAt,
  });

  factory TelegramChat.fromFirestore(String id, Map<String, dynamic> data) {
    return TelegramChat(
      chatId: parseString(data['chatId'], id),
      name: parseString(data['name'], id),
      username: parseStringOrNull(data['username']),
      type: parseString(data['type'], 'private'),
      lastMessageAt: parseDateTimeOrNull(data['lastMessageAt']),
    );
  }

  String get label => [
    name,
    if (username != null) '@$username',
    if (type != 'private') '(group)',
  ].join(' ');
}

/// The backend's Telegram bot, as reported in its heartbeat.
class BotStatus {
  final bool configured;
  final String? username;

  const BotStatus({required this.configured, this.username});
}

/// Fire stations and the Telegram bot, for administrators.
class FireStationService {
  FireStationService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Stream<List<FireStation>> stations() => _firestore
      .collection('fireStations')
      .snapshots()
      .map(
        (snap) =>
            snap.docs
                .map((d) => FireStation.fromFirestore(d.id, d.data()))
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );

  Stream<List<TelegramChat>> chats() => _firestore
      .collection('telegramChats')
      .snapshots()
      .map(
        (snap) =>
            snap.docs
                .map((d) => TelegramChat.fromFirestore(d.id, d.data()))
                .toList()
              ..sort(
                (a, b) => (b.lastMessageAt ?? DateTime(0)).compareTo(
                  a.lastMessageAt ?? DateTime(0),
                ),
              ),
      );

  Stream<BotStatus> botStatus() =>
      _firestore.collection('status').doc('backend').snapshots().map((snap) {
        final data = snap.data() ?? const {};
        return BotStatus(
          configured: data['telegramConfigured'] == true,
          username: parseStringOrNull(data['telegramBot']),
        );
      });

  Future<void> save({
    String? id,
    required String name,
    required String telegramChatId,
    String? phone,
    double? latitude,
    double? longitude,
  }) {
    final collection = _firestore.collection('fireStations');
    final doc = id == null ? collection.doc() : collection.doc(id);
    return doc.set({
      'name': name.trim(),
      'telegramChatId': telegramChatId.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (latitude != null && longitude != null) ...{
        'latitude': latitude,
        'longitude': longitude,
      },
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _auth.currentUser?.uid,
    });
  }

  Future<void> delete(String id) =>
      _firestore.collection('fireStations').doc(id).delete();

  /// Asks the backend to send a test message; returns its answer.
  Future<String> sendTest(String stationId) async {
    final request = await _firestore.collection('adminRequests').add({
      'kind': 'testStation',
      'requestedBy': _auth.currentUser?.uid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'stationId': stationId,
    });
    final result = await request
        .snapshots()
        .map((snapshot) => snapshot.data())
        .firstWhere((data) => data != null && data['status'] != 'pending')
        .timeout(
          const Duration(minutes: 3),
          onTimeout: () => throw TimeoutException(
            'The backend did not answer. Check that it is running.',
          ),
        );
    if (result!['status'] != 'done') {
      throw Exception(result['message'] ?? 'The test message failed.');
    }
    return result['message'] as String? ?? 'Test message sent.';
  }
}

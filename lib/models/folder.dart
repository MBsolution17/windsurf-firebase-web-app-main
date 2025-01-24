// lib/models/folder.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Folder {
  final String id;
  final String name;
  final String userId;
  final DateTime timestamp;

  Folder({
    required this.id,
    required this.name,
    required this.userId,
    required this.timestamp,
  });

  factory Folder.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Folder(
      id: doc.id,
      name: data['name'] ?? 'Sans nom',
      userId: data['userId'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'userId': userId,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}

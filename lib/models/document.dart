// lib/models/document.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class DocumentModel {
  final String id;
  final String title;
  final String type;
  final String url;
  final String folderId;
  final DateTime timestamp;

  DocumentModel({
    required this.id,
    required this.title,
    required this.type,
    required this.url,
    required this.folderId,
    required this.timestamp,
  });

  factory DocumentModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return DocumentModel(
      id: doc.id,
      title: data['title'] ?? 'Sans titre',
      type: data['type'] ?? 'pdf',
      url: data['url'] ?? '',
      folderId: data['folderId'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'type': type,
      'url': url,
      'folderId': folderId,
      'timestamp': timestamp, // Firestore convertira automatiquement DateTime en Timestamp
    };
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class DocumentModel {
  final String id;
  final String title;
  final String type;
  final String url;
  final String folderId;
  final DateTime timestamp;
  final List<String>? linkMapping; // Mapping des liens
  final String? originalUrl; // URL de la version originale

  DocumentModel({
    required this.id,
    required this.title,
    required this.type,
    required this.url,
    required this.folderId,
    required this.timestamp,
    this.linkMapping,
    this.originalUrl,
  });

  factory DocumentModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    List<String>? linkMapping;
    if (data['linkMapping'] != null) {
      if (data['linkMapping'] is List) {
        linkMapping = (data['linkMapping'] as List).map((e) => e?.toString() ?? '').toList();
      } else if (data['linkMapping'] is Map) {
        linkMapping = (data['linkMapping'] as Map).values.map((e) => e?.toString() ?? '').toList();
      } else {
        linkMapping = [];
      }
    }

    return DocumentModel(
      id: doc.id,
      title: data['title'] ?? 'Sans titre',
      type: data['type']?.toString().toLowerCase() ?? 'pdf',
      url: data['url'] ?? '',
      folderId: data['folderId'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      linkMapping: linkMapping,
      originalUrl: data['originalUrl'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'type': type,
      'url': url,
      'folderId': folderId,
      'timestamp': timestamp,
      'linkMapping': linkMapping ?? [],
      'originalUrl': originalUrl,
    };
  }

  @override
  String toString() {
    return 'DocumentModel(id: $id, title: $title, type: $type, folderId: $folderId, linkMapping: $linkMapping)';
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';

class Folder {
  final String id;
  final String name;
  final DateTime timestamp;
  final Map<String, String>? folderMapping;
  final bool isClosed;

  Folder({
    required this.id,
    required this.name,
    required this.timestamp,
    this.folderMapping,
    this.isClosed = false,
  });

  factory Folder.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Folder(
      id: doc.id,
      name: data['name'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      folderMapping: data['folderMapping'] != null
          ? Map<String, String>.from(data['folderMapping'])
          : null,
      isClosed: data['isClosed'] ?? false,
    );
  }
}

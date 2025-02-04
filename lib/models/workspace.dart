// lib/models/workspace.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Workspace {
  final String id;
  final String name;
  final String ownerUid; // UID du créateur
  final List<String> members; // Liste des UID des membres

  Workspace({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.members,
  });

  // Factory pour créer un Workspace depuis un DocumentSnapshot
  factory Workspace.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Workspace(
      id: doc.id,
      name: data['name'] ?? 'Sans nom',
      ownerUid: data['ownerUid'] ?? '',
      members: List<String>.from(data['members'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ownerUid': ownerUid,
      'members': members,
    };
  }
}

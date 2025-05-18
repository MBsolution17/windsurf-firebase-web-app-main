import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart'; // Assurez-vous que cette dépendance est dans pubspec.yaml

class Workspace {
  final String id;
  final String name;
  final String ownerUid; // UID du créateur
  final List<String> members; // Liste des UID des membres
  final String joinCode; // Code unique pour rejoindre le workspace

  Workspace({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.members,
    required this.joinCode,
  });

  // Factory pour créer un Workspace depuis un DocumentSnapshot
  factory Workspace.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Workspace(
      id: doc.id,
      name: data['name'] ?? 'Sans nom',
      ownerUid: data['ownerUid'] ?? '',
      members: List<String>.from(data['members'] ?? []),
      joinCode: data['joinCode'] ?? generateJoinCode(), // Utilise la méthode publique
    );
  }

  // Convertit un Workspace en Map pour Firestore
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'ownerUid': ownerUid,
      'members': members,
      'joinCode': joinCode,
    };
  }

  // Méthode publique pour générer un code de join
  static String generateJoinCode() {
    const uuid = Uuid();
    return uuid.v4().substring(0, 6).toUpperCase(); // Génère un code court et unique
  }

  // Méthode pour ajouter un membre (utilisée pour rejoindre un workspace)
  Workspace addMember(String memberUid) {
    final updatedMembers = [...members, memberUid];
    return Workspace(
      id: id,
      name: name,
      ownerUid: ownerUid,
      members: updatedMembers,
      joinCode: joinCode,
    );
  }
}
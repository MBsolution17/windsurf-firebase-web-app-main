// lib/models/chat_message.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Enumération des types de messages.
enum MessageType {
  user,
  ai,
}

/// Enumération des statuts des messages.
enum MessageStatus {
  pending_validation,  // En attente de validation
  validated,           // Validé par l'utilisateur
  rejected,            // Rejeté par l'utilisateur
  modified,            // Modifié par l'utilisateur
}

/// Modèle de données pour un message de chat.
class ChatMessage {
  final String id;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final String userId;
  final String userEmail;
  final MessageStatus status;
  final bool isDraft;
  final int version; // version est maintenant non nullable

  ChatMessage({
    required this.id,
    required this.content,
    required this.type,
    required this.userId,
    required this.userEmail,
    DateTime? timestamp,
    this.status = MessageStatus.pending_validation,
    this.isDraft = false,
    int? version, // version reste optionnel dans le constructeur
  })  : timestamp = timestamp ?? DateTime.now(),
        version = version ?? 0; // Assignation avec valeur par défaut

  /// Factory method to create a ChatMessage from a Firestore DocumentSnapshot
  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      content: data['content'] ?? '',
      type: MessageType.values.firstWhere(
          (e) => e.toString().split('.').last == data['type'],
          orElse: () => MessageType.ai),
      userId: data['userId'] ?? '',
      userEmail: data['userEmail'] ?? 'Utilisateur Inconnu',
      timestamp: data['timestamp'] != null
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now(),
      status: MessageStatus.values.firstWhere(
          (e) => e.toString().split('.').last == data['status'],
          orElse: () => MessageStatus.pending_validation),
      isDraft: data['isDraft'] ?? false,
      version: data['version'] ?? 0, // Assignation avec valeur par défaut
    );
  }

  /// Convert ChatMessage to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'content': content,
      'type': type.toString().split('.').last,
      'userId': userId,
      'userEmail': userEmail,
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status.toString().split('.').last,
      'isDraft': isDraft,
      'version': version, // version est non nullable
    };
  }

  /// Creates a copy of the message with optional modifications
  ChatMessage copyWith({
    String? content,
    MessageType? type,
    DateTime? timestamp,
    String? userId,
    String? userEmail,
    MessageStatus? status,
    bool? isDraft,
    int? version,
  }) {
    return ChatMessage(
      id: this.id,
      content: content ?? this.content,
      type: type ?? this.type,
      userId: userId ?? this.userId,
      userEmail: userEmail ?? this.userEmail,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      isDraft: isDraft ?? this.isDraft,
      version: version ?? this.version, // version est non nullable
    );
  }

  /// Indique si le message est de type IA
  bool get isAI => type == MessageType.ai;

  /// Indique si le message est de type utilisateur
  bool get isUser => type == MessageType.user;
}

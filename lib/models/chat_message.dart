// lib/models/chat_message.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType {
  user,
  ai,
}

enum MessageStatus {
  pending_validation,  // En attente de validation
  validated,           // Validé par l'utilisateur
  rejected,            // Rejeté par l'utilisateur
  modified,            // Modifié par l'utilisateur
}

class ChatMessage {
  final String id;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  final String userId;
  final String userEmail;
  final MessageStatus status;
  final bool isDraft;
  final int? version; // Added version property

  ChatMessage({
    required this.id,
    required this.content,
    required this.type,
    required this.userId,
    required this.userEmail,
    DateTime? timestamp,
    this.status = MessageStatus.pending_validation,
    this.isDraft = false,
    this.version, // Added version parameter
  }) : timestamp = timestamp ?? DateTime.now();

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
      version: data['version'] ?? 0, // Handle version
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
      'version': version ?? 0, // Include version
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
      version: version ?? this.version,
    );
  }
}

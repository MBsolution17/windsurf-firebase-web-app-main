// lib/models/appointment.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Appointment {
  final String id;
  final String contactId;
  final String title;
  final DateTime date;
  final String description;
  final Timestamp timestamp;

  Appointment({
    required this.id,
    required this.contactId,
    required this.title,
    required this.date,
    required this.description,
    required this.timestamp,
  });

  factory Appointment.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Appointment(
      id: doc.id,
      contactId: data['contactId'] ?? '',
      title: data['title'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      description: data['description'] ?? '',
      timestamp: data['timestamp'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'contactId': contactId,
      'title': title,
      'date': Timestamp.fromDate(date),
      'description': description,
      'timestamp': timestamp,
    };
  }
}

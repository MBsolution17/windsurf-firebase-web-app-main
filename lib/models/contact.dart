// lib/models/contact.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class Contact {
  final String id;
  final String userId;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String address;
  final String company;
  final String externalInfo;
  final String folderId;
  final DateTime timestamp;

  Contact({
    required this.id,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.address,
    required this.company,
    required this.externalInfo,
    required this.folderId,
    required this.timestamp,
  });

  factory Contact.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Contact(
      id: doc.id,
      userId: data['userId'] ?? '',
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      address: data['address'] ?? '',
      company: data['company'] ?? '',
      externalInfo: data['externalInfo'] ?? '',
      folderId: data['folderId'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'address': address,
      'company': company,
      'externalInfo': externalInfo,
      'folderId': folderId,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}

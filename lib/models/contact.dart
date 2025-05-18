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
    this.id = '',
    required this.userId,
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.company = '',
    this.externalInfo = '',
    this.folderId = '',
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
      timestamp: (data['timestamp'] as Timestamp).toDate(),
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

  factory Contact.fromJson(Map<String, dynamic> json, String userId) {
    return Contact(
      userId: userId,
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      address: json['address'] ?? '',
      company: json['company'] ?? '',
      externalInfo: json['externalInfo'] ?? '',
      timestamp: DateTime.now(),
    );
  }
}
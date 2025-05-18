// lib/models/task.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// Enums pour le Statut et la Priorité des Tâches
enum TaskStatus { PendingValidation, ToDo, InProgress, Done, Pending }
enum TaskPriority { Low, Medium, High }

/// Modèle de Données pour une Tâche
class Task {
  final String id;
  final String title;
  final String description;
  final DateTime dueDate;
  final int duration; // Durée en minutes
  final String assignee; // ID de l'utilisateur assigné
  final String assigneeName; // Pseudo de l'utilisateur assigné
  final TaskStatus status;
  final TaskPriority priority;
  final String? color; // Ajout du champ color (stocké comme String, ex: "0xFF0000")
  final String? customText; // Ajout du champ customText

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.dueDate,
    required this.duration,
    required this.assignee,
    required this.assigneeName,
    required this.status,
    required this.priority,
    this.color,
    this.customText,
  });

  /// Convertir un document Firestore en objet Task.
  /// Le champ "duration" est récupéré s'il existe, sinon la durée par défaut est fixée à 60 minutes.
  factory Task.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Task(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      dueDate: (data['dueDate'] as Timestamp).toDate(),
      duration: data['duration'] ?? 60, // Durée par défaut : 60 minutes
      assignee: data['assignee'] ?? '',
      assigneeName: data['assigneeName'] ?? 'Non assigné',
      status: _statusFromString(data['status'] ?? 'ToDo'),
      priority: _priorityFromString(data['priority'] ?? 'Low'),
      color: data['color'], // Récupère le champ color
      customText: data['customText'], // Récupère le champ customText
    );
  }

  /// Convertir un objet Task en Map pour Firestore.
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'dueDate': Timestamp.fromDate(dueDate),
      'duration': duration,
      'assignee': assignee,
      'assigneeName': assigneeName,
      'status': _statusToString(status),
      'priority': _priorityToString(priority),
      'color': color, // Ajoute le champ color
      'customText': customText, // Ajoute le champ customText
    };
  }

  // Helpers pour convertir les enums
  static TaskStatus _statusFromString(String status) {
    switch (status) {
      case 'PendingValidation':
        return TaskStatus.PendingValidation;
      case 'ToDo':
        return TaskStatus.ToDo;
      case 'InProgress':
        return TaskStatus.InProgress;
      case 'Done':
        return TaskStatus.Done;
      case 'Pending':
        return TaskStatus.Pending;
      default:
        return TaskStatus.PendingValidation; // Valeur par défaut
    }
  }

  static String _statusToString(TaskStatus status) {
    switch (status) {
      case TaskStatus.PendingValidation:
        return 'PendingValidation';
      case TaskStatus.ToDo:
        return 'ToDo';
      case TaskStatus.InProgress:
        return 'InProgress';
      case TaskStatus.Done:
        return 'Done';
      case TaskStatus.Pending:
        return 'Pending';
    }
  }

  static TaskPriority _priorityFromString(String priority) {
    switch (priority) {
      case 'Low':
        return TaskPriority.Low;
      case 'Medium':
        return TaskPriority.Medium;
      case 'High':
        return TaskPriority.High;
      default:
        return TaskPriority.Low; // Valeur par défaut
    }
  }

  static String _priorityToString(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.Low:
        return 'Low';
      case TaskPriority.Medium:
        return 'Medium';
      case TaskPriority.High:
        return 'High';
    }
  }
}
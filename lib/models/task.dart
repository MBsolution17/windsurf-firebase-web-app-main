// lib/models/task.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// **Enums pour le Statut et la Priorité des Tâches**

enum TaskStatus { PendingValidation, ToDo, InProgress, Done, Pending }
enum TaskPriority { Low, Medium, High }

/// **Modèle de Données pour une Tâche**

class Task {
  final String id;
  final String title;
  final String description;
  final DateTime dueDate;
  final String assignee; // ID de l'utilisateur assigné
  final String assigneeName; // Pseudo de l'utilisateur assigné
  final TaskStatus status;
  final TaskPriority priority;

  Task({
    required this.id,
    required this.title,
    required this.description,
    required this.dueDate,
    required this.assignee,
    required this.assigneeName,
    required this.status,
    required this.priority,
  });

  /// Convertir un document Firestore en objet Task
  factory Task.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Task(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      dueDate: (data['dueDate'] as Timestamp).toDate(),
      assignee: data['assignee'] ?? '',
      assigneeName: data['assigneeName'] ?? 'Non assigné',
      status: _statusFromString(data['status'] ?? 'ToDo'),
      priority: _priorityFromString(data['priority'] ?? 'Low'),
    );
  }

  /// Convertir un objet Task en map pour Firestore
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'dueDate': Timestamp.fromDate(dueDate),
      'assignee': assignee,
      'assigneeName': assigneeName,
      'status': _statusToString(status),
      'priority': _priorityToString(priority),
    };
  }

  /// Helpers pour les enums
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
        return TaskStatus.PendingValidation;
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
        return TaskPriority.Low;
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

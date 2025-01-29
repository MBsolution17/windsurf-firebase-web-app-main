// lib/models/action_event.dart

import 'package:flutter/material.dart';

/// Enumération des types d'actions que l'IA peut exécuter.
enum AIActionType {
  create_task,
  update_task,
  delete_task,
  create_event,
  update_event,
  delete_event,
  create_folder_with_document,
  add_contact,
  create_folder_and_add_contact,
  modify_document,
  // Ajoutez d'autres types d'actions si nécessaire
}

/// Classe représentant un événement d'action.
class ActionEvent {
  final AIActionType actionType;
  final Map<String, dynamic>? data;

  ActionEvent({required this.actionType, this.data});
}

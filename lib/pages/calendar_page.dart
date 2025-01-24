// lib/pages/calendar_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:firebase_web_app/models/task.dart'; // Import du modèle Task

/// **Page de Calendrier**

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  _CalendarPageState createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Task>> _tasksByDate = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchAllTasks();
  }

  /// Méthode pour récupérer toutes les tâches et les organiser par date
  Future<void> _fetchAllTasks() async {
    QuerySnapshot snapshot = await _firestore.collection('tasks').orderBy('dueDate').get();

    Map<DateTime, List<Task>> tasksMap = {};

    for (var doc in snapshot.docs) {
      Task task = Task.fromFirestore(doc);
      DateTime date = DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day);
      if (tasksMap[date] == null) {
        tasksMap[date] = [];
      }
      tasksMap[date]!.add(task);
    }

    setState(() {
      _tasksByDate = tasksMap;
    });
  }

  /// Met à jour les tâches sélectionnées pour le jour donné
  void _updateSelectedTasks(DateTime day) {
    setState(() {
      _selectedDay = day;
      _focusedDay = day;
    });
  }

  /// Vérifie si deux dates sont le même jour
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Widget pour afficher chaque tâche dans le calendrier
  Widget _buildCalendarTaskCard(Task task) {
    Color priorityColor;
    switch (task.priority) {
      case TaskPriority.Low:
        priorityColor = Colors.green;
        break;
      case TaskPriority.Medium:
        priorityColor = Colors.orange;
        break;
      case TaskPriority.High:
        priorityColor = Colors.red;
        break;
      default:
        priorityColor = Colors.grey;
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: ListTile(
        title: Text(
          task.title,
          style: GoogleFonts.lato(
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        subtitle: Text(
          task.description,
          style: GoogleFonts.lato(
            textStyle: const TextStyle(
              fontSize: 14,
              color: Colors.black54,
            ),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Statut
            Chip(
              label: Text(task.status.toString().split('.').last),
              backgroundColor: _getStatusColor(task.status),
            ),
            const SizedBox(height: 4),
            // Priorité
            Chip(
              label: Text(task.priority.toString().split('.').last),
              backgroundColor: priorityColor.withOpacity(0.2),
              avatar: CircleAvatar(
                backgroundColor: priorityColor,
                radius: 6,
              ),
            ),
          ],
        ),
        onTap: () {
          _showTaskDetailsDialog(task);
        },
      ),
    );
  }

  /// Fonction pour afficher les détails d'une tâche
  void _showTaskDetailsDialog(Task task) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(task.title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Description: ${task.description}'),
                const SizedBox(height: 8),
                Text('Assigné à: ${task.assignee}'),
                const SizedBox(height: 8),
                Text('Échéance: ${DateFormat('dd/MM/yyyy').format(task.dueDate)}'),
                const SizedBox(height: 8),
                Text('Statut: ${task.status.toString().split('.').last}'),
                const SizedBox(height: 8),
                Text('Priorité: ${task.priority.toString().split('.').last}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Fermer'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Fonction pour obtenir la couleur du statut
  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.ToDo:
        return Colors.blue;
      case TaskStatus.InProgress:
        return Colors.orange;
      case TaskStatus.Done:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    List<Task> selectedTasks = _selectedDay != null
        ? _tasksByDate[_selectedDay!] ?? []
        : [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
      ),
      body: Column(
        children: [
          TableCalendar<Task>(
            firstDay: DateTime.utc(2000, 1, 1),
            lastDay: DateTime.utc(2100, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => _isSameDay(_selectedDay ?? DateTime.now(), day),
            calendarFormat: _calendarFormat,
            eventLoader: (day) {
              return _tasksByDate[DateTime(day.year, day.month, day.day)] ?? [];
            },
            startingDayOfWeek: StartingDayOfWeek.monday,
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.blueAccent,
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Colors.orangeAccent,
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
            onDaySelected: (selectedDay, focusedDay) {
              _updateSelectedTasks(selectedDay);
            },
            onFormatChanged: (format) {
              if (_calendarFormat != format) {
                setState(() {
                  _calendarFormat = format;
                });
              }
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
          ),
          const SizedBox(height: 8.0),
          // Liste des tâches pour le jour sélectionné
          Expanded(
            child: selectedTasks.isEmpty
                ? const Center(
                    child: Text('Aucune tâche pour cette journée.'),
                  )
                : ListView.builder(
                    itemCount: selectedTasks.length,
                    itemBuilder: (context, index) {
                      final task = selectedTasks[index];
                      return _buildCalendarTaskCard(task);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

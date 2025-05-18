import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

// Utilisez un alias pour éviter les conflits avec Task de Firebase Storage.
import '../models/task.dart' as taskModel;

/// Modèle représentant un événement de calendrier.
class CalendarEvent {
  final String id;
  final String summary;
  final String description;
  final DateTime start;
  final DateTime end;
  final String? ownerId;
  final Color? color;
  final String? customText;

  CalendarEvent({
    required this.id,
    required this.summary,
    required this.description,
    required this.start,
    required this.end,
    this.ownerId,
    this.color,
    this.customText,
  });

  factory CalendarEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CalendarEvent(
      id: doc.id,
      summary: data['summary'] ?? 'Sans titre',
      description: data['description'] ?? '',
      start: (data['start'] as Timestamp).toDate(),
      end: (data['end'] as Timestamp).toDate(),
      ownerId: data['ownerId'],
      color: data['color'] != null
          ? Color(int.parse(data['color'].replaceFirst('0x', ''), radix: 16))
          : null,
      customText: data['customText'],
    );
  }

  CalendarEvent copyWith({
    DateTime? start,
    DateTime? end,
    String? ownerId,
    Color? color,
    String? customText,
  }) {
    return CalendarEvent(
      id: id,
      summary: summary,
      description: description,
      start: start ?? this.start,
      end: end ?? this.end,
      ownerId: ownerId ?? this.ownerId,
      color: color ?? this.color,
      customText: customText ?? this.customText,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'summary': summary,
      'description': description,
      'start': Timestamp.fromDate(start),
      'end': Timestamp.fromDate(end),
      'ownerId': ownerId,
      'color': color != null ? '0x${color!.value.toRadixString(16)}' : null,
      'customText': customText,
    };
  }
}

/// Page principale affichant simultanément la vue mensuelle et la vue hebdomadaire.
class CalendarPage extends StatefulWidget {
  final String workspaceId;
  const CalendarPage({Key? key, required this.workspaceId}) : super(key: key);

  @override
  _CalendarPageState createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<CalendarEvent> _allEvents = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Pour le filtrage par membre (ownerId)
  List<Map<String, dynamic>> _teamMembers = [];
  String? _selectedTeamMemberId;

  // Date de référence pour la vue hebdomadaire.
  DateTime _currentWeekStart = _getStartOfWeek(DateTime.now());
  // Date de référence pour la vue mensuelle.
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // Hauteur d'une cellule horaire et largeur de la colonne des heures.
  final double _hourHeight = 100.0;
  final double _hoursColumnWidth = 40.0;

  // Liste de couleurs pour les membres
  final List<Color> _memberColors = [
    Colors.blue.withOpacity(0.7),
    Colors.red.withOpacity(0.7),
    Colors.green.withOpacity(0.7),
    Colors.orange.withOpacity(0.7),
    Colors.purple.withOpacity(0.7),
    Colors.teal.withOpacity(0.7),
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // Attendre que les membres et les événements/tâches soient chargés
      await Future.wait([
        _fetchTeamMembers(),
        _fetchCalendarEventsAndTasks(),
      ]);
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors de la récupération: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchTeamMembers() async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('workspaces')
          .doc(widget.workspaceId)
          .collection('users')
          .get();
      setState(() {
        _teamMembers = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            "id": doc.id,
            "displayName": data['displayName'] ?? 'Utilisateur inconnu',
            "photoURL": data['photoURL'],
            "isOnline": data['isOnline'] ?? false,
          };
        }).toList();
      });
    } catch (e) {
      debugPrint('Erreur lors de la récupération des membres: $e');
      setState(() {
        _teamMembers = [];
      });
    }
  }

  Future<void> _fetchCalendarEventsAndTasks() async {
    QuerySnapshot calendarSnapshot = await _firestore
        .collection('workspaces')
        .doc(widget.workspaceId)
        .collection('calendar_events')
        .orderBy('start', descending: false)
        .get();
    List<CalendarEvent> calendarEvents = calendarSnapshot.docs
        .map((doc) => CalendarEvent.fromFirestore(doc))
        .toList();

    QuerySnapshot tasksSnapshot = await _firestore
        .collection('workspaces')
        .doc(widget.workspaceId)
        .collection('tasks')
        .orderBy('dueDate')
        .get();
    List<CalendarEvent> taskEvents = tasksSnapshot.docs.map((doc) {
      taskModel.Task task = taskModel.Task.fromFirestore(doc);
      DateTime start = task.dueDate;
      DateTime end = task.dueDate.add(Duration(minutes: task.duration));
      Color? eventColor = _getColorForMember(task.assignee);
      Color? taskColor;
      if (task.color != null) {
        try {
          taskColor = Color(int.parse(task.color!.replaceFirst('0x', ''), radix: 16));
        } catch (e) {
          debugPrint('Erreur de format pour la couleur de la tâche ${task.id}: $e');
          taskColor = null;
        }
      }
      return CalendarEvent(
        id: task.id,
        summary: task.title,
        description: task.description,
        start: start,
        end: end,
        ownerId: task.assignee,
        color: taskColor ?? eventColor ?? Colors.grey.withOpacity(0.7),
        customText: task.customText,
      );
    }).toList();

    setState(() {
      _allEvents = [...calendarEvents, ...taskEvents];
    });
  }

  Future<Uint8List?> _loadProfileImage(String? photoURL) async {
    if (photoURL == null) return null;
    try {
      final response = await http.get(
        Uri.parse(
            'https://getprofileimage-iu4ydislpq-uc.a.run.app?url=${Uri.encodeComponent(photoURL)}'),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['imageBase64'] != null) {
          return base64Decode(json['imageBase64']);
        }
      }
    } catch (e) {
      debugPrint('Erreur lors du chargement de l’image via Firebase Function : $e');
    }
    return null;
  }

  static DateTime _getStartOfWeek(DateTime date) {
    int daysToSubtract = date.weekday - DateTime.monday;
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: daysToSubtract));
  }

  Color? _getColorForMember(String? memberId) {
    if (memberId == null || _teamMembers.isEmpty) return null;
    int index = _teamMembers.indexWhere((member) => member["id"] == memberId);
    if (index >= 0 && index < _memberColors.length) {
      return _memberColors[index];
    }
    return _memberColors[_teamMembers.length % _memberColors.length];
  }

  List<CalendarEvent> _getEventsForCurrentWeek() {
    DateTime weekEnd = _currentWeekStart.add(const Duration(days: 7));
    return _allEvents.where((event) {
      bool inWeek =
          event.start.isBefore(weekEnd) && event.end.isAfter(_currentWeekStart);
      if (_selectedTeamMemberId != null) {
        return inWeek && event.ownerId == _selectedTeamMemberId;
      }
      return inWeek;
    }).toList();
  }

  void _previousWeek() {
    setState(() {
      _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    setState(() {
      _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
    });
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
  }

  Future<void> _updateEvent(CalendarEvent updatedEvent) async {
    setState(() {
      _allEvents = _allEvents.map((event) {
        return event.id == updatedEvent.id ? updatedEvent : event;
      }).toList();
    });

    try {
      await _firestore
          .collection('workspaces')
          .doc(widget.workspaceId)
          .collection('calendar_events')
          .doc(updatedEvent.id)
          .update({
        'start': updatedEvent.start,
        'end': updatedEvent.end,
        'ownerId': updatedEvent.ownerId,
        'color': updatedEvent.color != null
            ? '0x${updatedEvent.color!.value.toRadixString(16)}'
            : null,
        'customText': updatedEvent.customText,
      });
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        try {
          int newDuration =
              updatedEvent.end.difference(updatedEvent.start).inMinutes;
          await _firestore
              .collection('workspaces')
              .doc(widget.workspaceId)
              .collection('tasks')
              .doc(updatedEvent.id)
              .update({
            'dueDate': Timestamp.fromDate(updatedEvent.start),
            'duration': newDuration,
            'assignee': updatedEvent.ownerId,
            'color': updatedEvent.color != null
                ? '0x${updatedEvent.color!.value.toRadixString(16)}'
                : null,
            'customText': updatedEvent.customText,
          });
        } on FirebaseException catch (e2) {
          debugPrint('Erreur lors de la mise à jour dans tasks: $e2');
        }
      } else {
        debugPrint('Erreur lors de la mise à jour: $e');
      }
    }
  }

  void _showEventDetails(CalendarEvent event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          event.summary,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(
              'De ${DateFormat.Hm().format(event.start)} à ${DateFormat.Hm().format(event.end)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (event.customText != null) ...[
              const SizedBox(height: 8),
              Text(
                'Note: ${event.customText}',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: Theme.of(context).textTheme.bodyMedium!.color!.withOpacity(0.6),
                    ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Fermer',
                style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
          ),
        ],
      ),
    );
  }

  void _addTask() async {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    final TextEditingController customTextController = TextEditingController();
    DateTime selectedStart = DateTime.now();
    int selectedDuration = 60; // Durée par défaut : 1 heure
    String? selectedAssignee;
    Color selectedColor = Colors.blue.withOpacity(0.7);

    const int minDuration = 15;
    const int maxDuration = 10080; // 7 jours
    int divisions = ((maxDuration - minDuration) / 15).round();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text("Créer une tâche", style: Theme.of(context).textTheme.titleLarge),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        labelText: 'Titre',
                        labelStyle: Theme.of(context).textTheme.bodyMedium,
                        border: const OutlineInputBorder(),
                      ),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        labelStyle: Theme.of(context).textTheme.bodyMedium,
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text("Début : ", style: Theme.of(context).textTheme.bodyMedium),
                        Text(DateFormat('yyyy-MM-dd HH:mm').format(selectedStart),
                            style: Theme.of(context).textTheme.bodyLarge),
                        TextButton(
                          onPressed: () async {
                            DateTime? pickedDate = await showDatePicker(
                              context: context,
                              initialDate: selectedStart,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: Theme.of(context).colorScheme.copyWith(
                                          primary: Theme.of(context).colorScheme.primary,
                                          onPrimary: Theme.of(context).colorScheme.onPrimary,
                                          surface: Theme.of(context).cardColor,
                                          onSurface: Theme.of(context).textTheme.bodyLarge!.color,
                                        ),
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (pickedDate != null) {
                              TimeOfDay initialTime = TimeOfDay.fromDateTime(selectedStart);
                              TimeOfDay? pickedTime = await showTimePicker(
                                context: context,
                                initialTime: initialTime,
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: Theme.of(context).colorScheme.copyWith(
                                            primary: Theme.of(context).colorScheme.primary,
                                            onPrimary: Theme.of(context).colorScheme.onPrimary,
                                            surface: Theme.of(context).cardColor,
                                            onSurface: Theme.of(context).textTheme.bodyLarge!.color,
                                          ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (pickedTime != null) {
                                setDialogState(() {
                                  selectedStart = DateTime(
                                    pickedDate.year,
                                    pickedDate.month,
                                    pickedDate.day,
                                    pickedTime.hour,
                                    pickedTime.minute,
                                  );
                                });
                              }
                            }
                          },
                          child: Text("Modifier",
                              style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text("Durée : ", style: Theme.of(context).textTheme.bodyMedium),
                        Text("$selectedDuration min", style: Theme.of(context).textTheme.bodyLarge),
                      ],
                    ),
                    Slider(
                      value: selectedDuration.toDouble(),
                      min: minDuration.toDouble(),
                      max: maxDuration.toDouble(),
                      divisions: divisions > 0 ? divisions : null,
                      label: "$selectedDuration minutes",
                      activeColor: Theme.of(context).colorScheme.primary,
                      inactiveColor: Theme.of(context).unselectedWidgetColor,
                      onChanged: (value) {
                        setDialogState(() {
                          selectedDuration = value.round();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_teamMembers.isNotEmpty)
                      Row(
                        children: [
                          Text("Assigné : ", style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: selectedAssignee,
                            hint: Text("Sélectionner",
                                style: Theme.of(context).textTheme.bodyMedium),
                            items: _teamMembers
                                .map((member) => DropdownMenuItem<String>(
                                      value: member["id"],
                                      child: Text(member["displayName"],
                                          style: Theme.of(context).textTheme.bodyLarge),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedAssignee = value;
                              });
                            },
                            dropdownColor: Theme.of(context).cardColor,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      )
                    else
                      Text(
                        "Aucun membre d'équipe disponible.",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text("Couleur : ", style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(width: 8),
                        Wrap(
                          spacing: 8,
                          children: _memberColors.map((color) {
                            return GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  selectedColor = color;
                                });
                              },
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selectedColor == color
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: customTextController,
                      decoration: InputDecoration(
                        labelText: 'Note ou étiquette',
                        labelStyle: Theme.of(context).textTheme.bodyMedium,
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Annuler",
                      style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (titleController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Le titre est requis',
                                style: Theme.of(context).textTheme.bodyMedium)),
                      );
                      return;
                    }
                    Navigator.pop(context, {
                      'title': titleController.text,
                      'description': descriptionController.text,
                      'start': selectedStart,
                      'duration': selectedDuration,
                      'assignee': selectedAssignee,
                      'color': selectedColor.value.toRadixString(16),
                      'customText': customTextController.text.isNotEmpty
                          ? customTextController.text
                          : null,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[700]
                        : Theme.of(context).elevatedButtonTheme.style!.backgroundColor!
                            .resolve({}),
                    foregroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Theme.of(context).elevatedButtonTheme.style!.foregroundColor!
                            .resolve({}),
                    side: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Theme.of(context).elevatedButtonTheme.style!.foregroundColor!
                              .resolve({})!,
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 4,
                    shadowColor: Colors.black.withOpacity(0.25),
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  ),
                  child: Text("Créer", style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      DateTime start = result['start'];
      DateTime end = start.add(Duration(minutes: result['duration']));
      CalendarEvent newEvent = CalendarEvent(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        summary: result['title'],
        description: result['description'],
        start: start,
        end: end,
        ownerId: result['assignee'],
        color: Color(
            int.parse('0x${result['color'] ?? selectedColor.value.toRadixString(16)}')),
        customText: result['customText'],
      );

      setState(() {
        _allEvents.add(newEvent);
      });

      try {
        await _firestore
            .collection('workspaces')
            .doc(widget.workspaceId)
            .collection('calendar_events')
            .doc(newEvent.id)
            .set(newEvent.toFirestore());
      } catch (e) {
        debugPrint('Erreur lors de la création de la tâche: $e');
        setState(() {
          _allEvents.remove(newEvent);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur lors de la création: $e',
                  style: Theme.of(context).textTheme.bodyMedium)),
        );
      }
    }
  }

  void _editTask(CalendarEvent event) async {
    DateTime selectedStart = event.start;
    int selectedDuration = event.end.difference(event.start).inMinutes;
    String? selectedAssignee = event.ownerId;

    if (selectedAssignee != null &&
        !_teamMembers.any((member) => member["id"] == selectedAssignee)) {
      selectedAssignee = null;
    }

    Color selectedColor = event.color ?? Colors.blue.withOpacity(0.7);
    final TextEditingController customTextController =
        TextEditingController(text: event.customText ?? '');

    const int minDuration = 15;
    int maxDuration = selectedDuration > 10080 ? selectedDuration : 10080;
    int divisions = ((maxDuration - minDuration) / 15).round();

    TimeOfDay initialTime = TimeOfDay.fromDateTime(selectedStart);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text("Modifier la tâche", style: Theme.of(context).textTheme.titleLarge),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text("Début : ", style: Theme.of(context).textTheme.bodyMedium),
                          Text(
                            DateFormat('yyyy-MM-dd').format(selectedStart),
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          TextButton(
                            onPressed: () async {
                              DateTime? pickedDate = await showDatePicker(
                                context: context,
                                initialDate: selectedStart,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: Theme.of(context).colorScheme.copyWith(
                                            primary: Theme.of(context).colorScheme.primary,
                                            onPrimary: Theme.of(context).colorScheme.onPrimary,
                                            surface: Theme.of(context).cardColor,
                                            onSurface: Theme.of(context).textTheme.bodyLarge!.color,
                                          ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (pickedDate != null) {
                                setDialogState(() {
                                  selectedStart = DateTime(
                                    pickedDate.year,
                                    pickedDate.month,
                                    pickedDate.day,
                                    initialTime.hour,
                                    initialTime.minute,
                                  );
                                });
                              }
                            },
                            child: Text("Modifier la date",
                                style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 120,
                            child: Row(
                              children: [
                                Expanded(
                                  child: DropdownButton<int>(
                                    value: initialTime.hour,
                                    items: List.generate(24, (index) => index)
                                        .map((hour) => DropdownMenuItem<int>(
                                              value: hour,
                                              child: Text(hour.toString().padLeft(2, '0'),
                                                  style: Theme.of(context).textTheme.bodyLarge),
                                            ))
                                        .toList(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        setDialogState(() {
                                          initialTime = TimeOfDay(hour: value, minute: initialTime.minute);
                                          selectedStart = DateTime(
                                            selectedStart.year,
                                            selectedStart.month,
                                            selectedStart.day,
                                            value,
                                            initialTime.minute,
                                          );
                                        });
                                      }
                                    },
                                    dropdownColor: Theme.of(context).cardColor,
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ),
                                const Text(':'),
                                Expanded(
                                  child: DropdownButton<int>(
                                    value: initialTime.minute,
                                    items: [0, 15, 30, 45]
                                        .map((minute) => DropdownMenuItem<int>(
                                              value: minute,
                                              child: Text(minute.toString().padLeft(2, '0'),
                                                  style: Theme.of(context).textTheme.bodyLarge),
                                            ))
                                        .toList(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        setDialogState(() {
                                          initialTime = TimeOfDay(hour: initialTime.hour, minute: value);
                                          selectedStart = DateTime(
                                            selectedStart.year,
                                            selectedStart.month,
                                            selectedStart.day,
                                            initialTime.hour,
                                            value,
                                          );
                                        });
                                      }
                                    },
                                    dropdownColor: Theme.of(context).cardColor,
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text("Durée : ", style: Theme.of(context).textTheme.bodyMedium),
                          Text("$selectedDuration min",
                              style: Theme.of(context).textTheme.bodyLarge),
                        ],
                      ),
                      Slider(
                        value: selectedDuration.toDouble(),
                        min: minDuration.toDouble(),
                        max: maxDuration.toDouble(),
                        divisions: divisions > 0 ? divisions : null,
                        label: "$selectedDuration minutes",
                        activeColor: Theme.of(context).colorScheme.primary,
                        inactiveColor: Theme.of(context).unselectedWidgetColor,
                        onChanged: (value) {
                          setDialogState(() {
                            selectedDuration = value.round();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (_teamMembers.isNotEmpty)
                        Row(
                          children: [
                            Text("Assigné : ", style: Theme.of(context).textTheme.bodyMedium),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: selectedAssignee,
                              hint: Text("Sélectionner",
                                  style: Theme.of(context).textTheme.bodyMedium),
                              items: _teamMembers
                                  .map((member) => DropdownMenuItem<String>(
                                        value: member["id"],
                                        child: Text(member["displayName"],
                                            style: Theme.of(context).textTheme.bodyLarge),
                                      ))
                                  .toList(),
                              onChanged: (value) {
                                setDialogState(() {
                                  selectedAssignee = value;
                                });
                              },
                              dropdownColor: Theme.of(context).cardColor,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text("Couleur : ", style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(width: 8),
                          Wrap(
                            spacing: 8,
                            children: _memberColors.map((color) {
                              return GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    selectedColor = color;
                                  });
                                },
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selectedColor == color
                                          ? Theme.of(context).colorScheme.primary
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: customTextController,
                        decoration: InputDecoration(
                          labelText: 'Note ou étiquette',
                          labelStyle: Theme.of(context).textTheme.bodyMedium,
                          border: const OutlineInputBorder(),
                        ),
                        maxLines: 2,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Annuler",
                      style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    DateTime newEnd =
                        selectedStart.add(Duration(minutes: selectedDuration));
                    _updateEvent(
                      event.copyWith(
                        start: selectedStart,
                        end: newEnd,
                        ownerId: selectedAssignee,
                        color: selectedColor,
                        customText: customTextController.text.isNotEmpty
                            ? customTextController.text
                            : null,
                      ),
                    );
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[700]
                        : Theme.of(context).elevatedButtonTheme.style!.backgroundColor!
                            .resolve({}),
                    foregroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Theme.of(context).elevatedButtonTheme.style!.foregroundColor!
                            .resolve({}),
                    side: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Theme.of(context).elevatedButtonTheme.style!.foregroundColor!
                              .resolve({})!,
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 4,
                    shadowColor: Colors.black.withOpacity(0.25),
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  ),
                  child: Text("Valider", style: Theme.of(context).textTheme.titleMedium),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double verticalOffset = MediaQuery.of(context).size.height * 0.05;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Calendrier",
          style: Theme.of(context).textTheme.titleLarge,
        ),
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).cardColor,
        elevation: 2,
        iconTheme: Theme.of(context).iconTheme,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Rafraîchir",
            onPressed: _fetchData,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: "Semaine précédente",
            onPressed: _previousWeek,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: "Semaine suivante",
            onPressed: _nextWeek,
          ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error, fontSize: 16),
                  ),
                )
              : Center(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 15,
                        child: Padding(
                          padding: EdgeInsets.only(top: verticalOffset),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: ElevatedButton.icon(
                                  onPressed: _addTask,
                                  icon: Icon(Icons.add,
                                      color: Theme.of(context).iconTheme.color),
                                  label: Text("Créer",
                                      style: Theme.of(context).textTheme.titleMedium),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).brightness == Brightness.dark
                                            ? Colors.grey[700]
                                            : Theme.of(context)
                                                .elevatedButtonTheme
                                                .style!
                                                .backgroundColor!
                                                .resolve({}),
                                    foregroundColor:
                                        Theme.of(context).brightness == Brightness.dark
                                            ? Colors.white
                                            : Theme.of(context)
                                                .elevatedButtonTheme
                                                .style!
                                                .foregroundColor!
                                                .resolve({}),
                                    side: BorderSide(
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : Theme.of(context)
                                              .elevatedButtonTheme
                                              .style!
                                              .foregroundColor!
                                              .resolve({})!,
                                      width: 1,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 4,
                                    shadowColor: Colors.black.withOpacity(0.25),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 40, vertical: 20),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),
                              Expanded(
                                child: MonthlyCalendar(
                                  currentMonth: _currentMonth,
                                  events: _allEvents,
                                  onPrevMonth: _previousMonth,
                                  onNextMonth: _nextMonth,
                                  onDayTap: (day) {
                                    setState(() {
                                      _currentWeekStart = _getStartOfWeek(day);
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                color: Theme.of(context).cardColor,
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Membres de l\'équipe',
                                            style: Theme.of(context).textTheme.titleMedium,
                                          ),
                                          if (_selectedTeamMemberId != null)
                                            TextButton(
                                              onPressed: () {
                                                setState(() {
                                                  _selectedTeamMemberId = null;
                                                });
                                              },
                                              child: Text(
                                                'Tous les membres',
                                                style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .secondary),
                                              ),
                                            ),
                                        ],
                                      ),
                                      Divider(
                                          color: Theme.of(context).dividerColor,
                                          thickness: 1),
                                      const SizedBox(height: 10),
                                      _teamMembers.isEmpty
                                          ? Center(
                                              child: Text(
                                                'Aucun membre trouvé.',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium,
                                              ),
                                            )
                                          : SizedBox(
                                              height: 300,
                                              child: ListView.builder(
                                                itemCount: _teamMembers.length,
                                                itemBuilder: (context, index) {
                                                  var member = _teamMembers[index];
                                                  bool isSelected =
                                                      member["id"] == _selectedTeamMemberId;
                                                  return GestureDetector(
                                                    onTap: () {
                                                      setState(() {
                                                        _selectedTeamMemberId = member["id"];
                                                      });
                                                    },
                                                    child: Column(
                                                      children: [
                                                        ListTile(
                                                          leading: FutureBuilder<Uint8List?>(
                                                            future: _loadProfileImage(
                                                                member["photoURL"]),
                                                            builder: (context, imageSnapshot) {
                                                              return Container(
                                                                decoration: BoxDecoration(
                                                                  shape: BoxShape.circle,
                                                                  border: Border.all(
                                                                    color: isSelected
                                                                        ? Theme.of(context)
                                                                            .colorScheme
                                                                            .primary
                                                                        : (member["isOnline"]
                                                                            ? Colors.green
                                                                            : Theme.of(context)
                                                                                .unselectedWidgetColor),
                                                                    width: 2,
                                                                  ),
                                                                ),
                                                                child: CircleAvatar(
                                                                  radius: 20,
                                                                  backgroundColor: Colors.grey[400], // Changé en gris
                                                                  backgroundImage: imageSnapshot.data != null
                                                                      ? MemoryImage(imageSnapshot.data!)
                                                                      : (member["photoURL"] != null
                                                                          ? NetworkImage(member["photoURL"])
                                                                          : null) as ImageProvider?,
                                                                  child: imageSnapshot.data == null &&
                                                                          member["photoURL"] == null
                                                                      ? Text(
                                                                          member["displayName"]
                                                                                  .isNotEmpty
                                                                              ? member["displayName"][0]
                                                                                  .toUpperCase()
                                                                              : '?',
                                                                          style: TextStyle(
                                                                              color: Theme.of(context)
                                                                                  .colorScheme
                                                                                  .onPrimary),
                                                                        )
                                                                      : null,
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                          title: Text(
                                                            member["displayName"],
                                                            style: TextStyle(
                                                              fontWeight: FontWeight.bold,
                                                              color: isSelected
                                                                  ? Theme.of(context)
                                                                      .colorScheme
                                                                      .primary
                                                                  : Theme.of(context)
                                                                      .textTheme
                                                                      .bodyLarge!
                                                                      .color,
                                                            ),
                                                          ),
                                                          subtitle: Text(
                                                            member["isOnline"]
                                                                ? 'En ligne'
                                                                : 'Hors ligne',
                                                            style: TextStyle(
                                                              color: member["isOnline"]
                                                                  ? Colors.green
                                                                  : Theme.of(context)
                                                                      .textTheme
                                                                      .bodyMedium!
                                                                      .color,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                          trailing: Icon(
                                                            member["isOnline"]
                                                                ? Icons.circle
                                                                : Icons.circle_outlined,
                                                            color: member["isOnline"]
                                                                ? Colors.green
                                                                : Theme.of(context)
                                                                    .unselectedWidgetColor,
                                                            size: 16,
                                                          ),
                                                        ),
                                                        if (index < _teamMembers.length - 1)
                                                          Divider(
                                                              color: Theme.of(context).dividerColor,
                                                              thickness: 1),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 85,
                        child: WeeklyCalendar(
                          weekStart: _currentWeekStart,
                          events: _getEventsForCurrentWeek(),
                          teamMembers: _teamMembers,
                          onEventTap: (event) => _editTask(event),
                          hourHeight: _hourHeight,
                          hoursColumnWidth: _hoursColumnWidth,
                          onEventDragOrResize: _updateEvent,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

/// Callback pour le tap sur un événement.
typedef EventTapCallback = void Function(CalendarEvent event);
typedef EventUpdateCallback = void Function(CalendarEvent updatedEvent);

/// Vue hebdomadaire du calendrier.
class WeeklyCalendar extends StatefulWidget {
  final DateTime weekStart;
  final List<CalendarEvent> events;
  final EventTapCallback? onEventTap;
  final EventUpdateCallback? onEventDragOrResize;
  final double hourHeight;
  final double hoursColumnWidth;
  final List<Map<String, dynamic>>? teamMembers;

  const WeeklyCalendar({
    Key? key,
    required this.weekStart,
    required this.events,
    this.onEventTap,
    this.onEventDragOrResize,
    required this.hourHeight,
    required this.hoursColumnWidth,
    this.teamMembers,
  }) : super(key: key);

  @override
  _WeeklyCalendarState createState() => _WeeklyCalendarState();
}

class _WeeklyCalendarState extends State<WeeklyCalendar> {
  late ScrollController _verticalController;

  @override
  void initState() {
    super.initState();
    _verticalController =
        ScrollController(initialScrollOffset: widget.hourHeight * 8);
  }

  @override
  void didUpdateWidget(covariant WeeklyCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hourHeight != widget.hourHeight) {
      _verticalController.jumpTo(widget.hourHeight * 8);
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      double availableWidth = constraints.maxWidth - widget.hoursColumnWidth;
      double computedDayWidth = availableWidth / 7;
      return Column(
        children: [
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: widget.hoursColumnWidth,
                  child: const Center(child: Text('')),
                ),
                ...List.generate(7, (index) {
                  DateTime day = widget.weekStart.add(Duration(days: index));
                  String dayName = DateFormat('EEE', 'fr_FR').format(day).toUpperCase();
                  String dayNumber = DateFormat('dd').format(day);
                  bool isToday = day.year == DateTime.now().year &&
                      day.month == DateTime.now().month &&
                      day.day == DateTime.now().day;
                  return Container(
                    width: computedDayWidth,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      border: Border.all(
                          color: Theme.of(context).dividerColor,
                          width: isToday ? 2 : 1),
                      borderRadius: isToday
                          ? BorderRadius.circular(20)
                          : BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dayName,
                          style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dayNumber,
                          style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                                fontSize: 12,
                              ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _verticalController,
              physics: const BouncingScrollPhysics(),
              scrollDirection: Axis.vertical,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: widget.hoursColumnWidth,
                      child: Column(
                        children: List.generate(25, (index) {
                          return Container(
                            height: widget.hourHeight,
                            alignment: Alignment.topCenter,
                            decoration: BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: Theme.of(context).dividerColor,
                                      width: 1)),
                            ),
                            child: Text(
                              '$index:00',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium!
                                  .copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                            ),
                          );
                        }),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Container(
                        width: 7 * computedDayWidth,
                        height: 24 * widget.hourHeight,
                        child: Stack(
                          children: [
                            CustomPaint(
                              size: Size(7 * computedDayWidth, 24 * widget.hourHeight),
                              painter: CalendarGridPainter(
                                hourHeight: widget.hourHeight,
                                dayWidth: computedDayWidth,
                                context: context,
                              ),
                            ),
                            ..._buildEventWidgets(computedDayWidth),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  List<Widget> _buildEventWidgets(double computedDayWidth) {
    Map<int, List<CalendarEvent>> dayGroups = {};
    for (var event in widget.events) {
      DateTime eventStart =
          DateTime(event.start.year, event.start.month, event.start.day);
      DateTime weekStartDate =
          DateTime(widget.weekStart.year, widget.weekStart.month, widget.weekStart.day);
      int dayIndex = eventStart.difference(weekStartDate).inDays;
      if (dayIndex < 0 || dayIndex > 6) continue;
      dayGroups.putIfAbsent(dayIndex, () => []).add(event);
    }

    List<Widget> widgets = [];
    dayGroups.forEach((dayIndex, eventList) {
      eventList.sort((a, b) => a.start.compareTo(b.start));

      const Duration interval = Duration(minutes: 15);
      Map<DateTime, List<CalendarEvent>> timeSlots = {};
      for (var event in eventList) {
        DateTime slotStart = DateTime(event.start.year, event.start.month,
            event.start.day, event.start.hour, (event.start.minute ~/ 15) * 15);
        while (slotStart.isBefore(event.end)) {
          timeSlots.putIfAbsent(slotStart, () => []).add(event);
          slotStart = slotStart.add(interval);
        }
      }

      Map<DateTime, int> maxColumnsPerSlot = {};
      timeSlots.forEach((slotTime, eventsInSlot) {
        int activeEvents = 0;
        for (var event in eventList) {
          if (!(event.end.isBefore(slotTime) ||
              event.start.isAfter(slotTime.add(interval)))) {
            activeEvents++;
          }
        }
        maxColumnsPerSlot[slotTime] = activeEvents;
      });

      Map<CalendarEvent, int> eventColumns = {};
      for (var event in eventList) {
        int column = 0;
        bool placed = false;
        DateTime slotStart = DateTime(event.start.year, event.start.month,
            event.start.day, event.start.hour, (event.start.minute ~/ 15) * 15);

        while (slotStart.isBefore(event.end) && !placed) {
          int maxOverlap = maxColumnsPerSlot[slotStart] ?? 1;
          for (int col = 0; col < maxOverlap; col++) {
            bool overlaps = false;
            for (var otherEvent in eventList) {
              if (otherEvent != event &&
                  eventColumns.containsKey(otherEvent) &&
                  eventColumns[otherEvent] == col &&
                  !(event.end.isBefore(otherEvent.start) ||
                      event.start.isAfter(otherEvent.end))) {
                overlaps = true;
                break;
              }
            }
            if (!overlaps) {
              eventColumns[event] = col;
              placed = true;
              break;
            }
          }
          if (!placed && column < (maxColumnsPerSlot[slotStart] ?? 1) - 1) {
            column++;
          }
          slotStart = slotStart.add(interval);
        }
        if (!placed) {
          eventColumns[event] = 0;
        }
      }

      eventColumns.forEach((event, column) {
        double top = (event.start.hour + event.start.minute / 60.0) * widget.hourHeight;
        double durationHours = event.end.difference(event.start).inMinutes / 60.0;
        double height = durationHours * widget.hourHeight;
        if (height < 20) height = 20;

        int maxOverlapForEvent = 1;
        DateTime slotStart = DateTime(event.start.year, event.start.month,
            event.start.day, event.start.hour, (event.start.minute ~/ 15) * 15);
        while (slotStart.isBefore(event.end)) {
          int overlap = maxColumnsPerSlot[slotStart] ?? 1;
          maxOverlapForEvent =
              maxOverlapForEvent > overlap ? maxOverlapForEvent : overlap;
          slotStart = slotStart.add(interval);
        }
        double columnWidth = computedDayWidth / maxOverlapForEvent;
        double left = dayIndex * computedDayWidth + (column * columnWidth);

        widgets.add(
          DraggableEvent(
            key: ValueKey(event.id),
            event: event,
            initialTop: top,
            initialLeft: left,
            initialWidth: columnWidth,
            initialHeight: height,
            cellHourHeight: widget.hourHeight,
            dayWidth: computedDayWidth,
            weekStart: widget.weekStart,
            teamMembers: widget.teamMembers,
            onUpdate: widget.onEventDragOrResize,
            onTap: widget.onEventTap,
          ),
        );
      });
    });
    return widgets;
  }
}

class DraggableEvent extends StatefulWidget {
  final CalendarEvent event;
  final double initialTop;
  final double initialLeft;
  final double initialWidth;
  final double initialHeight;
  final double cellHourHeight;
  final double dayWidth;
  final DateTime weekStart;
  final List<Map<String, dynamic>>? teamMembers;
  final EventUpdateCallback? onUpdate;
  final EventTapCallback? onTap;

  const DraggableEvent({
    Key? key,
    required this.event,
    required this.initialTop,
    required this.initialLeft,
    required this.initialWidth,
    required this.initialHeight,
    required this.cellHourHeight,
    required this.dayWidth,
    required this.weekStart,
    this.teamMembers,
    this.onUpdate,
    this.onTap,
  }) : super(key: key);

  @override
  _DraggableEventState createState() => _DraggableEventState();
}

class _DraggableEventState extends State<DraggableEvent> {
  late double baseTop;
  late double baseLeft;
  Offset dragDelta = Offset.zero;

  double get currentTop => baseTop + dragDelta.dy;
  double get currentLeft => baseLeft + dragDelta.dx;

  late double width;
  late double height;

  @override
  void initState() {
    super.initState();
    baseTop = widget.initialTop;
    baseLeft = widget.initialLeft;
    width = widget.initialWidth;
    height = widget.initialHeight;
    dragDelta = Offset.zero;
  }

  @override
  void didUpdateWidget(covariant DraggableEvent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (dragDelta == Offset.zero) {
      baseTop = widget.initialTop;
      baseLeft = widget.initialLeft;
      width = widget.initialWidth;
      height = widget.initialHeight;
    }
  }

  double _snapToNearest(double value, double interval) {
    return (value / interval).round() * interval;
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      dragDelta = Offset.zero;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      dragDelta += details.delta;
      double maxLeft = 6 * widget.dayWidth;
      double newLeft = (baseLeft + dragDelta.dx).clamp(0, maxLeft);
      dragDelta = Offset(newLeft - baseLeft, dragDelta.dy);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    double newTop = baseTop + dragDelta.dy;
    double newLeft = baseLeft + dragDelta.dx;
    double snappedTop = _snapToNearest(newTop, widget.cellHourHeight / 4);
    double snappedLeft = _snapToNearest(newLeft, widget.dayWidth);

    int totalMinutes = ((snappedTop / widget.cellHourHeight) * 60).round();
    int newHour = totalMinutes ~/ 60;
    int newMinute = totalMinutes % 60;
    int newDayIndex = (snappedLeft / widget.dayWidth).round().clamp(0, 6);
    Duration eventDuration = widget.event.end.difference(widget.event.start);

    DateTime newStart = DateTime(
      widget.weekStart.year,
      widget.weekStart.month,
      widget.weekStart.day,
    ).add(Duration(days: newDayIndex, hours: newHour, minutes: newMinute));
    DateTime newEnd = newStart.add(eventDuration);

    setState(() {
      baseTop = snappedTop;
      baseLeft = snappedLeft;
      dragDelta = Offset.zero;
    });

    if (widget.onUpdate != null) {
      widget.onUpdate!(widget.event.copyWith(start: newStart, end: newEnd));
    }
  }

  void _editTask() async {
    if (widget.onTap != null) widget.onTap!(widget.event);
  }

  // Nouvelle fonction pour ajuster les couleurs avec réduction de saturation et luminosité
  Color _adjustColorForDarkMode(Color color, BuildContext context) {
    if (Theme.of(context).brightness == Brightness.dark) {
      HSLColor hslColor = HSLColor.fromColor(color);
      // Réduire la saturation à 50 % et la luminosité à 70 % en mode sombre
      HSLColor adjustedHSL = hslColor.withSaturation(0.5).withLightness(0.7);
      return adjustedHSL.toColor();
    }
    return color;
  }

  // Fonction pour déterminer la couleur de texte avec contraste
  Color _getContrastTextColor(Color backgroundColor) {
    double luminance = (0.299 * backgroundColor.red +
            0.587 * backgroundColor.green +
            0.114 * backgroundColor.blue) /
        255;
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    Color eventColor = widget.event.color ?? Theme.of(context).unselectedWidgetColor.withOpacity(0.7);
    Color adjustedColor = _adjustColorForDarkMode(eventColor, context);
    Color textColor = widget.event.color != null
        ? _getContrastTextColor(adjustedColor)
        : Theme.of(context).colorScheme.onPrimary;

    return Positioned(
      left: currentLeft.clamp(0, 6 * widget.dayWidth),
      top: currentTop,
      width: width.clamp(0, widget.dayWidth),
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTap: _editTask,
        child: Container(
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: adjustedColor,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withOpacity(0.3),
                offset: const Offset(1, 2),
                blurRadius: 3,
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  widget.event.summary,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium!
                      .copyWith(color: textColor, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat.Hm().format(widget.event.start)} - ${DateFormat.Hm().format(widget.event.end)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium!
                      .copyWith(color: textColor.withOpacity(0.7), fontSize: 10),
                ),
                if (widget.event.customText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.event.customText!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium!
                        .copyWith(
                            color: textColor.withOpacity(0.7),
                            fontSize: 10,
                            fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CalendarGridPainter extends CustomPainter {
  final double hourHeight;
  final double dayWidth;
  final BuildContext context;

  CalendarGridPainter({
    required this.hourHeight,
    required this.dayWidth,
    required this.context,
  });

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint,
      {double dashWidth = 4, double dashSpace = 2}) {
    final double totalDistance = (end - start).distance;
    final Offset direction = (end - start) / totalDistance;
    double distanceCovered = 0;
    while (distanceCovered < totalDistance) {
      final double currentDashWidth = dashWidth;
      final Offset dashStart = start + direction * distanceCovered;
      distanceCovered += currentDashWidth;
      final Offset dashEnd =
          start + direction * (distanceCovered.clamp(0, totalDistance));
      canvas.drawLine(dashStart, dashEnd, paint);
      distanceCovered += dashSpace;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fullHourPaint = Paint()
      ..color = Theme.of(context).textTheme.bodyMedium!.color!.withOpacity(0.6)
      ..strokeWidth = 1.5;
    final Paint subHourPaint = Paint()
      ..color = Theme.of(context).textTheme.bodyMedium!.color!.withOpacity(0.3)
      ..strokeWidth = 0.5;

    for (int i = 0; i <= 24; i++) {
      double y = i * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), fullHourPaint);
      if (i < 24) {
        for (int j = 1; j < 4; j++) {
          double subY = y + j * (hourHeight / 4);
          _drawDashedLine(canvas, Offset(0, subY), Offset(size.width, subY),
              subHourPaint,
              dashWidth: 4, dashSpace: 2);
        }
      }
    }
    final Paint verticalPaint = Paint()
      ..color = Theme.of(context).dividerColor
      ..strokeWidth = 1.0;
    for (int i = 0; i <= 7; i++) {
      double x = i * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), verticalPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MonthlyCalendar extends StatelessWidget {
  final DateTime currentMonth;
  final List<CalendarEvent> events;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final Function(DateTime day)? onDayTap;

  const MonthlyCalendar({
    Key? key,
    required this.currentMonth,
    required this.events,
    required this.onPrevMonth,
    required this.onNextMonth,
    this.onDayTap,
  }) : super(key: key);

  List<DateTime> _generateDaysForMonth(DateTime month) {
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    int weekday = firstDayOfMonth.weekday;
    DateTime gridStart = firstDayOfMonth.subtract(Duration(days: weekday - 1));
    return List.generate(42, (index) => gridStart.add(Duration(days: index)));
  }

  @override
  Widget build(BuildContext context) {
    List<DateTime> days = _generateDaysForMonth(currentMonth);
    return Column(
      children: [
        Container(
          color: Theme.of(context).appBarTheme.backgroundColor ??
              Theme.of(context).cardColor,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left,
                    size: 28, color: Theme.of(context).iconTheme.color),
                onPressed: onPrevMonth,
              ),
              Text(
                DateFormat.yMMMM().format(currentMonth),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    size: 28, color: Theme.of(context).iconTheme.color),
                onPressed: onNextMonth,
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            double totalWidth = constraints.maxWidth;
            double cellWidth = totalWidth / 7;
            double cellHeight = cellWidth / 1.2;
            return SizedBox(
              height: cellHeight * 6,
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: List.generate(6, (rowIndex) {
                  return TableRow(
                    children: List.generate(7, (colIndex) {
                      int index = rowIndex * 7 + colIndex;
                      DateTime day = days[index];
                      bool isCurrentMonth = day.month == currentMonth.month;
                      bool isToday = day.year == DateTime.now().year &&
                          day.month == DateTime.now().month &&
                          day.day == DateTime.now().day;
                      List<CalendarEvent> dayEvents = events.where((event) {
                        return event.start.day == day.day &&
                            event.start.month == day.month &&
                            event.start.year == day.year;
                      }).toList();
                      return GestureDetector(
                        onTap: () => onDayTap?.call(day),
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            border: Border.all(
                                color: Theme.of(context).dividerColor,
                                width: isToday ? 2 : 1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${day.day}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isCurrentMonth
                                      ? Theme.of(context).textTheme.bodyLarge!.color
                                      : Theme.of(context).textTheme.bodyMedium!.color,
                                ),
                              ),
                              if (dayEvents.isNotEmpty)
                                Wrap(
                                  spacing: 2,
                                  runSpacing: 2,
                                  children: List.generate(
                                    dayEvents.length > 3 ? 3 : dayEvents.length,
                                    (index) => Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: dayEvents[index].color ??
                                            Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            );
          },
        ),
      ],
    );
  }
}
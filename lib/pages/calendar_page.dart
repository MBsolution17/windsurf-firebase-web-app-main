// lib/pages/calendar_page.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart'; // Pour Firebase Storage
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:xml/xml.dart';
import 'package:http/http.dart' as http;

// Utilisez un alias pour éviter les conflits avec Task de Firebase Storage.
import '../models/task.dart' as taskModel;

/// Modèle représentant un événement de calendrier.
/// Chaque événement peut contenir (optionnellement) un ownerId indiquant à quel membre il appartient.
class CalendarEvent {
  final String id;
  final String summary;
  final String description;
  final DateTime start;
  final DateTime end;
  final String? ownerId;

  CalendarEvent({
    required this.id,
    required this.summary,
    required this.description,
    required this.start,
    required this.end,
    this.ownerId,
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
    );
  }

  CalendarEvent copyWith({DateTime? start, DateTime? end, String? ownerId}) {
    return CalendarEvent(
      id: id,
      summary: summary,
      description: description,
      start: start ?? this.start,
      end: end ?? this.end,
      ownerId: ownerId ?? this.ownerId,
    );
  }
}

/// Page principale affichant simultanément la vue mensuelle et la vue hebdomadaire.
/// Sous le calendrier mensuel, une liste horizontale affiche les membres du workspace.
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
  // Date de référence pour la vue mensuelle (mois affiché).
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // Hauteur d'une cellule horaire (1h) et largeur de la colonne des heures.
  final double _hourHeight = 100.0;
  final double _hoursColumnWidth = 40.0;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _fetchTeamMembers();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // Récupération des événements de la collection "calendar_events"
      QuerySnapshot calendarSnapshot = await _firestore
          .collection('workspaces')
          .doc(widget.workspaceId)
          .collection('calendar_events')
          .orderBy('start', descending: false)
          .get();
      List<CalendarEvent> calendarEvents = calendarSnapshot.docs
          .map((doc) => CalendarEvent.fromFirestore(doc))
          .toList();

      // Récupération des tâches de la collection "tasks" et conversion en événements
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
        return CalendarEvent(
          id: task.id,
          summary: task.title,
          description: task.description,
          start: start,
          end: end,
          ownerId: task.assignee,
        );
      }).toList();

      setState(() {
        _allEvents = [...calendarEvents, ...taskEvents];
      });
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

  /// Récupère la liste des membres de l'équipe depuis la sous-collection "users" du workspace.
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
            "name": data['name'] ?? 'Sans nom',
          };
        }).toList();
      });
    } catch (e) {
      debugPrint('Erreur lors de la récupération des membres: $e');
    }
  }

  /// Renvoie le lundi de la semaine pour une date donnée.
  static DateTime _getStartOfWeek(DateTime date) {
    int daysToSubtract = date.weekday - DateTime.monday;
    return DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: daysToSubtract));
  }

  /// Filtre les événements de la semaine en fonction du membre sélectionné (si un est sélectionné).
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

  /// Mise à jour optimiste d'un événement dans Firestore (ou dans la collection "tasks").
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          event.summary,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(event.description),
            const SizedBox(height: 8),
            Text(
              'De ${DateFormat.Hm().format(event.start)} à ${DateFormat.Hm().format(event.end)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  // Fonction appelée lors du tap sur le bouton "Créer"
  void _addTask() {
    debugPrint("Créer une tâche");
  }

  @override
  Widget build(BuildContext context) {
    double verticalOffset = MediaQuery.of(context).size.height * 0.05;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Calendrier",
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        iconTheme: const IconThemeData(color: Colors.black),
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
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 16),
                  ),
                )
              : Center(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Colonne pour le calendrier mensuel, le bouton "Créer" et la liste des membres.
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
                                  icon: const Icon(Icons.add, color: Colors.black),
                                  label: const Text("Créer"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    side: const BorderSide(color: Colors.black, width: 1),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 4,
                                    shadowColor: Colors.black.withOpacity(0.25),
                                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                                    textStyle: const TextStyle(fontSize: 16),
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
                              Container(
                                height: 80,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _teamMembers.length,
                                  itemBuilder: (context, index) {
                                    var member = _teamMembers[index];
                                    bool isSelected = member["id"] == _selectedTeamMemberId;
                                    return GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedTeamMemberId = member["id"];
                                        });
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 8),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isSelected ? Colors.black : Colors.grey.shade300,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Center(
                                          child: Text(
                                            member["name"],
                                            style: TextStyle(
                                              color: isSelected ? Colors.white : Colors.black,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Calendrier hebdomadaire.
                      Expanded(
                        flex: 85,
                        child: WeeklyCalendar(
                          weekStart: _currentWeekStart,
                          events: _getEventsForCurrentWeek(),
                          teamMembers: _teamMembers,
                          onEventTap: _showEventDetails,
                          hourHeight: _hourHeight,
                          hoursColumnWidth: _hoursColumnWidth,
                          onEventDragOrResize: (updatedEvent) {
                            _updateEvent(updatedEvent);
                          },
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
/// Callback pour notifier qu'un événement a été déplacé ou modifié.
typedef EventUpdateCallback = void Function(CalendarEvent updatedEvent);

/// Vue hebdomadaire du calendrier.
class WeeklyCalendar extends StatefulWidget {
  final DateTime weekStart; // Le lundi de la semaine.
  final List<CalendarEvent> events;
  final EventTapCallback? onEventTap;
  final EventUpdateCallback? onEventDragOrResize;
  final double hourHeight; // Hauteur d'une cellule horaire.
  final double hoursColumnWidth; // Largeur de la colonne des heures.
  final List<Map<String, dynamic>>? teamMembers; // Liste des membres pour l'assignation

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
            color: Colors.white,
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
                      color: Colors.white,
                      border: isToday
                          ? Border.all(color: Colors.black, width: 2)
                          : Border.all(color: Colors.grey.shade400, width: 1),
                      borderRadius: isToday ? BorderRadius.circular(20) : BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dayNumber,
                          style: const TextStyle(fontSize: 12, color: Colors.black),
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
                            child: Text(
                              '$index:00',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
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
    Map<int, Map<int, List<CalendarEvent>>> groups = {};

    for (var event in widget.events) {
      int dayIndex = event.start.weekday - 1;
      int hour = event.start.hour;
      groups.putIfAbsent(dayIndex, () => {});
      groups[dayIndex]!.putIfAbsent(hour, () => []).add(event);
    }

    List<Widget> widgets = [];
    groups.forEach((dayIndex, hourGroups) {
      hourGroups.forEach((hour, eventList) {
        eventList.sort((a, b) => a.start.minute.compareTo(b.start.minute));
        int count = eventList.length;
        for (int i = 0; i < count; i++) {
          var event = eventList[i];
          double top = (event.start.hour + event.start.minute / 60.0) * widget.hourHeight;
          double durationHours = event.end.difference(event.start).inMinutes / 60.0;
          double height = durationHours * widget.hourHeight;
          if (height < 20) height = 20;
          double eventWidth = computedDayWidth / count;
          double left = dayIndex * computedDayWidth + i * eventWidth;
          widgets.add(
            DraggableEvent(
              key: ValueKey(event.id),
              event: event,
              initialTop: top,
              initialLeft: left,
              initialWidth: eventWidth,
              initialHeight: height,
              cellHourHeight: widget.hourHeight,
              dayWidth: computedDayWidth,
              weekStart: widget.weekStart,
              teamMembers: widget.teamMembers,
              onUpdate: widget.onEventDragOrResize,
              onTap: widget.onEventTap,
            ),
          );
        }
      });
    });
    return widgets;
  }
}

/// Widget permettant de déplacer un événement et de modifier ses paramètres via dialogue.
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
  // On définit un "base offset" et un "drag delta"
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
    // Si aucun drag n'est en cours, met à jour le base offset
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

  // Utilisation des callbacks de pan pour permettre un drag continu
  void _onPanStart(DragStartDetails details) {
    setState(() {
      dragDelta = Offset.zero;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      dragDelta += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    // Calcul de la position finale = base + dragDelta
    double newTop = baseTop + dragDelta.dy;
    double newLeft = baseLeft + dragDelta.dx;
    double snappedTop = _snapToNearest(newTop, widget.cellHourHeight / 4);
    double snappedLeft = _snapToNearest(newLeft, widget.dayWidth);

    // Calcul de la nouvelle heure
    int totalMinutes = ((snappedTop / widget.cellHourHeight) * 60).round();
    int newHour = totalMinutes ~/ 60;
    int newMinute = totalMinutes % 60;
    // Calcul de l'index du jour
    int newDayIndex = (snappedLeft / widget.dayWidth).round();
    Duration eventDuration = widget.event.end.difference(widget.event.start);

    DateTime newStart = DateTime(
      widget.weekStart.year,
      widget.weekStart.month,
      widget.weekStart.day,
    ).add(Duration(days: newDayIndex, hours: newHour, minutes: newMinute));
    DateTime newEnd = newStart.add(eventDuration);

    // Mise à jour du base offset avec la position snapée, réinitialise dragDelta
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
    DateTime selectedStart = widget.event.start;
    int currentDuration = widget.event.end.difference(widget.event.start).inMinutes;
    int selectedDuration = currentDuration;
    String? selectedAssignee = widget.event.ownerId;

    const int minDuration = 15;
    int maxDuration = currentDuration > 240 ? currentDuration : 240;
    int divisions = ((maxDuration - minDuration) / 15).round();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Modifier la tâche", style: TextStyle(color: Colors.black)),
          content: StatefulBuilder(
            builder: (context, setStateSB) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text("Début : ", style: TextStyle(color: Colors.black)),
                      Text(DateFormat.Hm().format(selectedStart), style: const TextStyle(color: Colors.black)),
                      TextButton(
                        onPressed: () async {
                          TimeOfDay? picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(selectedStart),
                            builder: (context, child) {
                              return Theme(
                                data: ThemeData(
                                  colorScheme: ColorScheme.light(
                                    primary: Colors.black,
                                    onPrimary: Colors.white,
                                    surface: Colors.white,
                                    onSurface: Colors.black,
                                  ),
                                  timePickerTheme: const TimePickerThemeData(
                                    dialBackgroundColor: Colors.white,
                                    dialHandColor: Colors.black,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setStateSB(() {
                              selectedStart = DateTime(
                                selectedStart.year,
                                selectedStart.month,
                                selectedStart.day,
                                picked.hour,
                                picked.minute,
                              );
                            });
                          }
                        },
                        child: const Text("Modifier", style: TextStyle(color: Colors.black)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text("Durée : ", style: TextStyle(color: Colors.black)),
                      Text("$selectedDuration min", style: const TextStyle(color: Colors.black)),
                    ],
                  ),
                  Slider(
                    value: selectedDuration.toDouble(),
                    min: minDuration.toDouble(),
                    max: maxDuration.toDouble(),
                    divisions: divisions > 0 ? divisions : null,
                    label: "$selectedDuration minutes",
                    activeColor: Colors.black,
                    inactiveColor: Colors.grey.shade300,
                    onChanged: (value) {
                      setStateSB(() {
                        selectedDuration = value.round();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (widget.teamMembers != null && widget.teamMembers!.isNotEmpty)
                    Row(
                      children: [
                        const Text("Assigné : ", style: TextStyle(color: Colors.black)),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: selectedAssignee,
                          hint: const Text("Sélectionner", style: TextStyle(color: Colors.black)),
                          items: widget.teamMembers!
                              .map((member) => DropdownMenuItem<String>(
                                    value: member["id"],
                                    child: Text(member["name"], style: const TextStyle(color: Colors.black)),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setStateSB(() {
                              selectedAssignee = value;
                            });
                          },
                          dropdownColor: Colors.white,
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(context),
              child: const Text("Annuler"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.black),
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Valider"),
            ),
          ],
        );
      },
    );
    if (selectedDuration != currentDuration ||
        selectedStart != widget.event.start ||
        selectedAssignee != widget.event.ownerId) {
      DateTime newEnd = selectedStart.add(Duration(minutes: selectedDuration));
      if (widget.onUpdate != null) {
        widget.onUpdate!(widget.event.copyWith(start: selectedStart, end: newEnd, ownerId: selectedAssignee));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: currentLeft,
      top: currentTop,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTap: () {
          if (widget.onTap != null) widget.onTap!(widget.event);
        },
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.all(3),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat.Hm().format(widget.event.start)} - ${DateFormat.Hm().format(widget.event.end)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: _editTask,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white70,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.edit,
                    size: 14,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter pour dessiner la grille du calendrier (vue hebdomadaire).
class CalendarGridPainter extends CustomPainter {
  final double hourHeight;
  final double dayWidth;

  CalendarGridPainter({required this.hourHeight, required this.dayWidth});

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint,
      {double dashWidth = 4, double dashSpace = 2}) {
    final double totalDistance = (end - start).distance;
    final Offset direction = (end - start) / totalDistance;
    double distanceCovered = 0;
    while (distanceCovered < totalDistance) {
      final double currentDashWidth = dashWidth;
      final Offset dashStart = start + direction * distanceCovered;
      distanceCovered += currentDashWidth;
      final Offset dashEnd = start + direction * (distanceCovered.clamp(0, totalDistance));
      canvas.drawLine(dashStart, dashEnd, paint);
      distanceCovered += dashSpace;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fullHourPaint = Paint()
      ..color = Colors.grey.shade600.withOpacity(0.6)
      ..strokeWidth = 1.5;
    final Paint subHourPaint = Paint()
      ..color = Colors.grey.shade600.withOpacity(0.3)
      ..strokeWidth = 0.5;
      
    for (int i = 0; i <= 24; i++) {
      double y = i * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), fullHourPaint);
      if (i < 24) {
        for (int j = 1; j < 4; j++) {
          double subY = y + j * (hourHeight / 4);
          _drawDashedLine(canvas, Offset(0, subY), Offset(size.width, subY), subHourPaint,
              dashWidth: 4, dashSpace: 2);
        }
      }
    }
    final Paint verticalPaint = Paint()
      ..color = Colors.grey.shade600.withOpacity(0.6)
      ..strokeWidth = 1.0;
    for (int i = 0; i <= 7; i++) {
      double x = i * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), verticalPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Vue mensuelle du calendrier (affichée à gauche) réalisée avec un widget Table.
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
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 28, color: Colors.black),
                onPressed: onPrevMonth,
              ),
              Text(
                DateFormat.yMMMM().format(currentMonth),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 28, color: Colors.black),
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
                            color: Colors.white,
                            border: isToday
                                ? Border.all(color: Colors.black, width: 2)
                                : Border.all(color: Colors.grey.shade300),
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
                                  color: isCurrentMonth ? Colors.black : Colors.grey,
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
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black,
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

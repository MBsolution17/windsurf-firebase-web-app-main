// lib/pages/dashboard_page.dart

import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html; // Pour les opérations de téléchargement sur le web
import 'package:firebase_web_app/services/speech_recognition_js.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';
import '../models/folder.dart';
import '../models/contact.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/web_speech_recognition_service.dart';
import '../services/auth_service.dart';
import 'contact_page.dart';
import 'profile_page.dart';
import '../widgets/profile_avatar.dart';

class DashboardItem {
  final String title;
  final IconData icon;
  final String routeName;
  final Color color;

  DashboardItem({
    required this.title,
    required this.icon,
    required this.routeName,
    required this.color,
  });
}

class DashboardPage extends StatefulWidget {
  final String workspaceId;

  const DashboardPage({
    Key? key,
    required this.workspaceId,
  }) : super(key: key);

  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  AIService? _aiService;
  WebSpeechRecognitionService? _speechService;

  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  bool _isListening = false;

  late AnimationController _animationController;
  late Animation<double> _animation;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _externalInfoController = TextEditingController();

  String? _selectedFolderId;
  List<Contact> _availableContacts = [];

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Task>> _tasksByDate = {};

  String _aiResponse = '';
  String _lastError = '';

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isTtsEnabled = false;

  List<html.SpeechSynthesisVoice> _availableVoices = [];
  html.SpeechSynthesisVoice? _selectedVoice;
  String _selectedVoiceName = 'fr-FR-Wavenet-D';
  double _selectedSpeakingRate = 1.0;
  double _selectedPitch = 1.0;

  static const String prefSelectedVoiceName = 'selectedVoiceName';
  static const String prefSelectedVoiceId = 'selectedVoiceId';

  // Couleur principale et neutre (charte gris foncé)
  final Color primaryColor = Colors.grey[800]!;
  final Color neutralDark = Colors.grey[800]!;

  final List<DashboardItem> dashboardItems = [
    DashboardItem(
      title: 'Channels',
      icon: Icons.chat,
      routeName: '/channel_list',
      color: Colors.grey[600]!,
    ),
    DashboardItem(
      title: 'Friends',
      icon: Icons.people,
      routeName: '/friends',
      color: Colors.grey[600]!,
    ),
    DashboardItem(
      title: 'Calendar',
      icon: Icons.calendar_today,
      routeName: '/calendar',
      color: Colors.grey[600]!,
    ),
    DashboardItem(
      title: 'Task Tracker',
      icon: Icons.check_circle,
      routeName: '/task_tracker',
      color: Colors.grey[600]!,
    ),
    DashboardItem(
      title: 'Documents',
      icon: Icons.folder,
      routeName: '/documents',
      color: Colors.grey[600]!,
    ),
    DashboardItem(
      title: 'Analytics',
      icon: Icons.analytics,
      routeName: '/analytics',
      color: Colors.grey[600]!,
    ),
    DashboardItem(
      title: 'Contacts',
      icon: Icons.contact_mail,
      routeName: '/contact_page',
      color: Colors.grey[600]!,
    ),
  ];

  // Utilisation de '/documents' pour les actions relatives aux documents
  final Map<String, String> actionRouteMap = {
  'create_task': '/calendar', // Mise à jour ici
  'add_contact': '/contact_page',
  'create_folder_with_document': '/documents',
  'create_folder_and_add_contact': '/documents',
  'modify_document': '/documents',
};

  late String workspaceId;

  List<UserModel> _connectedUsers = [];

  @override
  void initState() {
    super.initState();
    workspaceId = widget.workspaceId;
    _selectedDay = DateTime.now();
    _focusedDay = DateTime.now();
    _calendarFormat = CalendarFormat.month;

    // Actualisation en temps réel des tâches
    _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('tasks')
        .snapshots()
        .listen((snapshot) {
      final Map<DateTime, List<Task>> tasksMap = {};
      for (var doc in snapshot.docs) {
        Task task = Task.fromFirestore(doc);
        DateTime date = DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day);
        tasksMap[date] = (tasksMap[date] ?? [])..add(task);
      }
      if (mounted) {
        setState(() {
          _tasksByDate = tasksMap;
        });
      }
    });

    _fetchAllFolders();
    _fetchAvailableContacts();
    _fetchConnectedUsers();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _animation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _aiService = Provider.of<AIService>(context, listen: false);
      _speechService =
          Provider.of<WebSpeechRecognitionService>(context, listen: false);

      if (_speechService != null) {
        bool available = await _speechService!.initialize();
        if (!available && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('La reconnaissance vocale n\'est pas disponible.')),
          );
        }
      }

      if (kIsWeb) {
        final synth = html.window.speechSynthesis;
        synth?.addEventListener('voiceschanged', (event) {
          if (!mounted) return;
          setState(() {
            _availableVoices = synth!
                .getVoices()
                .where((voice) => voice.lang?.startsWith('fr-FR') ?? false)
                .toList();
          });
          _loadSavedVoice();
        });
        if (synth != null) {
          setState(() {
            _availableVoices = synth
                .getVoices()
                .where((voice) => voice.lang?.startsWith('fr-FR') ?? false)
                .toList();
          });
        }
        _loadSavedVoice();
      } else {
        _loadSavedVoice();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_speechService != null) {
        _speechService!.onResult = (transcript) async {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _lastError = '';
            _aiResponse = 'En attente de la réponse de l\'IA...';
          });
          try {
            if (_aiService == null) return;
            ChatMessage aiMessage = await _aiService!.sendMessage(transcript);
            String responseContent = aiMessage.content;
            if (!mounted) return;
            setState(() {
              _aiResponse = responseContent;
            });
            if (_isTtsEnabled) {
              await _speak(responseContent);
            }
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _aiResponse = 'Erreur lors de la communication avec l\'IA.';
            });
          }
        };

        _speechService!.onError = (error) {
          if (!mounted) return;
          setState(() {
            _lastError = error;
            _isListening = false;
            _aiResponse = '';
          });
        };
      }
    });

    _chatFocusNode.addListener(() {
      if (!_chatFocusNode.hasFocus && _isListening) {
        _toggleAssistantListening();
      }
    });

    _listenToValidatedMessages();
  }

  @override
  void dispose() {
    _stopSpeaking();
    _audioPlayer.dispose();
    _animationController.dispose();
    _chatController.dispose();
    _chatFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _fetchAllFolders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('folders')
        .get();
  }

  void _fetchAvailableContacts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    QuerySnapshot snapshot = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('contacts')
        .get();
    final contacts = snapshot.docs.map((doc) => Contact.fromFirestore(doc)).toList();
    setState(() {
      _availableContacts = contacts;
    });
  }

  void _fetchConnectedUsers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('users')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _connectedUsers =
            snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList();
      });
    });
  }

  void _listenToValidatedMessages() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('chat_messages')
        .where('status', isEqualTo: 'validated')
        .where('executed', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        ChatMessage message = ChatMessage.fromFirestore(doc);
        _executeActionsFromMessage(message);
        doc.reference.update({'executed': true});
      }
    });
  }

  void _executeActionsFromMessage(ChatMessage message) {
    if (!isJson(message.content)) return;
    final dynamic data = jsonDecode(message.content);
    List<Map<String, dynamic>> actions = [];
    if (data is List) {
      actions = data.map((e) => e as Map<String, dynamic>).toList();
    } else if (data is Map<String, dynamic>) {
      actions = [data];
    }
    for (var actionData in actions) {
      _executeAction(actionData);
    }
  }

  void _executeAction(Map<String, dynamic> actionData) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String action = actionData['action'] ?? '';
    Map<String, dynamic> data = actionData['data'] ?? {};
    switch (action) {
      case 'create_folder_and_add_contact':
        _createFolderAndAddContact(data);
        break;
      case 'create_task':
        _createTask(data);
        break;
      case 'add_contact':
        _addContact(data);
        break;
      default:
        break;
    }
  }

  Future<void> _createTask(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String title = data['title'] ?? '';
    String description = data['description'] ?? '';
    String dueDateStr = data['dueDate'] ?? '';
    String priority = data['priority'] ?? 'Medium';
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(dueDateStr);
    } catch (_) {
      parsedDate = DateTime.now().add(const Duration(days: 1));
    }
    await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('tasks')
        .add({
      'title': title,
      'description': description,
      'dueDate': parsedDate,
      'priority': priority,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'Pending',
    });
  }

  Future<void> _addContact(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String firstName = data['firstName'] ?? '';
    String lastName = data['lastName'] ?? '';
    String email = data['email'] ?? '';
    String phone = data['phone'] ?? '';
    String address = data['address'] ?? '';
    String company = data['company'] ?? '';
    String externalInfo = data['externalInfo'] ?? '';
    await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('contacts')
        .add({
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'address': address,
      'company': company,
      'externalInfo': externalInfo,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _createFolderAndAddContact(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String folderName = data['folderName'] ?? '';
    Map<String, dynamic> contactData = data['contact'] ?? {};
    final folderRef = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('folders')
        .add({
      'folderName': folderName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    String firstName = contactData['firstName'] ?? '';
    String lastName = contactData['lastName'] ?? '';
    String email = contactData['email'] ?? '';
    String phone = contactData['phone'] ?? '';
    String address = contactData['address'] ?? '';
    String company = contactData['company'] ?? '';
    String externalInfo = contactData['externalInfo'] ?? '';
    await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('contacts')
        .add({
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'address': address,
      'company': company,
      'externalInfo': externalInfo,
      'folderId': folderRef.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _loadSavedVoice() async {
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb) {
      String? savedVoiceName = prefs.getString(prefSelectedVoiceName);
      if (savedVoiceName != null && _availableVoices.isNotEmpty) {
        final voice = _availableVoices.firstWhere(
          (v) => v.name == savedVoiceName,
          orElse: () => _availableVoices.first,
        );
        if (mounted) {
          setState(() {
            _selectedVoice = voice;
          });
        }
      } else if (_availableVoices.isNotEmpty) {
        if (mounted) {
          setState(() {
            _selectedVoice = _availableVoices.first;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _selectedVoice = null;
          });
        }
      }
    } else {
      String? savedVoiceName = prefs.getString(prefSelectedVoiceName);
      if (savedVoiceName != null && mounted) {
        setState(() {
          _selectedVoiceName = savedVoiceName;
        });
      }
    }
  }

  void _saveVoiceSelection() async {
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb) {
      if (_selectedVoice != null) {
        await prefs.setString(prefSelectedVoiceName, _selectedVoice!.name!);
      }
    } else {
      await prefs.setString(prefSelectedVoiceName, _selectedVoiceName);
    }
  }

  Future<void> _speak(String text) async {
    if (!_isTtsEnabled) return;
    String textToSpeak = isJson(text) ? jsonToSentence(text) : text;
    if (kIsWeb) {
      _speakWeb(textToSpeak);
    } else {
      try {
        HttpsCallable callable =
            FirebaseFunctions.instance.httpsCallable('synthesizeSpeech');
        final results = await callable.call(<String, dynamic>{
          'text': textToSpeak,
          'languageCode': 'fr-FR',
          'voiceName': _selectedVoiceName,
          'speakingRate': _selectedSpeakingRate,
        });
        String audioBase64 = results.data['audioContent'];
        Uint8List audioBytes = base64Decode(audioBase64);
        await _audioPlayer.play(BytesSource(audioBytes));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur lors de la synthèse vocale.')),
          );
        }
      }
    }
  }

  void _speakWeb(String text) {
    final synth = html.window.speechSynthesis;
    if (synth?.speaking ?? false) {
      synth?.cancel();
    }
    final utterance = html.SpeechSynthesisUtterance(text)
      ..lang = 'fr-FR'
      ..rate = _selectedSpeakingRate
      ..pitch = _selectedPitch
      ..voice = _selectedVoice;
    synth?.speak(utterance);
  }

  Future<void> _stopSpeaking() async {
    if (kIsWeb) {
      html.window.speechSynthesis?.cancel();
    } else {
      await _audioPlayer.stop();
    }
  }

  void _openVoiceSettings() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Paramètres de Voix'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (kIsWeb) ...[
                  DropdownButton<html.SpeechSynthesisVoice>(
                    value: _selectedVoice,
                    hint: const Text('Sélectionnez une voix'),
                    isExpanded: true,
                    items: _availableVoices.map((voice) {
                      return DropdownMenuItem<html.SpeechSynthesisVoice>(
                        value: voice,
                        child: Text(voice.name ?? 'Voix inconnue'),
                      );
                    }).toList(),
                    onChanged: (voice) {
                      if (!mounted) return;
                      setState(() {
                        _selectedVoice = voice;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                ] else ...[
                  DropdownButtonFormField<String>(
                    value: _selectedVoiceName.isNotEmpty ? _selectedVoiceName : null,
                    decoration: const InputDecoration(
                      labelText: 'Sélectionnez une voix',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'fr-FR-Wavenet-D',
                        child: Text('Voix A'),
                      ),
                      DropdownMenuItem(
                        value: 'fr-FR-Wavenet-B',
                        child: Text('Voix B'),
                      ),
                    ],
                    onChanged: (value) {
                      if (!mounted) return;
                      setState(() {
                        _selectedVoiceName = value ?? '';
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                ],
                Row(
                  children: [
                    const Text('Vitesse:'),
                    Expanded(
                      child: Slider(
                        value: _selectedSpeakingRate,
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        label: _selectedSpeakingRate.toStringAsFixed(1),
                        onChanged: (value) {
                          if (!mounted) return;
                          setState(() {
                            _selectedSpeakingRate = value;
                          });
                        },
                      ),
                    ),
                    Text('${_selectedSpeakingRate.toStringAsFixed(1)}x'),
                  ],
                ),
                const SizedBox(height: 20),
                if (kIsWeb) ...[
                  Row(
                    children: [
                      const Text('Hauteur (Pitch):'),
                      Expanded(
                        child: Slider(
                          value: _selectedPitch,
                          min: 0.5,
                          max: 2.0,
                          divisions: 15,
                          label: _selectedPitch.toStringAsFixed(1),
                          onChanged: (value) {
                            if (!mounted) return;
                            setState(() {
                              _selectedPitch = value;
                            });
                          },
                        ),
                      ),
                      Text(_selectedPitch.toStringAsFixed(1)),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                ElevatedButton(
                  onPressed: () async {
                    const sampleText = 'Bonjour, ceci est un exemple de voix.';
                    await _speak(sampleText);
                  },
                  child: const Text('Écouter un exemple'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
            ElevatedButton(
              onPressed: () {
                _saveVoiceSelection();
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Paramètres de voix mis à jour')),
                );
              },
              child: const Text('Appliquer'),
            ),
          ],
        );
      },
    );
  }

  void _toggleAssistantListening() {
    if (_speechService == null) return;
    if (_isListening) {
      _speechService!.stopListening();
      _animationController.stop();
      _animationController.reset();
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    } else {
      _speechService!.startListening();
      _animationController.repeat(reverse: true);
      if (mounted) {
        setState(() {
          _isListening = true;
        });
      }
    }
  }

  Future<void> _sendMessage(String message) async {
    if (_aiService == null) return;
    try {
      ChatMessage aiMessage = await _aiService!.sendMessage(message);
      String aiResponse = aiMessage.content;
      if (!mounted) return;
      setState(() {
        _chatController.clear();
        _aiResponse = aiResponse;
      });
      if (_isTtsEnabled) {
        await _speak(aiResponse);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'envoi du message: $e')),
      );
    }
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.Pending:
        return Colors.orange;
      case TaskStatus.InProgress:
        return Colors.blue;
      case TaskStatus.Done:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _showTaskDetailsDialog(Task task) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(task.title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Description: ${task.description}'),
                const SizedBox(height: 6),
                Text('Date d\'échéance: ${DateFormat('dd/MM/yyyy').format(task.dueDate)}'),
                const SizedBox(height: 6),
                Text('Priorité: ${task.priority.toString().split('.').last}'),
                const SizedBox(height: 6),
                Text('Statut: ${task.status.toString().split('.').last}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Fermer'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUpcomingTasksSection() {
    List<Task> upcomingTasks = _tasksByDate.values
        .expand((tasks) => tasks)
        .where((task) =>
            task.dueDate.isAfter(DateTime.now()) &&
            task.status != TaskStatus.Done)
        .toList();
    upcomingTasks.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    upcomingTasks = upcomingTasks.take(20).toList();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      color: Colors.white,
      child: Container(
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tâches à Venir',
                    style: GoogleFonts.roboto(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                 TextButton(
  onPressed: () {
    Navigator.pushNamed(context, '/calendar',
        arguments: {'workspaceId': workspaceId});
  },
  style: TextButton.styleFrom(
    foregroundColor: Colors.grey[700],
  ),
  child: const Text('Voir Tout'),
),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: upcomingTasks.length,
                  itemBuilder: (context, index) {
                    final task = upcomingTasks[index];
                    return Card(
                      color: const Color.fromARGB(255, 210, 210, 210),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              style: GoogleFonts.roboto(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[900],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              task.description,
                              style: GoogleFonts.roboto(
                                fontSize: 12,
                                color: Colors.grey[800],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'À faire le ${DateFormat('dd/MM/yyyy').format(task.dueDate)}',
                                  style: GoogleFonts.roboto(
                                    fontSize: 12,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(task.status),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    task.status.toString().split('.').last,
                                    style: GoogleFonts.roboto(
                                      color: Colors.grey[900],
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: ElevatedButton(
                                onPressed: () => _showTaskDetailsDialog(task),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(60, 25),
                                  backgroundColor: Colors.grey[800],
                                  foregroundColor: Colors.white,
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                                child: const Text('Détails'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool isJson(String text) {
    try {
      final decoded = jsonDecode(text);
      return (decoded is Map<String, dynamic> || decoded is List<dynamic>);
    } catch (_) {
      return false;
    }
  }

  String jsonToSentence(String jsonString) {
    try {
      final dynamic data = jsonDecode(jsonString);
      if (data is List) {
        return data
            .map((element) => element is Map<String, dynamic>
                ? _convertSingleActionToSentence(element)
                : 'Action invalide.')
            .join(' ');
      } else if (data is Map<String, dynamic>) {
        return _convertSingleActionToSentence(data);
      } else {
        return 'Contenu JSON invalide.';
      }
    } catch (_) {
      return 'Contenu JSON invalide.';
    }
  }

  String _convertSingleActionToSentence(Map<String, dynamic> jsonData) {
    final String action = jsonData['action'] ?? 'Unknown Action';
    final Map<String, dynamic> data = jsonData['data'] ?? {};
    switch (action) {
      case 'create_task':
        String title = data['title'] ?? 'Sans Titre';
        String description = data['description'] ?? 'Aucune Description';
        String dueDate = data['dueDate'] ?? 'Date non spécifiée';
        String priority = data['priority'] ?? 'Moyenne';
        DateTime? parsedDate;
        try {
          parsedDate = DateTime.parse(dueDate);
        } catch (_) {}
        String dateFormatee = parsedDate != null
            ? DateFormat('dd/MM/yyyy').format(parsedDate)
            : dueDate;
        return 'Nouvelle tâche: "$title" (priorité $priority), "$description", à faire le $dateFormatee.';
      case 'add_contact':
        String firstName = data['firstName'] ?? '';
        String lastName = data['lastName'] ?? '';
        String phone = data['phone'] ?? '';
        return 'Nouveau contact: $firstName $lastName (tél: $phone).';
      case 'create_folder_with_document':
        String folderName = data['folderName'] ?? 'Sans Nom';
        String docTitle = data['document']?['title'] ?? 'Sans Titre';
        return 'Dossier "$folderName" créé avec le document "$docTitle".';
      case 'create_folder_and_add_contact':
        final folderName = data['folderName'] ?? 'Sans Nom';
        final contactData = data['contact'] ?? {};
        String cFirst = contactData['firstName'] ?? '';
        String cLast = contactData['lastName'] ?? '';
        String cPhone = contactData['phone'] ?? '';
        return 'Dossier "$folderName" créé, contact: $cFirst $cLast (tél: $cPhone).';
      case 'modify_document':
        final folderName2 = data['folderName'] ?? 'Sans Nom';
        final docName = data['documentName'] ?? 'Document';
        return 'Modification du document "$docName" dans le dossier "$folderName2".';
      default:
        return 'Action inconnue : $action.';
    }
  }

  Widget buildSentenceResponseUI(String jsonString) {
    String sentence = jsonToSentence(jsonString);
    try {
      final dynamic data = jsonDecode(jsonString);
      List<Map<String, dynamic>> actions = [];
      if (data is List) {
        actions = data.whereType<Map<String, dynamic>>().toList();
      } else if (data is Map<String, dynamic>) {
        actions = [data];
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: actions.map((actionData) {
          final action = actionData['action'] ?? '';
          final routeName = actionRouteMap[action] ?? '';
          final actionSentence = _convertSingleActionToSentence(actionData);
          if (routeName.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  actionSentence,
                  style: GoogleFonts.roboto(
                    color: Colors.black87,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, routeName,
                        arguments: {'workspaceId': workspaceId});
                  },
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text(
                    'Accéder',
                    style: GoogleFonts.roboto(fontSize: 14, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 104, 104, 104),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          } else {
            return SelectableText(
              actionSentence,
              style: GoogleFonts.roboto(
                color: Colors.black87,
                fontSize: 14,
              ),
            );
          }
        }).toList(),
      );
    } catch (_) {
      return SelectableText(
        'Impossible de parser le JSON : $sentence',
        style: GoogleFonts.roboto(
          color: Colors.red,
          fontSize: 14,
        ),
      );
    }
  }

  Widget _buildChatAssistantSection() {
    if (_aiService == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assistant IA',
              style: GoogleFonts.roboto(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: neutralDark,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _aiService!.getChatHistory(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Erreur: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Text(
                        'Aucun message trouvé.',
                        style: GoogleFonts.roboto(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    );
                  }
                  final chat_messages = snapshot.data!;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        _scrollController.position.minScrollExtent,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  });
                  return ListView.builder(
                    reverse: true,
                    controller: _scrollController,
                    itemCount: chat_messages.length,
                    itemBuilder: (context, index) {
                      final message = chat_messages[index];
                      bool isUser = message.type == MessageType.user;
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.blue[200] : Colors.grey[300],
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Column(
                            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              // Si le message n'est pas de l'utilisateur et est au format JSON, on affiche la réponse formatée
                              if (!isUser && isJson(message.content))
                                buildSentenceResponseUI(message.content)
                              else
                                SelectableText(
                                  message.content,
                                  style: GoogleFonts.roboto(
                                    color: Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              // N'affichez pas le statut si c'est "pending_validation" ou "validated"
                              if (!(message.status == MessageStatus.pending_validation ||
                                  message.status == MessageStatus.validated))
                                Text(
                                  'Statut: ${message.status.toString().split('.').last}',
                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                              // Affichage des boutons uniquement si le message est de type IA, en pending_validation et le contenu est au format JSON
                              if (message.type == MessageType.ai &&
                                  message.status == MessageStatus.pending_validation &&
                                  isJson(message.content))
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    ElevatedButton(
                                      onPressed: () {
                                        _aiService!.handleValidation(
                                          message.id,
                                          MessageStatus.validated,
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(100, 40),
                                        backgroundColor: Colors.grey[300],
                                        foregroundColor: Colors.black54,
                                        textStyle: const TextStyle(fontSize: 16),
                                      ),
                                      child: const Text('Valider'),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () {
                                        _showEditMessageDialog(message, isAIMessage: true);
                                      },
                                      icon: const Icon(Icons.edit, size: 16, color: Colors.black54),
                                      label: const Text(
                                        'Modifier',
                                        style: TextStyle(fontSize: 12, color: Colors.black54),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    focusNode: _chatFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Posez votre question...',
                      filled: true,
                      fillColor: Colors.grey[200],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Colors.grey[400]!),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
                    ),
                    style: const TextStyle(color: Colors.black87),
                    onSubmitted: (value) async {
                      if (value.isNotEmpty) {
                        await _sendMessage(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _toggleAssistantListening,
                  child: ScaleTransition(
                    scale: _animation,
                    child: CircleAvatar(
                      backgroundColor: _isListening ? Colors.redAccent : Colors.grey[400],
                      child: Icon(
                        _isListening ? Icons.mic_off : Icons.mic,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _isTtsEnabled ? Icons.headset : Icons.headset_off,
                    color: _isTtsEnabled ? Colors.blueAccent : Colors.grey,
                  ),
                  tooltip: _isTtsEnabled ? 'Désactiver la lecture vocale' : 'Activer la lecture vocale',
                  onPressed: () {
                    if (!mounted) return;
                    setState(() {
                      _isTtsEnabled = !_isTtsEnabled;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_isTtsEnabled ? 'Lecture vocale activée' : 'Lecture vocale désactivée'),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.settings_voice, color: Colors.blueGrey[800]),
                  tooltip: 'Paramètres de Voix',
                  onPressed: _openVoiceSettings,
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.grey[400],
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: () async {
                      if (_chatController.text.isNotEmpty) {
                        await _sendMessage(_chatController.text);
                        _chatController.clear();
                      }
                    },
                  ),
                ),
              ],
            ),
            if (_lastError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Erreur : $_lastError',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showEditMessageDialog(ChatMessage message, {bool isAIMessage = false}) {
    if (!isJson(message.content)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le contenu du message n\'est pas un JSON valide.')),
      );
      return;
    }
    dynamic raw;
    try {
      raw = jsonDecode(message.content);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de parser le JSON.')),
      );
      return;
    }
    List<Map<String, dynamic>> items;
    if (raw is List) {
      items = raw.cast<Map<String, dynamic>>();
    } else if (raw is Map<String, dynamic>) {
      items = [raw];
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Structure JSON inattendue.')),
      );
      return;
    }
    final List<Map<String, TextEditingController>> controllersList = [];
    for (int i = 0; i < items.length; i++) {
      final action = items[i]['action'] ?? '';
      final data = items[i]['data'] ?? <String, dynamic>{};
      final Map<String, TextEditingController> ctrlMap = {};
      switch (action) {
        case 'create_task':
          ctrlMap['title'] = TextEditingController(text: data['title'] ?? '');
          ctrlMap['description'] = TextEditingController(text: data['description'] ?? '');
          ctrlMap['dueDate'] = TextEditingController(text: data['dueDate'] ?? '');
          ctrlMap['priority'] = TextEditingController(text: data['priority'] ?? 'Low');
          break;
        case 'create_folder_with_document':
          ctrlMap['folderName'] = TextEditingController(text: data['folderName'] ?? '');
          final doc = data['document'] ?? {};
          ctrlMap['docTitle'] = TextEditingController(text: doc['title'] ?? '');
          ctrlMap['docContent'] = TextEditingController(text: doc['content'] ?? '');
          break;
        case 'add_contact':
          ctrlMap['firstName'] = TextEditingController(text: data['firstName'] ?? '');
          ctrlMap['lastName'] = TextEditingController(text: data['lastName'] ?? '');
          ctrlMap['email'] = TextEditingController(text: data['email'] ?? '');
          ctrlMap['phone'] = TextEditingController(text: data['phone'] ?? '');
          ctrlMap['address'] = TextEditingController(text: data['address'] ?? '');
          ctrlMap['company'] = TextEditingController(text: data['company'] ?? '');
          ctrlMap['externalInfo'] = TextEditingController(text: data['externalInfo'] ?? '');
          break;
        case 'create_folder_and_add_contact':
          ctrlMap['folderName'] = TextEditingController(text: data['folderName'] ?? '');
          final contact = data['contact'] ?? {};
          ctrlMap['firstName'] = TextEditingController(text: contact['firstName'] ?? '');
          ctrlMap['lastName'] = TextEditingController(text: contact['lastName'] ?? '');
          ctrlMap['email'] = TextEditingController(text: contact['email'] ?? '');
          ctrlMap['phone'] = TextEditingController(text: contact['phone'] ?? '');
          ctrlMap['address'] = TextEditingController(text: contact['address'] ?? '');
          ctrlMap['company'] = TextEditingController(text: contact['company'] ?? '');
          ctrlMap['externalInfo'] = TextEditingController(text: contact['externalInfo'] ?? '');
          break;
        case 'modify_document':
          ctrlMap['folderName'] = TextEditingController(text: data['folderName'] ?? '');
          ctrlMap['documentName'] = TextEditingController(text: data['documentName'] ?? '');
          break;
      }
      controllersList.add(ctrlMap);
    }
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState2) {
            return AlertDialog(
              title: const Text('Modifier le message'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      _buildActionEditor(
                        items: items,
                        index: i,
                        controllersMap: controllersList[i],
                        onFieldChanged: () {
                          setState2(() {});
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Annuler'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: const Text('Valider'),
                  onPressed: () async {
                    for (int i = 0; i < items.length; i++) {
                      final action = items[i]['action'] ?? '';
                      final data = items[i]['data'] ?? <String, dynamic>{};
                      final ctrlMap = controllersList[i];
                      switch (action) {
                        case 'create_task':
                          data['title'] = ctrlMap['title']?.text ?? '';
                          data['description'] = ctrlMap['description']?.text ?? '';
                          data['dueDate'] = ctrlMap['dueDate']?.text ?? '';
                          data['priority'] = ctrlMap['priority']?.text ?? 'Low';
                          break;
                        case 'create_folder_with_document':
                          data['folderName'] = ctrlMap['folderName']?.text ?? '';
                          final doc = data['document'] ?? {};
                          doc['title'] = ctrlMap['docTitle']?.text ?? '';
                          doc['content'] = ctrlMap['docContent']?.text ?? '';
                          data['document'] = doc;
                          break;
                        case 'add_contact':
                          data['firstName'] = ctrlMap['firstName']?.text ?? '';
                          data['lastName'] = ctrlMap['lastName']?.text ?? '';
                          data['email'] = ctrlMap['email']?.text ?? '';
                          data['phone'] = ctrlMap['phone']?.text ?? '';
                          data['address'] = ctrlMap['address']?.text ?? '';
                          data['company'] = ctrlMap['company']?.text ?? '';
                          data['externalInfo'] = ctrlMap['externalInfo']?.text ?? '';
                          break;
                        case 'create_folder_and_add_contact':
                          data['folderName'] = ctrlMap['folderName']?.text ?? '';
                          final contact = data['contact'] ?? {};
                          contact['firstName'] = ctrlMap['firstName']?.text ?? '';
                          contact['lastName'] = ctrlMap['lastName']?.text ?? '';
                          contact['email'] = ctrlMap['email']?.text ?? '';
                          contact['phone'] = ctrlMap['phone']?.text ?? '';
                          contact['address'] = ctrlMap['address']?.text ?? '';
                          contact['company'] = ctrlMap['company']?.text ?? '';
                          contact['externalInfo'] = ctrlMap['externalInfo']?.text ?? '';
                          data['contact'] = contact;
                          break;
                        case 'modify_document':
                          data['folderName'] = ctrlMap['folderName']?.text ?? '';
                          data['documentName'] = ctrlMap['documentName']?.text ?? '';
                          break;
                      }
                      items[i]['data'] = data;
                    }
                    String updatedContent;
                    if (items.length == 1) {
                      updatedContent = jsonEncode(items.first);
                    } else {
                      updatedContent = jsonEncode(items);
                    }
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;
                    try {
                      await _firestore
                          .collection('workspaces')
                          .doc(workspaceId)
                          .collection('chat_messages')
                          .doc(message.id)
                          .update({
                        'content': updatedContent,
                        'status': 'pending_validation',
                        'executed': false,
                      });
                      await _firestore
                          .collection('workspaces')
                          .doc(workspaceId)
                          .collection('chat_messages')
                          .doc(message.id)
                          .update({
                        'status': 'validated',
                        'executed': false,
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Message mis à jour avec succès.')),
                        );
                      }
                      Navigator.of(context).pop();
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Erreur lors de la mise à jour.')),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildActionEditor({
    required List<Map<String, dynamic>> items,
    required int index,
    required Map<String, TextEditingController> controllersMap,
    required VoidCallback onFieldChanged,
  }) {
    final jsonContent = items[index];
    final String action = jsonContent['action'] ?? '';
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text('Action n°${index + 1} : $action'),
      children: [
        const SizedBox(height: 8),
        ..._buildEditableFields(jsonContent, controllersMap, onFieldChanged),
        const SizedBox(height: 16),
      ],
    );
  }

  List<Widget> _buildEditableFields(
      Map<String, dynamic> jsonContent,
      Map<String, TextEditingController> ctrlMap,
      VoidCallback onFieldChanged) {
    final String action = jsonContent['action'] ?? '';
    switch (action) {
      case 'create_task':
        return [
          TextFormField(
            controller: ctrlMap['title'],
            decoration: const InputDecoration(
              labelText: 'Titre de la tâche',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['description'],
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['dueDate'],
            decoration: const InputDecoration(
              labelText: 'Date (YYYY-MM-DDTHH:MM:SSZ)',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['priority'],
            decoration: const InputDecoration(
              labelText: 'Priorité (Low, Medium, High)',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
        ];
      case 'create_folder_with_document':
        return [
          TextFormField(
            controller: ctrlMap['folderName'],
            decoration: const InputDecoration(
              labelText: 'Nom du Dossier',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['docTitle'],
            decoration: const InputDecoration(
              labelText: 'Titre du Document',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['docContent'],
            decoration: const InputDecoration(
              labelText: 'Contenu du Document',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            onChanged: (value) => onFieldChanged(),
          ),
        ];
      case 'add_contact':
        return [
          TextFormField(
            controller: ctrlMap['firstName'],
            decoration: const InputDecoration(
              labelText: 'Prénom',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['lastName'],
            decoration: const InputDecoration(
              labelText: 'Nom',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['email'],
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['phone'],
            decoration: const InputDecoration(
              labelText: 'Téléphone',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['address'],
            decoration: const InputDecoration(
              labelText: 'Adresse',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['company'],
            decoration: const InputDecoration(
              labelText: 'Entreprise',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['externalInfo'],
            decoration: const InputDecoration(
              labelText: 'Informations Externes',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
        ];
      case 'create_folder_and_add_contact':
        return [
          TextFormField(
            controller: ctrlMap['folderName'],
            decoration: const InputDecoration(
              labelText: 'Nom du Dossier',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['firstName'],
            decoration: const InputDecoration(
              labelText: 'Prénom du Contact',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['lastName'],
            decoration: const InputDecoration(
              labelText: 'Nom du Contact',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['email'],
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['phone'],
            decoration: const InputDecoration(
              labelText: 'Téléphone',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['address'],
            decoration: const InputDecoration(
              labelText: 'Adresse',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['company'],
            decoration: const InputDecoration(
              labelText: 'Entreprise',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['externalInfo'],
            decoration: const InputDecoration(
              labelText: 'Informations Externes',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
        ];
      case 'modify_document':
        return [
          TextFormField(
            controller: ctrlMap['folderName'],
            decoration: const InputDecoration(
              labelText: 'Nom du Dossier',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: ctrlMap['documentName'],
            decoration: const InputDecoration(
              labelText: 'Nom du Document',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => onFieldChanged(),
          ),
        ];
      default:
        return [
          Text(
            'Action "$action" inconnue ou non supportée.',
            style: const TextStyle(color: Colors.red),
          ),
        ];
    }
  }

  Widget _buildNotificationsSection() {
    return SizedBox(
      width: double.infinity,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notifications',
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: neutralDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Aucune notification pour le moment.',
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectedUsersSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Utilisateurs Connectés',
              style: GoogleFonts.roboto(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: neutralDark,
              ),
            ),
            const SizedBox(height: 10),
            _connectedUsers.isEmpty
                ? Center(
                    child: Text(
                      'Aucun utilisateur connecté.',
                      style: GoogleFonts.roboto(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  )
                : Column(
                    children: _connectedUsers.map((user) {
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Text(
                            user.displayName.isNotEmpty
                                ? user.displayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          user.displayName,
                          style: GoogleFonts.roboto(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          'Statut: ${user.isOnline ? 'En Ligne' : 'Hors Ligne'}',
                          style: GoogleFonts.roboto(
                            color: Colors.grey[600],
                          ),
                        ),
                        trailing: Icon(
                          user.isOnline ? Icons.circle : Icons.circle_outlined,
                          color: user.isOnline ? Colors.green : Colors.red,
                          size: 16,
                        ),
                      );
                    }).toList(),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 197, 197, 197),
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.logout),
                          tooltip: 'Déconnexion',
                          onPressed: () async {
                            await authService.signOut();
                            if (!mounted) return;
                            Navigator.pushReplacementNamed(context, '/');
                          },
                        ),
                      ],
                    ),
                    Expanded(
                      child: constraints.maxWidth < 600
                          ? _buildMobileLayout()
                          : _buildDesktopLayout(),
                    ),
                  ],
                );
              },
            ),
            if (MediaQuery.of(context).size.width < 600)
              _buildVoiceChatContainer(),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Cartes de fonctionnalités
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: dashboardItems.map((item) => FeatureCard(item: item)).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // Section Profil
          Consumer<AuthService>(
            builder: (context, authService, child) {
              return GestureDetector(
                onTap: () {
                  _navigateToProfile();
                },
                child: Column(
                  children: [
                    ProfileAvatar(radius: 30),
                    const SizedBox(height: 10),
                    Text(
                      authService.currentUser?.displayName ?? 'Utilisateur',
                      style: GoogleFonts.roboto(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Section Tâches à Venir
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildUpcomingTasksSection(),
          ),
          const SizedBox(height: 16),
          // Section Utilisateurs Connectés
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildConnectedUsersSection(),
          ),
          const SizedBox(height: 16),
          // Section Assistant IA
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildChatAssistantSection(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar
        Container(
          width: 250,
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(2, 0),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section Profil
              Consumer<AuthService>(
                builder: (context, authService, child) {
                  return GestureDetector(
                    onTap: _navigateToProfile,
                    child: Row(
                      children: [
                        ProfileAvatar(radius: 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            authService.currentUser?.displayName ?? 'Utilisateur',
                            style: GoogleFonts.roboto(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              // Cartes de fonctionnalités
              Expanded(
                child: ListView(
                  children: dashboardItems.map((item) => FeatureCard(item: item)).toList(),
                ),
              ),
              const SizedBox(height: 20),
              // Contrôles vocaux
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(2, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: _toggleAssistantListening,
                      child: ScaleTransition(
                        scale: _animation,
                        child: CircleAvatar(
                          backgroundColor: _isListening ? Colors.redAccent : Colors.grey[400],
                          child: Icon(
                            _isTtsEnabled ? Icons.mic_off : Icons.mic,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isTtsEnabled ? Icons.headset : Icons.headset_off,
                        color: _isTtsEnabled ? Colors.blueAccent : Colors.grey,
                        size: 28,
                      ),
                      tooltip: _isTtsEnabled ? 'Désactiver la lecture vocale' : 'Activer la lecture vocale',
                      onPressed: () {
                        if (!mounted) return;
                        setState(() {
                          _isTtsEnabled = !_isTtsEnabled;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_isTtsEnabled ? 'Lecture vocale activée' : 'Lecture vocale désactivée'),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.settings_voice, color: Colors.blueGrey[800]),
                      tooltip: 'Paramètres de Voix',
                      onPressed: _openVoiceSettings,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Zone principale
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Assistant IA
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildChatAssistantSection(),
                ),
              ),
              // Colonne droite
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 16.0, right: 16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      // Tâches à venir
                      Expanded(
                        flex: 5,
                        child: _buildUpcomingTasksSection(),
                      ),
                      const SizedBox(height: 16),
                      // Utilisateurs connectés
                      Expanded(
                        flex: 3,
                        child: _buildConnectedUsersSection(),
                      ),
                      const SizedBox(height: 16),
                      // Notifications
                      Expanded(
                        flex: 2,
                        child: _buildNotificationsSection(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceChatContainer() {
    return Positioned(
      bottom: 20,
      left: 20,
      child: MediaQuery.of(context).size.width < 600
          ? Container(
              width: MediaQuery.of(context).size.width > 40
                  ? MediaQuery.of(context).size.width - 40
                  : 100,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _toggleAssistantListening,
                    child: ScaleTransition(
                      scale: _animation,
                      child: CircleAvatar(
                        backgroundColor: _isListening ? Colors.redAccent : Colors.grey[400],
                        child: Icon(
                          _isTtsEnabled ? Icons.mic_off : Icons.mic,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isTtsEnabled ? Icons.headset : Icons.headset_off,
                      color: _isTtsEnabled ? Colors.blueAccent : Colors.grey,
                    ),
                    tooltip: _isTtsEnabled ? 'Désactiver la lecture vocale' : 'Activer la lecture vocale',
                    onPressed: () {
                      if (!mounted) return;
                      setState(() {
                        _isTtsEnabled = !_isTtsEnabled;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_isTtsEnabled ? 'Lecture vocale activée' : 'Lecture vocale désactivée'),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.settings_voice, color: Colors.blueGrey[800]),
                    tooltip: 'Paramètres de Voix',
                    onPressed: _openVoiceSettings,
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  void _navigateToProfile() {
    Navigator.pushNamed(context, '/profile_page');
  }
}

class FeatureCard extends StatefulWidget {
  final DashboardItem item;
  const FeatureCard({Key? key, required this.item}) : super(key: key);

  @override
  _FeatureCardState createState() => _FeatureCardState();
}

class _FeatureCardState extends State<FeatureCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isTapped = false;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      lowerBound: 1.0,
      upperBound: 1.05,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onEnter(bool hover) {
    if (hover) {
      _scaleController.forward();
      setState(() {
        _isHovered = true;
      });
    } else {
      _scaleController.reverse();
      setState(() {
        _isHovered = false;
      });
    }
  }

  void _onTapDown(TapDownDetails details) {
    _scaleController.forward();
    setState(() {
      _isTapped = true;
    });
  }

  void _onTapUp(TapUpDetails details) {
    _scaleController.reverse();
    setState(() {
      _isTapped = false;
    });
    _navigateToPage();
  }

  void _onTapCancel() {
    _scaleController.reverse();
    setState(() {
      _isTapped = false;
    });
  }

  void _navigateToPage() {
    if (widget.item.routeName.isNotEmpty) {
      Navigator.pushNamed(context, widget.item.routeName, arguments: {
        'workspaceId': (context.findAncestorStateOfType<_DashboardPageState>()?.workspaceId ?? '')
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onEnter(true),
      onExit: (_) => _onEnter(false),
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedScale(
          scale: _isHovered || _isTapped ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Card(
            elevation: 4,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      widget.item.icon,
                      size: 30,
                      color: Colors.grey[800],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.item.title,
                        style: GoogleFonts.roboto(
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UserModel {
  final String id;
  final String displayName;
  final bool isOnline;

  UserModel({
    required this.id,
    required this.displayName,
    required this.isOnline,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      displayName: data['displayName'] ?? 'Utilisateur',
      isOnline: data['isOnline'] ?? false,
    );
  }
}

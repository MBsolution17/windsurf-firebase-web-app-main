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
import 'package:cloud_functions/cloud_functions.dart'; // Pour les fonctions Cloud
import 'package:audioplayers/audioplayers.dart'; // Pour la lecture audio
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart'; // Pour Clipboard
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart'; // Pour SharedPreferences

import '../models/task.dart';
import '../models/folder.dart';
import '../models/contact.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/web_speech_recognition_service.dart';
import '../services/auth_service.dart';
import 'contact_page.dart';
import 'profile_page.dart'; // **Import de ProfilePage si nécessaire**
import '../widgets/profile_avatar.dart'; // **Import du widget ProfileAvatar**

/// Simple model for the dashboard items
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
  const DashboardPage({Key? key}) : super(key: key);

  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Services IA & Speech
  AIService? _aiService;
  WebSpeechRecognitionService? _speechService;

  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // Gestion de l'écoute micro
  bool _isListening = false;

  // Animation du micro
  late AnimationController _animationController;
  late Animation<double> _animation;

  // Pour les formulaires (ajout contact, etc.)
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _externalInfoController = TextEditingController();

  // Folders & Contacts
  String? _selectedFolderId;
  List<Contact> _availableContacts = [];

  // Tâches & Calendrier
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Task>> _tasksByDate = {};

  // Chat IA
  String _aiResponse = '';
  String _lastError = '';

  // AudioPlayer (TTS mobile)
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isTtsEnabled = false; // État pour activer/désactiver la lecture vocale

  // Voix disponibles (web)
  List<html.SpeechSynthesisVoice> _availableVoices = [];
  html.SpeechSynthesisVoice? _selectedVoice;
  // Voix mobiles
  String _selectedVoiceName = 'fr-FR-Wavenet-D';
  double _selectedSpeakingRate = 1.0;
  double _selectedPitch = 1.0; // Pour le web éventuellement

  // Clés pour SharedPreferences
  static const String prefSelectedVoiceName = 'selectedVoiceName';
  static const String prefSelectedVoiceId = 'selectedVoiceId';

  // Palette de couleurs
  final Color primaryColor = Colors.grey[800]!;
  final Color neutralDark = Colors.grey[800]!;

  // Dashboard Items
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

  // Mapping action -> route
  final Map<String, String> actionRouteMap = {
    'create_task': '/task_tracker',
    'add_contact': '/contact_page',
    'create_folder_with_document': '/document_page',
    'create_folder_and_add_contact': '/document_page',
    'modify_document': '/document_page',
    // Ajoutez d'autres mappings si nécessaire
  };

  @override
  void initState() {
    super.initState();

    _selectedDay = DateTime.now();
    _focusedDay = DateTime.now();
    _calendarFormat = CalendarFormat.month;

    // Fetch vos données
    _fetchAllTasks();
    _fetchAllFolders();
    _fetchAvailableContacts();

    // Animation micro
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _animation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Initialise IA & Speech
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _aiService = Provider.of<AIService>(context, listen: false);
      _speechService = Provider.of<WebSpeechRecognitionService>(context, listen: false);

      // Reconnaissance vocale
      if (_speechService != null) {
        bool available = await _speechService!.initialize();
        if (!available && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('La reconnaissance vocale n\'est pas disponible.')),
          );
        }
      }

      // Voix web
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
        // Mobile
        _loadSavedVoice();
      }
    });

    // Callbacks de reconnaissance vocale
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_speechService != null) {
        _speechService!.onResult = (transcript) async {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _lastError = '';
            _aiResponse = 'En attente de la réponse de l\'IA...';
          });
          debugPrint('Texte reconnu : $transcript');

          // Envoi au service IA
          try {
            if (_aiService == null) return;
            ChatMessage aiMessage = await _aiService!.sendMessage(transcript);
            String responseContent = aiMessage.content;
            debugPrint('Réponse de l\'IA : $responseContent');
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
            debugPrint('Erreur lors de l\'envoi du message à l\'IA : $e');
          }
        };

        _speechService!.onError = (error) {
          if (!mounted) return;
          setState(() {
            _lastError = error;
            _isListening = false;
            _aiResponse = '';
          });
          debugPrint('Erreur de reconnaissance vocale : $error');
        };
      }
    });

    // Focus
    _chatFocusNode.addListener(() {
      if (!_chatFocusNode.hasFocus && _isListening) {
        _toggleAssistantListening();
      }
    });

    // Écoute des messages validés
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

  // ---------------------------------------------------------------------------
  // FETCH DATA (Firestore) - À adapter selon votre logique
  // ---------------------------------------------------------------------------
  void _fetchAllTasks() {
    // TODO: Votre logique Firestore pour récupérer les tâches, puis remplir _tasksByDate
  }

  void _fetchAllFolders() {
    // TODO: Votre logique Firestore pour récupérer les dossiers
  }

  void _fetchAvailableContacts() {
    // TODO: Votre logique Firestore pour récupérer les contacts
  }

  // ---------------------------------------------------------------------------
  // ÉCOUTE DES MESSAGES VALIDÉS
  // ---------------------------------------------------------------------------
  void _listenToValidatedMessages() {
    _firestore
        .collection('chat_messages')
        .where('status', isEqualTo: 'validated')
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        ChatMessage message = ChatMessage.fromFirestore(doc);
        // Exécuter les actions du JSON
        _executeActionsFromMessage(message);
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
    String action = actionData['action'] ?? '';
    Map<String, dynamic> data = actionData['data'] ?? {};

    debugPrint('Exécution de l\'action: $action, data=$data');
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
        debugPrint('Action inconnue: $action');
    }
  }

  // ---------------------------------------------------------------------------
  // MÉTHODES QUI FONT VRAIMENT LES INSERTIONS FIRESTORE
  // ---------------------------------------------------------------------------

  /// Exemple de création de tâche dans la collection "tasks"
  Future<void> _createTask(Map<String, dynamic> data) async {
    String title = data['title'] ?? '';
    String description = data['description'] ?? '';
    String dueDateStr = data['dueDate'] ?? '';
    String priority = data['priority'] ?? 'Medium';

    debugPrint(
      'Création de la tâche "$title", desc="$description", '
      'date="$dueDateStr", prio=$priority ...'
    );

    // Parse la date si besoin
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(dueDateStr);
    } catch (_) {
      // En cas de parsing impossible, met une date par défaut
      parsedDate = DateTime.now().add(const Duration(days: 1));
    }

    // Insère dans Firestore
    await _firestore.collection('tasks').add({
      'title': title,
      'description': description,
      'dueDate': parsedDate,
      'priority': priority,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'Pending', // ou tout autre champ
    });

    debugPrint('Tâche "$title" insérée dans la collection "tasks" !');
  }

  /// Exemple de création de contact dans la collection "contacts"
  Future<void> _addContact(Map<String, dynamic> data) async {
    String firstName = data['firstName'] ?? '';
    String lastName = data['lastName'] ?? '';
    String email = data['email'] ?? '';
    String phone = data['phone'] ?? '';
    String address = data['address'] ?? '';
    String company = data['company'] ?? '';
    String externalInfo = data['externalInfo'] ?? '';

    debugPrint(
      'Création d\'un contact "$firstName $lastName", phone="$phone", email="$email"...'
    );

    await _firestore.collection('contacts').add({
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'address': address,
      'company': company,
      'externalInfo': externalInfo,
      'createdAt': FieldValue.serverTimestamp(),
    });

    debugPrint('Contact "$firstName $lastName" inséré dans la collection "contacts" !');
  }

  /// Exemple de création d'un dossier + contact
  Future<void> _createFolderAndAddContact(Map<String, dynamic> data) async {
    String folderName = data['folderName'] ?? '';
    Map<String, dynamic> contactData = data['contact'] ?? {};

    debugPrint('Création du dossier "$folderName" + contact $contactData ...');

    // 1) Crée le dossier dans "folders"
    final folderRef = await _firestore.collection('folders').add({
      'folderName': folderName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    debugPrint('Dossier "$folderName" inséré dans la collection "folders".');

    // 2) Puis crée le contact (dans la collection globale "contacts")
    String firstName = contactData['firstName'] ?? '';
    String lastName = contactData['lastName'] ?? '';
    String email = contactData['email'] ?? '';
    String phone = contactData['phone'] ?? '';
    String address = contactData['address'] ?? '';
    String company = contactData['company'] ?? '';
    String externalInfo = contactData['externalInfo'] ?? '';

    await _firestore.collection('contacts').add({
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'address': address,
      'company': company,
      'externalInfo': externalInfo,
      'folderId': folderRef.id, // on associe le contact au folder
      'createdAt': FieldValue.serverTimestamp(),
    });

    debugPrint(
      'Contact "$firstName $lastName" ajouté et lié au folderId=${folderRef.id} !'
    );
  }

  // ---------------------------------------------------------------------------
  // VOIX (TTS)
  // ---------------------------------------------------------------------------
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
      // Mobile
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
    debugPrint('Texte à lire : $textToSpeak');

    if (kIsWeb) {
      _speakWeb(textToSpeak);
    } else {
      // Mobile : via Cloud Functions
      try {
        HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('synthesizeSpeech');
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
        debugPrint('Erreur synthèse vocale: $e');
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

  // ---------------------------------------------------------------------------
  // METHODE POUR OUVRIR LES PARAMÈTRES DE VOIX
  // ---------------------------------------------------------------------------
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
                // Si on est sur le Web, on liste les voix `html.SpeechSynthesisVoice`
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
                ]
                // Sinon, sur mobile, on propose un Dropdown "maison"
                else ...[
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
                // Slider de vitesse
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
                // Slider de pitch si on est sur le Web
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
                // Bouton d'écoute d'exemple
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

  // ---------------------------------------------------------------------------
  // RECONNAISSANCE VOCALE
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // ENVOI MESSAGE À L'IA
  // ---------------------------------------------------------------------------
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
      debugPrint('Erreur lors de l\'envoi du message: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // TÂCHES
  // ---------------------------------------------------------------------------
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
                const SizedBox(height: 8),
                Text('Date d\'échéance: ${DateFormat('dd/MM/yyyy').format(task.dueDate)}'),
                const SizedBox(height: 8),
                Text('Priorité: ${task.priority.toString().split('.').last}'),
                const SizedBox(height: 8),
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
    // Extrait 5 tâches
    List<Task> upcomingTasks = _tasksByDate.values
        .expand((tasks) => tasks)
        .where((task) =>
            task.dueDate.isAfter(DateTime.now()) &&
            task.status != TaskStatus.Done)
        .toList();

    upcomingTasks.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    upcomingTasks = upcomingTasks.take(5).toList();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titre
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tâches à Venir',
                  style: GoogleFonts.roboto(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: neutralDark,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/task_tracker');
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: primaryColor,
                  ),
                  child: const Text('Voir Tout'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (upcomingTasks.isEmpty)
              Center(
                child: Text(
                  'Aucune tâche à venir',
                  style: GoogleFonts.roboto(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              )
            else
              Column(
                children: [
                  // Première tâche
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[300]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 2,
                          blurRadius: 5,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(Icons.star, color: primaryColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Prochaine Tâche',
                                style: GoogleFonts.roboto(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: neutralDark,
                                ),
                              ),
                              Text(
                                upcomingTasks.first.title,
                                style: GoogleFonts.roboto(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: neutralDark,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'À faire le ${DateFormat('dd/MM/yyyy').format(upcomingTasks.first.dueDate)}',
                                style: GoogleFonts.roboto(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(upcomingTasks.first.status),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            upcomingTasks.first.status
                                .toString()
                                .split('.')
                                .last,
                            style: GoogleFonts.roboto(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Les autres tâches
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: (upcomingTasks.length > 1)
                          ? upcomingTasks.length - 1
                          : 0,
                      itemBuilder: (context, index) {
                        final task = upcomingTasks[index + 1];
                        return ListTile(
                          title: Text(
                            task.title,
                            style: GoogleFonts.roboto(
                              fontWeight: FontWeight.w600,
                              color: neutralDark,
                            ),
                          ),
                          subtitle: Text(
                            '${DateFormat('dd MMM yyyy').format(task.dueDate)} - ${task.priority.toString().split('.').last}',
                            style: GoogleFonts.roboto(
                              color: Colors.grey[600],
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getStatusColor(task.status),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              task.status.toString().split('.').last,
                              style: GoogleFonts.roboto(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          onTap: () => _showTaskDetailsDialog(task),
                        );
                      },
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GESTION DU JSON (IA)
  // ---------------------------------------------------------------------------
  bool isJson(String text) {
    try {
      final decoded = jsonDecode(text);
      return (decoded is Map<String, dynamic> || decoded is List<dynamic>);
    } catch (e) {
      debugPrint('Erreur de parsing JSON: $e');
      debugPrint('Contenu JSON reçu: $text');
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
    } catch (e) {
      debugPrint('Erreur lors de la conversion JSON en phrase : $e');
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
        // On parse la date si possible
        DateTime? parsedDate;
        try {
          parsedDate = DateTime.parse(dueDate);
        } catch (_) {}
        String dateFormatee =
            parsedDate != null ? DateFormat('dd/MM/yyyy').format(parsedDate) : dueDate;
        return 'Nouvelle tâche: "$title" (priorité $priority), décrite comme "$description", à réaliser d\'ici le $dateFormatee.';

      case 'add_contact':
        String firstName = data['firstName'] ?? '';
        String lastName = data['lastName'] ?? '';
        String phone = data['phone'] ?? '';
        return 'Nouveau contact ajouté : $firstName $lastName (tél: $phone).';

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
        return 'Le document "$docName" dans le dossier "$folderName2" va être modifié.';

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
      } else {
        throw FormatException('Structure JSON inattendue');
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
                    Navigator.pushNamed(context, routeName);
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
    } catch (e) {
      debugPrint('Erreur lors de la conversion JSON en phrase : $e');
      return SelectableText(
        'Impossible de parser le JSON : $sentence',
        style: GoogleFonts.roboto(
          color: Colors.red,
          fontSize: 14,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // CHAT IA
  // ---------------------------------------------------------------------------
  Widget _buildChatAssistantSection() {
    // Si _aiService n'est pas encore initialisé
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
            Expanded(
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
                  // Auto-scroll
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
                            crossAxisAlignment:
                                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              // Affichage du contenu
                              if (!isUser && isJson(message.content))
                                buildSentenceResponseUI(message.content)
                              else if (!isUser && !isJson(message.content))
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                      message.content,
                                      style: GoogleFonts.roboto(
                                        color: Colors.black87,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Ce message ne peut pas être modifié car il n\'est pas au format JSON.',
                                      style: TextStyle(color: Colors.red, fontSize: 12),
                                    ),
                                  ],
                                )
                              else
                                SelectableText(
                                  message.content,
                                  style: GoogleFonts.roboto(
                                    color: Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),

                              const SizedBox(height: 4),
                              Text(
                                'Statut: ${message.status.toString().split('.').last}',
                                style: const TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                              if (message.type == MessageType.ai &&
                                  message.status == MessageStatus.pending_validation)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    ElevatedButton(
                                      onPressed: () {
                                        // Valider MANUELLEMENT
                                        _aiService!.handleValidation(
                                          message.id,
                                          MessageStatus.validated,
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.grey[300],
                                        foregroundColor: Colors.black54,
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
            // Zone de saisie
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
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 16.0,
                      ),
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
                // Micro
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
                // Lecture vocale On/Off
                IconButton(
                  icon: Icon(
                    _isTtsEnabled ? Icons.headset : Icons.headset_off,
                    color: _isTtsEnabled ? Colors.blueAccent : Colors.grey,
                  ),
                  tooltip: _isTtsEnabled
                      ? 'Désactiver la lecture vocale'
                      : 'Activer la lecture vocale',
                  onPressed: () {
                    if (!mounted) return;
                    setState(() {
                      _isTtsEnabled = !_isTtsEnabled;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _isTtsEnabled
                              ? 'Lecture vocale activée'
                              : 'Lecture vocale désactivée',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                // Paramètres de voix
                IconButton(
                  icon: Icon(Icons.settings_voice, color: Colors.blueGrey[800]),
                  tooltip: 'Paramètres de Voix',
                  onPressed: _openVoiceSettings,
                ),
                const SizedBox(width: 8),
                // Bouton envoi
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

  // ---------------------------------------------------------------------------
  // ÉDITION DES MESSAGES (JSON LIST)
  // ---------------------------------------------------------------------------
  void _showEditMessageDialog(ChatMessage message, {bool isAIMessage = false}) {
    if (!isJson(message.content)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le contenu du message n\'est pas un JSON valide.')),
      );
      return;
    }

    // Parser le JSON (objet ou liste)
    dynamic raw;
    try {
      raw = jsonDecode(message.content);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de parser le JSON.')),
      );
      return;
    }

    // On convertit tout en liste d'actions
    late List<Map<String, dynamic>> items;
    if (raw is List) {
      items = raw.map((e) => e as Map<String, dynamic>).toList();
    } else if (raw is Map<String, dynamic>) {
      items = [raw];
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Structure JSON inattendue.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState2) {
            return AlertDialog(
              title: const Text('Modifier le message'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pour chaque action, on affiche un panneau d'édition
                      for (int i = 0; i < items.length; i++)
                        _buildActionEditor(items, i, setState2),
                    ],
                  ),
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
                    // Validation de chaque action
                    bool allValid = true;
                    String errorMessage = '';

                    for (int i = 0; i < items.length; i++) {
                      final item = items[i];
                      String action = item['action'] ?? '';
                      final data = item['data'] ?? {};

                      switch (action) {
                        case 'create_task':
                          if ((data['title'] ?? '').isEmpty ||
                              (data['description'] ?? '').isEmpty ||
                              (data['dueDate'] ?? '').isEmpty ||
                              (data['priority'] ?? '').isEmpty) {
                            allValid = false;
                            errorMessage = 'Tous les champs de la tâche sont requis.';
                          }
                          break;
                        case 'create_folder_with_document':
                          if ((data['folderName'] ?? '').isEmpty ||
                              ((data['document']?['title']) ?? '').isEmpty ||
                              ((data['document']?['content']) ?? '').isEmpty) {
                            allValid = false;
                            errorMessage =
                                'Veuillez remplir tous les champs (dossier + document).';
                          }
                          break;
                        case 'add_contact':
                          if ((data['firstName'] ?? '').isEmpty ||
                              (data['lastName'] ?? '').isEmpty ||
                              (data['email'] ?? '').isEmpty ||
                              (data['phone'] ?? '').isEmpty ||
                              (data['address'] ?? '').isEmpty ||
                              (data['company'] ?? '').isEmpty ||
                              (data['externalInfo'] ?? '').isEmpty) {
                            allValid = false;
                            errorMessage = 'Tous les champs du contact sont requis.';
                          }
                          break;
                        case 'create_folder_and_add_contact':
                          final contact = data['contact'] ?? {};
                          if ((data['folderName'] ?? '').isEmpty ||
                              (contact['firstName'] ?? '').isEmpty ||
                              (contact['lastName'] ?? '').isEmpty ||
                              (contact['phone'] ?? '').isEmpty ||
                              (contact['email'] ?? '').isEmpty ||
                              (contact['address'] ?? '').isEmpty ||
                              (contact['company'] ?? '').isEmpty ||
                              (contact['externalInfo'] ?? '').isEmpty) {
                            allValid = false;
                            errorMessage =
                                'Veuillez remplir tous les champs (folderName + contact).';
                          }
                          break;
                        case 'modify_document':
                          if ((data['folderName'] ?? '').isEmpty ||
                              (data['documentName'] ?? '').isEmpty ||
                              (data['variables'] ?? {}).isEmpty) {
                            allValid = false;
                            errorMessage =
                                'Tous les champs (folderName, documentName, variables) sont requis.';
                          }
                          break;
                        default:
                          allValid = false;
                          errorMessage = 'Action inconnue ou non supportée.';
                      }
                      if (!allValid) break;
                    }

                    if (!allValid) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(errorMessage)),
                      );
                      return;
                    }

                    // Mise à jour Firestore
                    try {
                      // Ré-encoder : si 1 seul item => renvoi un objet, sinon => liste
                      String updatedContent;
                      if (items.length == 1) {
                        updatedContent = jsonEncode(items.first);
                      } else {
                        updatedContent = jsonEncode(items);
                      }

                      // NOUVEAU : On repasse d'abord en pending_validation,
                      // puis on repasse en validated pour relancer le stream.
                      await _firestore.collection('chat_messages').doc(message.id).update({
                        'content': updatedContent,
                        'status': 'pending_validation',
                      });

                      await _firestore.collection('chat_messages').doc(message.id).update({
                        'status': 'validated',
                      });

                      debugPrint('Message mis à jour (double update).');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Message mis à jour avec succès.')),
                        );
                      }
                      Navigator.of(context).pop();
                    } catch (e) {
                      debugPrint('Erreur lors de la mise à jour du message: $e');
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

  /// Construit un éditeur pour l'action [items[index]].
  Widget _buildActionEditor(
    List<Map<String, dynamic>> items,
    int index,
    void Function(void Function()) setState2,
  ) {
    final item = items[index];
    final String action = item['action'] ?? '(inconnu)';

    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(
        'Action n°${index + 1} : $action',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      children: [
        const SizedBox(height: 8),
        // On construit les champs selon l'action
        ..._buildEditableFields(item, setState2),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Détermine les champs à afficher selon l'action
  List<Widget> _buildEditableFields(
    Map<String, dynamic> jsonContent,
    void Function(void Function()) setState2,
  ) {
    String action = jsonContent['action'] ?? '';
    switch (action) {
      case 'create_task':
        return _buildCreateTaskFields(jsonContent, setState2);
      case 'create_folder_with_document':
        return _buildCreateFolderWithDocumentFields(jsonContent, setState2);
      case 'add_contact':
        return _buildAddContactFields(jsonContent, setState2);
      case 'create_folder_and_add_contact':
        return _buildCreateFolderAndAddContactFields(jsonContent, setState2);
      case 'modify_document':
        return _buildModifyDocumentFields(jsonContent, setState2);
      default:
        return [
          Text(
            'Action "$action" inconnue ou non supportée.',
            style: const TextStyle(color: Colors.red),
          ),
        ];
    }
  }

  // ---------------------------------------------------------------------------
  // CHAMPS D'ÉDITION PAR ACTION
  // ---------------------------------------------------------------------------
  List<Widget> _buildCreateTaskFields(
    Map<String, dynamic> jsonContent,
    void Function(void Function()) setState2,
  ) {
    final data = jsonContent['data'] ?? <String, dynamic>{};
    final titleController = TextEditingController(text: data['title'] ?? '');
    final descController = TextEditingController(text: data['description'] ?? '');
    final dueDateController = TextEditingController(text: data['dueDate'] ?? '');
    String selectedPriority = data['priority'] ?? 'Low';

    return [
      TextFormField(
        controller: titleController,
        decoration: const InputDecoration(
          labelText: 'Titre de la tâche',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          jsonContent['data']['title'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: descController,
        decoration: const InputDecoration(
          labelText: 'Description',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          jsonContent['data']['description'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: dueDateController,
        decoration: const InputDecoration(
          labelText: 'Date (YYYY-MM-DDTHH:MM:SSZ)',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          jsonContent['data']['dueDate'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: selectedPriority.isNotEmpty ? selectedPriority : null,
        decoration: const InputDecoration(
          labelText: 'Priorité',
          border: OutlineInputBorder(),
        ),
        items: ['Low', 'Medium', 'High'].map((p) {
          return DropdownMenuItem<String>(
            value: p,
            child: Text(p),
          );
        }).toList(),
        onChanged: (value) => setState2(() {
          if (value != null) {
            selectedPriority = value;
            jsonContent['data']['priority'] = value;
          }
        }),
      ),
    ];
  }

  List<Widget> _buildCreateFolderWithDocumentFields(
    Map<String, dynamic> jsonContent,
    void Function(void Function()) setState2,
  ) {
    final data = jsonContent['data'] ?? {};
    final folderController = TextEditingController(text: data['folderName'] ?? '');
    final doc = data['document'] ?? {};
    final docTitleController = TextEditingController(text: doc['title'] ?? '');
    final docContentController = TextEditingController(text: doc['content'] ?? '');

    return [
      TextFormField(
        controller: folderController,
        decoration: const InputDecoration(
          labelText: 'Nom du Dossier',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          jsonContent['data']['folderName'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: docTitleController,
        decoration: const InputDecoration(
          labelText: 'Titre du Document',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          jsonContent['data']['document']['title'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: docContentController,
        decoration: const InputDecoration(
          labelText: 'Contenu du Document',
          border: OutlineInputBorder(),
        ),
        maxLines: 3,
        onChanged: (value) => setState2(() {
          jsonContent['data']['document']['content'] = value.trim();
        }),
      ),
    ];
  }

  List<Widget> _buildAddContactFields(
    Map<String, dynamic> jsonContent,
    void Function(void Function()) setState2,
  ) {
    final data = jsonContent['data'] ?? {};
    final firstNameController = TextEditingController(text: data['firstName'] ?? '');
    final lastNameController = TextEditingController(text: data['lastName'] ?? '');
    final emailController = TextEditingController(text: data['email'] ?? '');
    final phoneController = TextEditingController(text: data['phone'] ?? '');
    final addressController = TextEditingController(text: data['address'] ?? '');
    final companyController = TextEditingController(text: data['company'] ?? '');
    final externalInfoController = TextEditingController(text: data['externalInfo'] ?? '');

    return [
      TextFormField(
        controller: firstNameController,
        decoration: const InputDecoration(
          labelText: 'Prénom',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          data['firstName'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: lastNameController,
        decoration: const InputDecoration(
          labelText: 'Nom',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          data['lastName'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: emailController,
        decoration: const InputDecoration(
          labelText: 'Email',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          data['email'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: phoneController,
        decoration: const InputDecoration(
          labelText: 'Téléphone',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          data['phone'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: addressController,
        decoration: const InputDecoration(
          labelText: 'Adresse',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          data['address'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: companyController,
        decoration: const InputDecoration(
          labelText: 'Entreprise',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          data['company'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: externalInfoController,
        decoration: const InputDecoration(
          labelText: 'Informations Externes',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          data['externalInfo'] = value.trim();
        }),
      ),
    ];
  }

  List<Widget> _buildCreateFolderAndAddContactFields(
    Map<String, dynamic> jsonContent,
    void Function(void Function()) setState2,
  ) {
    final data = jsonContent['data'] ?? {};
    final folderController = TextEditingController(text: data['folderName'] ?? '');
    final contact = data['contact'] ?? {};
    final firstNameController = TextEditingController(text: contact['firstName'] ?? '');
    final lastNameController = TextEditingController(text: contact['lastName'] ?? '');
    final emailController = TextEditingController(text: contact['email'] ?? '');
    final phoneController = TextEditingController(text: contact['phone'] ?? '');
    final addressController = TextEditingController(text: contact['address'] ?? '');
    final companyController = TextEditingController(text: contact['company'] ?? '');
    final externalInfoController = TextEditingController(text: contact['externalInfo'] ?? '');

    return [
      TextFormField(
        controller: folderController,
        decoration: const InputDecoration(
          labelText: 'Nom du Dossier',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          data['folderName'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: firstNameController,
        decoration: const InputDecoration(
          labelText: 'Prénom du Contact',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          contact['firstName'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: lastNameController,
        decoration: const InputDecoration(
          labelText: 'Nom du Contact',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          contact['lastName'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: emailController,
        decoration: const InputDecoration(
          labelText: 'Email',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          contact['email'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: phoneController,
        decoration: const InputDecoration(
          labelText: 'Téléphone',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          contact['phone'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: addressController,
        decoration: const InputDecoration(
          labelText: 'Adresse',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          contact['address'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: companyController,
        decoration: const InputDecoration(
          labelText: 'Entreprise',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          contact['company'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: externalInfoController,
        decoration: const InputDecoration(
          labelText: 'Informations Externes',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          contact['externalInfo'] = value.trim();
        }),
      ),
    ];
  }

  List<Widget> _buildModifyDocumentFields(
    Map<String, dynamic> jsonContent,
    void Function(void Function()) setState2,
  ) {
    final data = jsonContent['data'] ?? {};
    final folderController = TextEditingController(text: data['folderName'] ?? '');
    final docNameController = TextEditingController(text: data['documentName'] ?? '');
    Map<String, dynamic> variables =
        Map<String, dynamic>.from(data['variables'] ?? {});

    List<Widget> variableFields = [];
    variables.forEach((key, val) {
      final controller = TextEditingController(text: val.toString());
      variableFields.add(
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: key,
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => setState2(() {
            variables[key] = v.trim();
          }),
        ),
      );
      variableFields.add(const SizedBox(height: 8));
    });

    return [
      TextFormField(
        controller: folderController,
        decoration: const InputDecoration(
          labelText: 'Nom du Dossier',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          data['folderName'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: docNameController,
        decoration: const InputDecoration(
          labelText: 'Nom du Document',
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => setState2(() {
          data['documentName'] = value.trim();
        }),
      ),
      const SizedBox(height: 8),
      ...variableFields,
      // Mettre à jour les variables modifiées dans le JSON
      Builder(builder: (context) {
        data['variables'] = variables;
        return const SizedBox.shrink();
      }),
    ];
  }

  // ---------------------------------------------------------------------------
  // DISPOSITION GLOBALE
  // ---------------------------------------------------------------------------
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
                    // Bouton de déconnexion en haut à droite
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
            // Barre vocale en bas si petit écran
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
          // Menu latéral version mobile
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: dashboardItems.map((item) => FeatureCard(item: item)).toList(),
            ),
          ),
          const SizedBox(height: 16),
          // Avatar + nom
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
          // Assistant IA
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              height: 400,
              child: _buildChatAssistantSection(),
            ),
          ),
          const SizedBox(height: 16),
          // Tâches
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildUpcomingTasksSection(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Barre latérale gauche
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
              Consumer<AuthService>(
                builder: (context, authService, child) {
                  return GestureDetector(
                    onTap: () {
                      _navigateToProfile();
                    },
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
              Expanded(
                child: ListView(
                  children: dashboardItems.map((item) => FeatureCard(item: item)).toList(),
                ),
              ),
              const SizedBox(height: 20),
              // Barre vocale (micro + TTS) en bas de la sidebar
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
                            _isListening ? Icons.mic_off : Icons.mic,
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
                      tooltip: _isTtsEnabled
                          ? 'Désactiver la lecture vocale'
                          : 'Activer la lecture vocale',
                      onPressed: () {
                        if (!mounted) return;
                        setState(() {
                          _isTtsEnabled = !_isTtsEnabled;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _isTtsEnabled
                                  ? 'Lecture vocale activée'
                                  : 'Lecture vocale désactivée',
                            ),
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
        // Partie droite : Chat IA + Tâches
        Expanded(
          child: Column(
            children: [
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildChatAssistantSection(),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildUpcomingTasksSection(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Barre vocale en bas (mobile uniquement)
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
                          _isListening ? Icons.mic_off : Icons.mic,
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
                    tooltip: _isTtsEnabled
                        ? 'Désactiver la lecture vocale'
                        : 'Activer la lecture vocale',
                    onPressed: () {
                      if (!mounted) return;
                      setState(() {
                        _isTtsEnabled = !_isTtsEnabled;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _isTtsEnabled
                                ? 'Lecture vocale activée'
                                : 'Lecture vocale désactivée',
                          ),
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

/// Widget pour chaque fonctionnalité du dashboard
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(_scaleController);
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
      Navigator.pushNamed(context, widget.item.routeName);
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

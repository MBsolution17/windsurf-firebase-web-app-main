import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html; // Pour les opérations de téléchargement sur le web
import 'dart:js' as js; // Ajout pour l'interaction JavaScript
import 'package:firebase_web_app/services/speech_recognition_js.dart';
import 'package:firebase_web_app/theme_provider.dart';
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
import 'onboarding/onboarding_page.dart';

class DashboardItem {
  final String title;
  final IconData icon;
  final String routeName;

  DashboardItem({
    required this.title,
    required this.icon,
    required this.routeName,
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

  void _openReconfigureWorkspace() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OnboardingPage(workspaceId: widget.workspaceId),
      ),
    );
  }

  AIService? _aiService;
  WebSpeechRecognitionService? _speechService;

  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  bool _isListening = false;
  bool _isDarkTheme = false;

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

  String _lastError = '';

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isTtsEnabled = false;

  List<html.SpeechSynthesisVoice> _availableVoices = [];
  html.SpeechSynthesisVoice? _selectedVoice;
  String _selectedVoiceName = 'fr-FR-Wavenet-D';
  double _selectedSpeakingRate = 1.0;
  double _selectedPitch = 1.0;

  // Nouvelles variables pour les périphériques audio
  List<html.MediaDeviceInfo> _inputDevices = [];
  List<html.MediaDeviceInfo> _outputDevices = [];
  String? _selectedInputDeviceId;
  String? _selectedOutputDeviceId;

  static const String prefSelectedVoiceName = 'selectedVoiceName';
  static const String prefSelectedVoiceId = 'selectedVoiceId';
  static const String prefThemeMode = 'themeMode';
  // Nouvelles constantes pour les préférences de périphériques audio
  static const String prefInputDeviceId = 'selectedInputDeviceId';
  static const String prefOutputDeviceId = 'selectedOutputDeviceId';

  final List<DashboardItem> dashboardItems = [
    DashboardItem(
      title: 'Canaux',
      icon: Icons.chat,
      routeName: '/channel_list',
    ),
    DashboardItem(
      title: 'Collaborateurs',
      icon: Icons.people,
      routeName: '/friends',
    ),
    DashboardItem(
      title: 'Calendrier',
      icon: Icons.calendar_today,
      routeName: '/calendar',
    ),
    DashboardItem(
      title: 'Documents',
      icon: Icons.folder,
      routeName: '/documents',
    ),
    DashboardItem(
      title: 'Analyse',
      icon: Icons.analytics,
      routeName: '/analytics',
    ),
    DashboardItem(
      title: 'Contacts',
      icon: Icons.contact_mail,
      routeName: '/contact_page',
    ),
  ];

  final Map<String, String> actionRouteMap = {
    'create_task': '/calendar',
    'add_contact': '/contact_page',
    'create_folder_with_document': '/documents',
    'create_folder_and_add_contact': '/documents',
    'modify_document': '/documents',
  };

  late String workspaceId;

  List<UserModel> _connectedUsers = [];

  // Variable pour suivre le dernier message lu par TTS
  String? _lastTtsMessageId;

  Future<Uint8List?> _loadProfileImage(String? photoURL) async {
    if (photoURL == null || !kIsWeb) return null;
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
      debugPrint("Erreur lors du chargement de l'image via Firebase Function : $e");
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    workspaceId = widget.workspaceId;
    _selectedDay = DateTime.now();
    _focusedDay = DateTime.now();
    _calendarFormat = CalendarFormat.month;

    _loadThemePreference();

    _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('tasks')
        .snapshots()
        .listen((snapshot) {
      final Map<DateTime, List<Task>> tasksMap = {};
      for (var doc in snapshot.docs) {
        Task task = Task.fromFirestore(doc);
        DateTime date =
            DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day);
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
      _speechService = Provider.of<WebSpeechRecognitionService>(context, listen: false);

      if (_speechService != null) {
        bool available = await _speechService!.initialize();
        if (!available && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('La reconnaissance vocale n\'est pas disponible.')),
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
        
        // Charger les périphériques audio
        _loadAudioDevices();
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
          });
          if (_chatController.text.isEmpty) {
            _chatController.text = transcript;
          }
          try {
            if (_aiService == null) return;
            await _sendMessage(transcript);
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _lastError = 'Erreur lors de la communication avec l\'IA: $e';
            });
          }
        };

        _speechService!.onError = (error) {
          if (!mounted) return;
          setState(() {
            _lastError = error;
            _isListening = false;
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

  // Méthode pour charger les périphériques audio
  Future<void> _loadAudioDevices() async {
    if (kIsWeb) {
      try {
        // Demander la permission d'accéder aux périphériques
        await html.window.navigator.mediaDevices?.getUserMedia({
          'audio': true,
        });
        
        // Récupérer la liste des périphériques
        final devices = await html.window.navigator.mediaDevices?.enumerateDevices();
        
        if (devices != null) {
          setState(() {
            _inputDevices = devices.where((device) => device.kind == 'audioinput').cast<html.MediaDeviceInfo>().toList();
            _outputDevices = devices.where((device) => device.kind == 'audiooutput').cast<html.MediaDeviceInfo>().toList();
          });
          
          // Charger les préférences sauvegardées
          final prefs = await SharedPreferences.getInstance();
          _selectedInputDeviceId = prefs.getString(prefInputDeviceId);
          _selectedOutputDeviceId = prefs.getString(prefOutputDeviceId);
          
          // Si aucun appareil n'est sélectionné, utiliser les appareils par défaut
          if (_selectedInputDeviceId == null && _inputDevices.isNotEmpty) {
            _selectedInputDeviceId = _inputDevices.first.deviceId;
          }
          if (_selectedOutputDeviceId == null && _outputDevices.isNotEmpty) {
            _selectedOutputDeviceId = _outputDevices.first.deviceId;
          }
          
          // Configurer le service de reconnaissance vocale avec le périphérique par défaut
          if (_speechService != null && _selectedInputDeviceId != null) {
            try {
              js.context.callMethod('updateSpeechRecognitionDevice', [_selectedInputDeviceId]);
            } catch (e) {
              debugPrint("Erreur lors de la configuration du microphone: $e");
            }
          }
        }
      } catch (e) {
        debugPrint("Erreur lors de l'accès aux périphériques audio: $e");
      }
    }
  }
  
  // Méthode pour sauvegarder les préférences de périphérique audio
  Future<void> _saveAudioDevicePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedInputDeviceId != null) {
      await prefs.setString(prefInputDeviceId, _selectedInputDeviceId!);
      
      // Configurer le service de reconnaissance vocale
      if (_speechService != null) {
        try {
          js.context.callMethod('updateSpeechRecognitionDevice', [_selectedInputDeviceId]);
          
          // Si la reconnaissance est active, la redémarrer pour appliquer le changement
          if (_isListening) {
            _toggleAssistantListening();
            _toggleAssistantListening();
          }
        } catch (e) {
          debugPrint("Erreur lors de la configuration du microphone: $e");
        }
      }
    }
    
    if (_selectedOutputDeviceId != null) {
      await prefs.setString(prefOutputDeviceId, _selectedOutputDeviceId!);
    }
  }

  void _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkTheme = prefs.getBool(prefThemeMode) ?? false;
    });
  }

  void _saveThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefThemeMode, _isDarkTheme);
  }

  void _toggleTheme() {
    setState(() {
      _isDarkTheme = !_isDarkTheme;
      _saveThemePreference();
    });
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
      'name': folderName,
      'userId': user.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'version': 0,
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
      'timestamp': FieldValue.serverTimestamp(),
      'version': 0,
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
    if (kIsWeb) {
      _speakWeb(text);
    } else {
      try {
        HttpsCallable callable =
            FirebaseFunctions.instance.httpsCallable('synthesizeSpeech');
        final results = await callable.call(<String, dynamic>{
          'text': text,
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
    
    if (_selectedOutputDeviceId != null) {
      try {
        js.context.callMethod('setSpeechSynthesisOutputDevice', [_selectedOutputDeviceId]);
      } catch (e) {
        debugPrint("Erreur lors de la configuration de la sortie audio: $e");
      }
    }
    
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
        return StatefulBuilder(
          builder: (context, setState) {
            // Charger les périphériques audio au premier affichage du dialogue
            if (kIsWeb && (_inputDevices.isEmpty || _outputDevices.isEmpty)) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                await _loadAudioDevices();
                setState(() {}); // Mettre à jour l'interface après le chargement
              });
            }
            
            return AlertDialog(
              title: const Text('Paramètres Audio'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section pour les voix de synthèse
                    const Text(
                      'Voix de synthèse',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
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
                          setState(() {
                            _selectedVoiceName = value ?? '';
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                    
                    // Réglages de vitesse et hauteur
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
                              setState(() {
                                _selectedSpeakingRate = value;
                              });
                            },
                          ),
                        ),
                        Text('${_selectedSpeakingRate.toStringAsFixed(1)}x'),
                      ],
                    ),
                    
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
                                setState(() {
                                  _selectedPitch = value;
                                });
                              },
                            ),
                          ),
                          Text(_selectedPitch.toStringAsFixed(1)),
                        ],
                      ),
                    ],
                    
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 10),
                    
                    // Nouvelle section pour la sélection des périphériques d'entrée (microphones)
                    if (kIsWeb) ...[
                      const Text(
                        'Microphone',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      DropdownButton<String>(
                        value: _selectedInputDeviceId,
                        hint: const Text('Sélectionnez un microphone'),
                        isExpanded: true,
                        items: _inputDevices.map((device) {
                          return DropdownMenuItem<String>(
                            value: device.deviceId,
                            child: Text(device.label?.isNotEmpty == true
                                ? device.label!
                                : 'Microphone ${_inputDevices.indexOf(device) + 1}'),
                          );
                        }).toList(),
                        onChanged: (deviceId) {
                          setState(() {
                            _selectedInputDeviceId = deviceId;
                          });
                        },
                      ),
                      if (_inputDevices.isEmpty) 
                        const Text('Aucun microphone détecté. Vérifiez les permissions du navigateur.', 
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                      const SizedBox(height: 20),
                      
                      // Nouvelle section pour la sélection des périphériques de sortie (haut-parleurs)
                      const Text(
                        'Sortie audio',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      DropdownButton<String>(
                        value: _selectedOutputDeviceId,
                        hint: const Text('Sélectionnez une sortie audio'),
                        isExpanded: true,
                        items: _outputDevices.map((device) {
                          return DropdownMenuItem<String>(
                            value: device.deviceId,
                            child: Text(device.label?.isNotEmpty == true
                                ? device.label!
                                : 'Sortie audio ${_outputDevices.indexOf(device) + 1}'),
                          );
                        }).toList(),
                        onChanged: (deviceId) {
                          setState(() {
                            _selectedOutputDeviceId = deviceId;
                          });
                        },
                      ),
                      if (_outputDevices.isEmpty) 
                        const Text('Aucune sortie audio détectée. Vérifiez les permissions du navigateur.', 
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                    ],
                    
                    const SizedBox(height: 20),
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
                    if (kIsWeb) {
                      _saveAudioDevicePreferences();
                    }
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Paramètres audio mis à jour')),
                    );
                  },
                  child: const Text('Appliquer'),
                ),
              ],
            );
          },
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
      await _aiService!.sendMessage(message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastError = 'Erreur lors de l\'envoi du message: $e';
      });
    }
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.Pending:
        return Colors.orange[300]!;
      case TaskStatus.InProgress:
        return Colors.blue;
      case TaskStatus.Done:
        return Colors.green[300]!;
      case TaskStatus.PendingValidation:
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  String _translateTaskStatus(TaskStatus status) {
    switch (status) {
      case TaskStatus.Pending:
        return 'En attente';
      case TaskStatus.InProgress:
        return 'En cours';
      case TaskStatus.Done:
        return 'Terminé';
      case TaskStatus.PendingValidation:
        return 'À valider';
      default:
        return 'Inconnu';
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
                Text(
                    'Date d\'échéance: ${DateFormat('dd/MM/yyyy').format(task.dueDate)}'),
                const SizedBox(height: 6),
                Text('Priorité: ${task.priority.toString().split('.').last}'),
                const SizedBox(height: 6),
                Text('Statut: ${_translateTaskStatus(task.status)}'),
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
            task.dueDate.isAfter(DateTime.now()) && task.status != TaskStatus.Done)
        .toList();
    upcomingTasks.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    upcomingTasks = upcomingTasks.take(20).toList();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      color: Theme.of(context).cardColor,
      child: Container(
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                      color: Theme.of(context).textTheme.bodyLarge!.color,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/calendar',
                          arguments: {'workspaceId': workspaceId});
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).textTheme.bodyMedium!.color,
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
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[800]
                          : const Color.fromARGB(255, 210, 210, 210),
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
                                color: Theme.of(context).textTheme.bodyLarge!.color,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              task.description,
                              style: GoogleFonts.roboto(
                                fontSize: 12,
                                color: Theme.of(context).textTheme.bodyMedium!.color,
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
                                    color: Theme.of(context).textTheme.bodyMedium!.color,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: task.status == TaskStatus.PendingValidation
                                      ? () async {
                                          try {
                                            await _firestore
                                                .collection('workspaces')
                                                .doc(workspaceId)
                                                .collection('tasks')
                                                .doc(task.id)
                                                .update({
                                              'status': 'Done',
                                            });
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                  content:
                                                      Text('Tâche marquée comme terminée.')),
                                            );
                                          } catch (e) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                  content: Text(
                                                      'Erreur lors de la mise à jour: $e')),
                                            );
                                          }
                                        }
                                      : null,
                                  child: Container(
                                    constraints: const BoxConstraints(minWidth: 60),
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(task.status),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _translateTaskStatus(task.status),
                                        style: GoogleFonts.roboto(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
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
                                  backgroundColor: Theme.of(context).primaryColor,
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
                    color: Theme.of(context).textTheme.bodyLarge!.color,
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
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[800]
                        : Theme.of(context).primaryColor,
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
                color: Theme.of(context).textTheme.bodyLarge!.color,
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

  void _handleNewMessage(ChatMessage message) async {
    if (_isTtsEnabled &&
        message.type == MessageType.ai &&
        message.timestamp.isAfter(DateTime.now().subtract(const Duration(seconds: 5))) &&
        _lastTtsMessageId != message.id) {
      _lastTtsMessageId = message.id;
      if (isJson(message.content)) {
        await _speak(jsonToSentence(message.content));
      } else {
        await _speak(message.content);
      }
    }
  }

  Widget _buildChatAssistantSection() {
    if (_aiService == null) {
      return const Center(child: Text('Service IA non disponible'));
    }
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              'assets/images/Orion.png',
              height: 30,
              fit: BoxFit.contain,
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color.fromARGB(255, 168, 168, 168)
                  : null,
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
                    return Center(
                      child: Text(
                        'Chargement des messages...',
                        style: GoogleFonts.roboto(
                            color: Theme.of(context).textTheme.bodyMedium!.color),
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Text(
                        'Aucun message trouvé.',
                        style: GoogleFonts.roboto(
                          fontSize: 16,
                          color: Theme.of(context).textTheme.bodyMedium!.color,
                        ),
                      ),
                    );
                  }
                  final chatMessages = snapshot.data!;
                  // Déplacer le défilement uniquement
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        _scrollController.position.minScrollExtent,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  });
                  // Vérifier le dernier message pour TTS
                  if (chatMessages.isNotEmpty) {
                    _handleNewMessage(chatMessages.first);
                  }
                  return ListView.builder(
                    reverse: true,
                    controller: _scrollController,
                    itemCount: chatMessages.length,
                    itemBuilder: (context, index) {
                      final message = chatMessages[index];
                      bool isUser = message.type == MessageType.user;
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser
                                ? (Theme.of(context).brightness == Brightness.dark
                                    ? Color(0xFF4A6070)
                                    : Colors.blue[200])
                                : Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[700]
                                    : Colors.grey[300],
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (!isUser && isJson(message.content))
                                buildSentenceResponseUI(message.content)
                              else
                                SelectableText(
                                  message.content,
                                  style: GoogleFonts.roboto(
                                    color: Theme.of(context).textTheme.bodyLarge!.color,
                                    fontSize: 14,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              if (!(message.status == MessageStatus.pending_validation ||
                                  message.status == MessageStatus.validated))
                                Text(
                                  'Statut: ${message.status.toString().split('.').last}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).textTheme.bodySmall!.color),
                                ),
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
                                        backgroundColor: Colors.grey[500],
                                        foregroundColor: Colors.white,
                                        textStyle: const TextStyle(fontSize: 16),
                                      ),
                                      child: const Text('Valider'),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () {
                                        _showEditMessageDialog(message, isAIMessage: true);
                                      },
                                      icon: Icon(Icons.edit,
                                          size: 16,
                                          color: Theme.of(context).textTheme.bodySmall!.color),
                                      label: Text(
                                        'Modifier',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                Theme.of(context).textTheme.bodySmall!.color),
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
                      fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
                    ),
                    style: TextStyle(color: Theme.of(context).textTheme.bodyLarge!.color),
                    onSubmitted: (value) async {
                      if (value.isNotEmpty) {
                        await _sendMessage(value);
                        _chatController.clear();
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
                      backgroundColor:
                          _isListening ? Colors.redAccent : Theme.of(context).iconTheme.color,
                      child: Icon(
                        _isTtsEnabled ? Icons.mic_off : Icons.mic,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    _isTtsEnabled ? Icons.headset : Icons.headset_off,
                    color: _isTtsEnabled ? Colors.blueAccent : Theme.of(context).iconTheme.color,
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
                        content: Text(_isTtsEnabled
                            ? 'Lecture vocale activée'
                            : 'Lecture vocale désactivée'),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.tune,
                    color: Theme.of(context).iconTheme.color,
                  ),
                  tooltip: 'Réglages vocaux',
                  onPressed: _openVoiceSettings,
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: () async {
                      if (_chatController.text.isNotEmpty) {
                        await _sendMessage(_chatController.text);
                        _chatController.clear();
                        setState(() {});
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
          ctrlMap['externalInfo'] =
              TextEditingController(text: contact['externalInfo'] ?? '');
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF4A6070)
                        : Colors.blue[200],
                    foregroundColor: Colors.white,
                  ),
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

  List<Widget> _buildEditableFields(Map<String, dynamic> jsonContent,
      Map<String, TextEditingController> ctrlMap, VoidCallback onFieldChanged) {
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
        color: Theme.of(context).cardColor,
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
                  color: Theme.of(context).textTheme.bodyLarge!.color,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Aucune notification pour le moment.',
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  color: Theme.of(context).textTheme.bodyMedium!.color,
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
      color: Theme.of(context).cardColor,
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
                color: Theme.of(context).textTheme.bodyLarge!.color,
              ),
            ),
            const SizedBox(height: 10),
            _connectedUsers.isEmpty
                ? Center(
                    child: Text(
                      'Aucun utilisateur connecté.',
                      style: GoogleFonts.roboto(
                        fontSize: 16,
                        color: Theme.of(context).textTheme.bodyMedium!.color,
                      ),
                    ),
                  )
                : SizedBox(
                    height: 200,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('workspaces')
                          .doc(workspaceId)
                          .collection('users')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Erreur: ${snapshot.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Center(
                            child: Text(
                              'Aucun utilisateur dans le workspace.',
                              style: GoogleFonts.roboto(
                                fontSize: 16,
                                color: Theme.of(context).textTheme.bodyMedium!.color,
                              ),
                            ),
                          );
                        }

                        final users = snapshot.data!.docs
                            .map((doc) => UserModel.fromFirestore(doc))
                            .toList();

                        return ListView.builder(
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            final user = users[index];
                            return FutureBuilder<Uint8List?>(
                              future: _loadProfileImage(user.photoURL),
                              builder: (context, imageSnapshot) {
                                return ListTile(
                                  leading: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: user.isOnline ? Colors.green : Colors.grey,
                                        width: 2,
                                      ),
                                    ),
                                    child: CircleAvatar(
                                      radius: 20,
                                      backgroundColor: Colors.grey[500],
                                      backgroundImage: imageSnapshot.data != null
                                          ? MemoryImage(imageSnapshot.data!)
                                          : (user.photoURL != null && user.photoURL!.isNotEmpty
                                              ? NetworkImage(user.photoURL!)
                                              : null) as ImageProvider?,
                                      foregroundImage: null,
                                      child: imageSnapshot.data == null &&
                                              (user.photoURL == null || user.photoURL!.isEmpty)
                                          ? Text(
                                              user.displayName.isNotEmpty
                                                  ? user.displayName[0].toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge!
                                                    .color,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                  title: Text(
                                    user.displayName,
                                    style: GoogleFonts.roboto(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).textTheme.bodyLarge!.color,
                                    ),
                                  ),
                                  subtitle: user.isOnline
                                      ? Text(
                                          'En ligne',
                                          style: GoogleFonts.roboto(
                                            color: Colors.green,
                                            fontSize: 12,
                                          ),
                                        )
                                      : StreamBuilder<DocumentSnapshot>(
                                          stream: _firestore
                                              .collection('workspaces')
                                              .doc(workspaceId)
                                              .collection('users')
                                              .doc(user.id)
                                              .snapshots(),
                                          builder: (context, snapshot) {
                                            if (!snapshot.hasData) return const SizedBox.shrink();
                                            final data =
                                                snapshot.data!.data() as Map<String, dynamic>?;
                                            final lastSeen = data?['lastSeen'] as Timestamp?;
                                            if (lastSeen == null) {
                                              return Text(
                                                'Hors ligne',
                                                style: GoogleFonts.roboto(
                                                  color:
                                                      Theme.of(context).textTheme.bodyMedium!.color,
                                                  fontSize: 12,
                                                ),
                                              );
                                            }
                                            final now = DateTime.now();
                                            final lastSeenDate = lastSeen.toDate();
                                            final difference = now.difference(lastSeenDate);

                                            String timeAgo;
                                            if (difference.inMinutes < 60) {
                                              timeAgo = '${difference.inMinutes} min';
                                            } else if (difference.inHours < 24) {
                                              timeAgo = '${difference.inHours} h';
                                            } else {
                                              timeAgo = '${difference.inDays} j';
                                            }

                                            return Text(
                                              'Hors ligne depuis $timeAgo',
                                              style: GoogleFonts.roboto(
                                                color:
                                                    Theme.of(context).textTheme.bodyMedium!.color,
                                                fontSize: 12,
                                              ),
                                            );
                                          },
                                        ),
                                  trailing: Icon(
                                    user.isOnline ? Icons.circle : Icons.circle_outlined,
                                    color: user.isOnline ? Colors.green : Colors.grey[400],
                                    size: 16,
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) => Scaffold(
      
        backgroundColor: themeProvider.themeData.scaffoldBackgroundColor,
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
    // Thème clair / sombre
    IconButton(
      icon: Icon(
        themeProvider.isDarkMode ? Icons.wb_sunny : Icons.nightlight_round,
        color: themeProvider.themeData.iconTheme.color,
      ),
      tooltip: themeProvider.isDarkMode
          ? 'Passer au thème clair'
          : 'Passer au thème sombre',
      onPressed: () => themeProvider.toggleTheme(),
    ),
    // ⚙️ Réglages à côté du soleil/lune
    IconButton(
      icon: Icon(
        Icons.settings,
        color: themeProvider.themeData.iconTheme.color,
      ),
      tooltip: 'Réglages',
      onPressed: _openReconfigureWorkspace,
    ),
    // Déconnexion
    IconButton(
      icon: Icon(
        Icons.logout,
        color: themeProvider.themeData.iconTheme.color,
      ),
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
              if (MediaQuery.of(context).size.width < 600) _buildVoiceChatContainer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: dashboardItems.map((item) => FeatureCard(item: item)).toList(),
            ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<User?>(
            stream: FirebaseAuth.instance.userChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }
              User? user = snapshot.data;
              if (user == null) {
                return const Text('Utilisateur non connecté');
              }
              return kIsWeb
                  ? FutureBuilder<Uint8List?>(
                      future: _loadProfileImage(user.photoURL),
                      builder: (context, imageSnapshot) {
                        return GestureDetector(
                          onTap: _navigateToProfile,
                          child: Column(
                            children: [
                              ProfileAvatar(
                                radius: 30,
                                photoURL: user.photoURL,
                                displayImageBytes: imageSnapshot.data,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                user.displayName ?? 'Utilisateur',
                                style: GoogleFonts.roboto(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).textTheme.bodyLarge!.color,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  : GestureDetector(
                      onTap: _navigateToProfile,
                      child: Column(
                        children: [
                          ProfileAvatar(
                            radius: 30,
                            photoURL: user.photoURL,
                            displayImageBytes: null,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            user.displayName ?? 'Utilisateur',
                            style: GoogleFonts.roboto(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.bodyLarge!.color,
                            ),
                          ),
                        ],
                      ),
                    );
            },
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildUpcomingTasksSection(),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildConnectedUsersSection(),
          ),
          const SizedBox(height: 16),
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
        Container(
          width: 250,
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
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
              StreamBuilder<User?>(
                stream: FirebaseAuth.instance.userChanges(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }
                  User? user = snapshot.data;
                  if (user == null) {
                    return const Text('Utilisateur non connecté');
                  }
return kIsWeb
                      ? FutureBuilder<Uint8List?>(
                          future: _loadProfileImage(user.photoURL),
                          builder: (context, imageSnapshot) {
                            return GestureDetector(
                              onTap: _navigateToProfile,
                              child: Row(
                                children: [
                                  ProfileAvatar(
                                    radius: 30,
                                    photoURL: user.photoURL,
                                    displayImageBytes: imageSnapshot.data,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      user.displayName ?? 'Utilisateur',
                                      style: GoogleFonts.roboto(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).textTheme.bodyLarge!.color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      : GestureDetector(
                          onTap: _navigateToProfile,
                          child: Row(
                            children: [
                              ProfileAvatar(
                                radius: 30,
                                photoURL: user.photoURL,
                                displayImageBytes: null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  user.displayName ?? 'Utilisateur',
                                  style: GoogleFonts.roboto(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).textTheme.bodyLarge!.color,
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
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[800]
                      : Colors.grey[100],
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
                          backgroundColor: _isListening
                              ? Colors.redAccent
                              : Theme.of(context).iconTheme.color,
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
                        color: _isTtsEnabled
                            ? Colors.blueAccent
                            : Theme.of(context).iconTheme.color,
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
                      icon: Icon(
                        Icons.settings_voice,
                        color: Theme.of(context).iconTheme.color,
                      ),
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
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildChatAssistantSection(),
                ),
              ),
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 16.0, right: 16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _buildUpcomingTasksSection(),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        flex: 3,
                        child: _buildConnectedUsersSection(),
                      ),
                      const SizedBox(height: 16),
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
                color: Theme.of(context).cardColor.withOpacity(0.95),
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
                        backgroundColor: _isListening
                            ? Colors.redAccent
                            : Theme.of(context).iconTheme.color,
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
                      color: _isTtsEnabled
                          ? Colors.blueAccent
                          : Theme.of(context).iconTheme.color,
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
                    icon: Icon(
                      Icons.settings_voice,
                      color: Theme.of(context).iconTheme.color,
                    ),
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
            color: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      widget.item.icon,
                      size: 30,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.item.title,
                        style: GoogleFonts.roboto(
                          textStyle: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).textTheme.bodyLarge!.color,
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

// Ajout du champ photoURL dans UserModel
class UserModel {
  final String id;
  final String displayName;
  final bool isOnline;
  final String? photoURL; // Nouveau champ pour la photo de profil

  UserModel({
    required this.id,
    required this.displayName,
    required this.isOnline,
    this.photoURL,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      displayName: data['displayName'] ?? 'Utilisateur',
      isOnline: data['isOnline'] ?? false,
      photoURL: data['photoURL'],
    );
  }
}
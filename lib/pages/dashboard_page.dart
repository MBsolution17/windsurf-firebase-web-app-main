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
// Importez d'autres pages nécessaires ici, par exemple:
// import 'friends_page.dart';
// import 'task_tracker_page.dart';
// import 'documents_page.dart';
// import 'analytics_page.dart';
// import 'channel_list_page.dart';

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
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late AIService _aiService;
  late WebSpeechRecognitionService _speechService;
  final TextEditingController _chatController = TextEditingController();

  bool _isListening = false;

  // Variables Déclarées
  List<Folder> _folders = [];
  List<String> _downloadingFolders = [];
  Folder? _selectedFolder;
  List<Map<String, dynamic>> _documents = [];

  // Formulaire d'ajout de contact
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController  = TextEditingController();
  final TextEditingController _emailController     = TextEditingController();
  final TextEditingController _phoneController     = TextEditingController();
  final TextEditingController _addressController   = TextEditingController();
  final TextEditingController _companyController   = TextEditingController();
  final TextEditingController _externalInfoController = TextEditingController();

  String? _selectedFolderId;

  List<Contact> _availableContacts = [];

  // Calendrier
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Task>> _tasksByDate = {};

  // Palette de Couleurs Douces
  final Color primaryColor = Colors.grey[800]!; // Gris Foncé
  final Color secondaryColor1 = Colors.grey[600]!; // Gris Moyen
  final Color secondaryColor2 = Colors.black87; // Noir Sombre
  final Color neutralLight = Colors.grey[200]!; // Gris Très Clair pour fond
  final Color neutralDark = Colors.grey[800]!; // Gris Foncé pour textes et éléments

  // Liste des fonctionnalités avec leurs icônes et routes
  final List<DashboardItem> dashboardItems = [
    DashboardItem(
      title: 'Channels',
      icon: Icons.chat,
      routeName: '/channel_list',
      color: Colors.grey[600]!, // Gris Moyen
    ),
    DashboardItem(
      title: 'Friends',
      icon: Icons.people,
      routeName: '/friends',
      color: Colors.grey[600]!, // Gris Moyen
    ),
    DashboardItem(
      title: 'Calendar',
      icon: Icons.calendar_today,
      routeName: '/calendar',
      color: Colors.grey[600]!, // Gris Moyen
    ),
    DashboardItem(
      title: 'Task Tracker',
      icon: Icons.check_circle,
      routeName: '/task_tracker',
      color: Colors.grey[600]!, // Gris Moyen
    ),
    DashboardItem(
      title: 'Documents',
      icon: Icons.folder,
      routeName: '/documents',
      color: Colors.grey[600]!, // Gris Moyen
    ),
    DashboardItem(
      title: 'Analytics',
      icon: Icons.analytics,
      routeName: '/analytics',
      color: Colors.grey[600]!, // Gris Moyen
    ),
    DashboardItem(
      title: 'Contacts',
      icon: Icons.contact_mail,
      routeName: '/contact_page',
      color: Colors.grey[600]!, // Gris Moyen
    ),
    // Vous pouvez ajouter d'autres éléments ici si nécessaire
  ];

  late AnimationController _animationController;
  late Animation<double> _animation;

  // FocusNode pour le TextField
  final FocusNode _chatFocusNode = FocusNode();

  // ScrollController pour le chat
  final ScrollController _scrollController = ScrollController();

  // Variables pour l'assistant vocal intégré
  String _aiResponse = '';
  String _lastError = '';

  // Instance d'AudioPlayer
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isTtsEnabled = false; // État pour activer/désactiver la lecture vocale

  // Variables pour la personnalisation de la voix
  List<html.SpeechSynthesisVoice> _availableVoices = [];
  html.SpeechSynthesisVoice? _selectedVoice; // Pour le web
  String _selectedVoiceName = 'fr-FR-Wavenet-D'; // Pour mobile
  double _selectedSpeakingRate = 1.2; // Taux de parole
  double _selectedPitch = 1.2; // Hauteur (pitch) - Optionnel pour le web

  // Clés pour SharedPreferences
  static const String prefSelectedVoiceName = 'selectedVoiceName';
  static const String prefSelectedVoiceId = 'selectedVoiceId';

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _focusedDay = DateTime.now();
    _calendarFormat = CalendarFormat.month;
    _fetchAllTasks();
    _fetchAllFolders(); // Méthode pour récupérer les dossiers
    _fetchAvailableContacts(); // Récupérer les contacts disponibles

    // Initialiser le service de reconnaissance vocale via Provider
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _aiService = Provider.of<AIService>(context, listen: false);
      _speechService = Provider.of<WebSpeechRecognitionService>(context, listen: false);
      bool available = await _speechService.initialize();
      if (available) {
        print('Speech recognition available');
      } else {
        print('Speech recognition not available');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('La reconnaissance vocale n\'est pas disponible.')),
        );
      }

      // Charger les voix disponibles si on est sur le web
      if (kIsWeb) {
        final synth = html.window.speechSynthesis;

        // Ajouter un écouteur pour les changements de voix
        synth?.addEventListener('voiceschanged', (event) {
          setState(() {
            _availableVoices = synth!.getVoices()
                .where((voice) => voice.lang?.startsWith('fr-FR') ?? false) // Filtrer pour le français de France
                .toList();
          });
          _loadSavedVoice(); // Charger la voix sauvegardée après le chargement des voix
        });

        // Initialiser les voix disponibles
        setState(() {
          _availableVoices = synth!.getVoices()
              .where((voice) => voice.lang?.startsWith('fr-FR') ?? false) // Filtrer pour le français de France
              .toList();
        });

        // Optionnel : Imprimer les voix disponibles pour les identifier
        _availableVoices.forEach((voice) {
          print('Voix disponible: ${voice.name} (${voice.lang})');
        });

        _loadSavedVoice(); // Charger la voix sauvegardée initialement
      } else {
        // Sur mobile, charger la voix sauvegardée
        _loadSavedVoice();
      }
    });

    // Définir les callbacks via les setters
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speechService.onResult = (transcript) async {
        setState(() {
          _isListening = false;
          _lastError = '';
          _aiResponse = 'En attente de la réponse de l\'IA...';
        });
        print('Texte reconnu : $transcript');

        // Envoyer le texte reconnu à l'AI Service
        try {
          ChatMessage aiMessage = await _aiService.sendMessage(transcript);
          String responseContent = aiMessage.content;
          setState(() {
            _aiResponse = responseContent;
          });
          print('Réponse de l\'IA : $responseContent');

          // Lire la réponse IA si la lecture vocale est activée
          if (_isTtsEnabled) {
            await _speak(responseContent); // Utiliser la méthode _speak corrigée
          }
        } catch (e) {
          setState(() {
            _aiResponse = 'Erreur lors de la communication avec l\'IA.';
          });
          print('Erreur lors de l\'envoi du message à l\'IA : $e');
        }
      };

      _speechService.onError = (error) {
        setState(() {
          _lastError = error;
          _isListening = false;
          _aiResponse = '';
        });
        print('Erreur de reconnaissance vocale : $error');
      };
    });

    // Initialiser l'AnimationController
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Définir l'animation de pulsation (scale)
    _animation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    // Écouteur pour le FocusNode
    _chatFocusNode.addListener(() {
      if (!_chatFocusNode.hasFocus && _isListening) {
        _toggleAssistantListening();
      }
    });
  }

  @override
  void dispose() {
    _stopSpeaking(); // Arrêter toute lecture en cours
    _audioPlayer.dispose(); // Dispose de l'audio player
    _animationController.dispose();
    _chatController.dispose();
    _chatFocusNode.dispose(); // Dispose du FocusNode
    _scrollController.dispose(); // Dispose du ScrollController
    super.dispose();
  }

  /// Méthode pour charger la voix sauvegardée depuis SharedPreferences
  void _loadSavedVoice() async {
    final prefs = await SharedPreferences.getInstance();

    if (kIsWeb) {
      String? savedVoiceName = prefs.getString(prefSelectedVoiceName);
      if (savedVoiceName != null && _availableVoices.isNotEmpty) {
        // Trouver la voix avec le nom sauvegardé ou utiliser la première voix disponible
        final voice = _availableVoices.firstWhere(
          (voice) => voice.name == savedVoiceName,
          orElse: () => _availableVoices.first,
        );
        setState(() {
          _selectedVoice = voice;
          print('Voix sauvegardée: ${voice.name}');
        });
      } else if (_availableVoices.isNotEmpty) {
        // Si aucun nom sauvegardé ou la voix sauvegardée n'existe pas, utiliser la première voix
        setState(() {
          _selectedVoice = _availableVoices.first;
          print('Voix par défaut définie: ${_selectedVoice!.name}');
        });
      } else {
        // Si aucune voix n'est disponible
        setState(() {
          _selectedVoice = null;
        });
        print('Aucune voix disponible.');
      }
    } else {
      String? savedVoiceName = prefs.getString(prefSelectedVoiceName);
      if (savedVoiceName != null) {
        setState(() {
          _selectedVoiceName = savedVoiceName;
          print('Voix mobile sauvegardée: $_selectedVoiceName');
        });
      }
    }
  }

  /// Méthode pour sauvegarder la voix sélectionnée dans SharedPreferences
  void _saveVoiceSelection() async {
    final prefs = await SharedPreferences.getInstance();
    if (kIsWeb) {
      if (_selectedVoice != null) {
        await prefs.setString(prefSelectedVoiceName, _selectedVoice!.name!);
        print('Voix sauvegardée: ${_selectedVoice!.name}');
      }
    } else {
      await prefs.setString(prefSelectedVoiceName, _selectedVoiceName);
      print('Voix mobile sauvegardée: $_selectedVoiceName');
    }
  }

  /// Méthode pour parler, utilisant Google Text-to-Speech via Cloud Functions sur mobile et Web Speech API sur le web
  Future<void> _speak(String text) async {
    if (!_isTtsEnabled) return; // Ne rien faire si TTS est désactivé

    if (kIsWeb) {
      _speakWeb(text);
    } else {
      try {
        HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('synthesizeSpeech');
        final results = await callable.call(<String, dynamic>{
          'text': text,
          'languageCode': 'fr-FR', // Langue
          'voiceName': _selectedVoiceName, // Voix sélectionnée pour mobile
          'speakingRate': _selectedSpeakingRate, // Taux de parole sélectionné
        });
        String audioBase64 = results.data['audioContent'];
        Uint8List audioBytes = base64Decode(audioBase64);

        // Jouer l'audio avec audioplayers
        await _audioPlayer.play(BytesSource(audioBytes));
      } catch (e) {
        print('Erreur lors de la synthèse vocale: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la synthèse vocale.')),
        );
      }
    }
  }

  /// Méthode pour arrêter la lecture vocale
  Future<void> _stopSpeaking() async {
    if (kIsWeb) {
      html.window.speechSynthesis?.cancel();
    } else {
      await _audioPlayer.stop();
    }
  }

  /// Méthode spécifique au web pour utiliser Web Speech API
  void _speakWeb(String text) {
    final synth = html.window.speechSynthesis;

    // Annuler toute parole en cours
    if (synth?.speaking ?? false) {
      synth?.cancel();
    }

    final utterance = html.SpeechSynthesisUtterance(text)
      ..lang = 'fr-FR'
      ..rate = _selectedSpeakingRate
      ..pitch = _selectedPitch
      ..voice = _selectedVoice;

    print('Synthèse vocale avec la voix: ${_selectedVoice?.name ?? 'Voix par défaut'}');

    synth?.speak(utterance);
  }

  /// Méthode pour envoyer un message
  Future<void> _sendMessage(String message) async {
    try {
      // Envoi du message via AIService
      ChatMessage aiMessage = await _aiService.sendMessage(message);
      String aiResponse = aiMessage.content;
      print('Réponse de l\'IA: $aiResponse');

      // Optionnel : Effacer le champ de texte après l'envoi
      setState(() {
        _chatController.clear();
        _aiResponse = aiResponse;
      });

      // Lire la réponse IA si la lecture vocale est activée
      if (_isTtsEnabled) {
        await _speak(aiResponse); // Utiliser la méthode _speak corrigée
      }
    } catch (e) {
      // Gestion des erreurs : Afficher un message d'erreur à l'utilisateur
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'envoi du message: $e')),
      );
      print('Erreur lors de l\'envoi du message: $e');
    }
  }

  /// Méthode pour basculer l'écoute de l'assistant vocal
  void _toggleAssistantListening() {
    if (_isListening) {
      print('Arrêt de la reconnaissance vocale...');
      _speechService.stopListening();
      _animationController.stop(); // Arrêter l'animation
      _animationController.reset(); // Réinitialiser l'animation
      setState(() {
        _isListening = false;
      });
    } else {
      print('Démarrage de la reconnaissance vocale...');
      _speechService.startListening();
      _animationController.repeat(reverse: true); // Démarrer l'animation
      setState(() {
        _isListening = true;
      });
    }
  }

  /// Méthode pour récupérer toutes les tâches et les organiser par date
  Future<void> _fetchAllTasks() async {
    try {
      // Vérifier si un utilisateur est connecté
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        // Si aucun utilisateur n'est connecté, définir une liste de tâches vide
        if (mounted) {
          setState(() {
            _tasksByDate = {};
          });
        }
        return;
      }

      QuerySnapshot snapshot = await _firestore
          .collection('tasks')
          .where('userId', isEqualTo: currentUser.uid)
          .orderBy('dueDate')
          .get();

      Map<DateTime, List<Task>> tasksMap = {};

      for (var doc in snapshot.docs) {
        Task task = Task.fromFirestore(doc);
        DateTime date =
            DateTime(task.dueDate.year, task.dueDate.month, task.dueDate.day);
        if (tasksMap[date] == null) {
          tasksMap[date] = [];
        }
        tasksMap[date]!.add(task);
      }

      // Vérifier si le widget est toujours monté avant d'appeler setState
      if (mounted) {
        setState(() {
          _tasksByDate = tasksMap;
        });
      }
    } catch (e) {
      print('Erreur lors de la récupération des tâches: $e');
      // Gérer l'erreur de manière appropriée, peut-être afficher un message à l'utilisateur
      if (mounted) {
        setState(() {
          _tasksByDate = {};
        });
      }
    }
  }

  /// Méthode pour récupérer tous les dossiers
  Future<void> _fetchAllFolders() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        if (mounted) {
          setState(() {
            _folders = [];
          });
        }
        return;
      }

      QuerySnapshot snapshot = await _firestore
          .collection('folders')
          .where('userId', isEqualTo: currentUser.uid)
          .orderBy('timestamp', descending: true)
          .get();

      List<Folder> folders =
          snapshot.docs.map((doc) => Folder.fromFirestore(doc)).toList();

      if (mounted) {
        setState(() {
          _folders = folders;
        });
      }
    } catch (e) {
      print('Erreur lors de la récupération des dossiers: $e');
      if (mounted) {
        setState(() {
          _folders = [];
        });
      }
    }
  }

  /// Méthode pour récupérer les contacts disponibles
  Future<void> _fetchAvailableContacts() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _availableContacts = [];
        });
        return;
      }

      QuerySnapshot snapshot = await _firestore
          .collection('contacts')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      List<Contact> contacts =
          snapshot.docs.map((doc) => Contact.fromFirestore(doc)).toList();

      setState(() {
        _availableContacts = contacts;
      });
    } catch (e) {
      print('Erreur lors de la récupération des contacts disponibles: $e');
      setState(() {
        _availableContacts = [];
      });
    }
  }

  /// Méthode pour récupérer les documents d'un dossier
  Future<void> _fetchDocuments(String folderId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('documents')
          .where('folderId', isEqualTo: folderId)
          .orderBy('timestamp', descending: true)
          .get();

      List<Map<String, dynamic>> documents =
          snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

      if (mounted) {
        setState(() {
          _documents = documents;
        });
      }
    } catch (e) {
      print('Erreur lors de la récupération des documents: $e');
      if (mounted) {
        setState(() {
          _documents = [];
        });
      }
    }
  }

  /// Fonction pour obtenir la couleur du statut
  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.ToDo:
        return Colors.blueGrey[600]!;
      case TaskStatus.InProgress:
        return Colors.blueGrey[400]!;
      case TaskStatus.Done:
        return Colors.blueGrey[200]!;
      default:
        return Colors.grey;
    }
  }

  /// Fonction pour obtenir la couleur de la priorité
  Color _getPriorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.Low:
        return Colors.blueGrey[300]!;
      case TaskPriority.Medium:
        return Colors.blueGrey[400]!;
      case TaskPriority.High:
        return Colors.blueGrey[500]!;
      default:
        return Colors.grey;
    }
  }

  /// Widget pour afficher chaque tâche dans le calendrier
  Widget _buildCalendarTaskCard(Task task) {
    Color priorityColor;
    switch (task.priority) {
      case TaskPriority.Low:
        priorityColor = Colors.blueGrey[300]!;
        break;
      case TaskPriority.Medium:
        priorityColor = Colors.blueGrey[400]!;
        break;
      case TaskPriority.High:
        priorityColor = Colors.blueGrey[500]!;
        break;
      default:
        priorityColor = Colors.grey;
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      color: Colors.white, // Revenir au fond blanc pour les tâches
      child: ListTile(
        title: Text(
          task.title,
          style: GoogleFonts.roboto(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87, // Texte noir foncé
          ),
        ),
        subtitle: Text(
          task.description,
          style: GoogleFonts.roboto(
            fontSize: 14,
            color: Colors.black54, // Texte gris foncé
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Statut
            Chip(
              label: Text(
                task.status.toString().split('.').last,
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: _getStatusColor(task.status),
            ),
            const SizedBox(height: 4),
            // Priorité
            Chip(
              label: Text(
                task.priority.toString().split('.').last,
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: _getPriorityColor(task.priority),
              avatar: CircleAvatar(
                backgroundColor: Colors.white,
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
                SizedBox(height: 8),
                Text(
                    'Assigné à: ${task.assignee.isNotEmpty ? task.assignee : 'Non assigné'}'),
                SizedBox(height: 8),
                Text(
                    'Échéance: ${DateFormat('dd/MM/yyyy').format(task.dueDate)}'),
                SizedBox(height: 8),
                Text('Statut: ${task.status.toString().split('.').last}'),
                SizedBox(height: 8),
                Text(
                    'Priorité: ${task.priority.toString().split('.').last}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text('Fermer'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  /// Widget pour afficher la liste des dossiers avec boutons de téléchargement
  Widget _buildFolderList() {
    if (_folders.isEmpty) {
      return Center(
          child: Text('Aucun dossier trouvé',
              style: GoogleFonts.roboto(
                  fontSize: 16, color: Colors.grey[700])));
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        final isDownloading = _downloadingFolders.contains(folder.id);
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          color: Colors.white, // Revenir au fond blanc pour les dossiers
          child: ListTile(
            leading: Icon(Icons.folder, color: Colors.grey[800], size: 30),
            title: Text(folder.name,
                style: GoogleFonts.roboto(
                    fontWeight: FontWeight.bold, color: Colors.black87)),
            subtitle: Text(
              'Créé le: ${DateFormat('dd/MM/yyyy').format(folder.timestamp)}',
              style: GoogleFonts.roboto(
                  fontSize: 14, color: Colors.grey[600]),
            ),
            trailing: isDownloading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      color: Colors.grey[800],
                    ),
                  )
                : IconButton(
                    icon: Icon(Icons.download, color: Colors.grey[800]),
                    tooltip: 'Télécharger le dossier',
                    onPressed: () {
                      _downloadFolder(folder);
                    },
                  ),
            onTap: () {
              setState(() {
                _selectedFolder = folder;
                _documents = []; // Réinitialiser la liste des documents
                _fetchDocuments(folder.id);
              });
            },
          ),
        );
      },
    );
  }

  /// Widget pour afficher la liste des documents dans un dossier
  Widget _buildDocumentList() {
    if (_documents.isEmpty) {
      return Center(
          child: Text('Aucun document trouvé dans ce dossier',
              style: GoogleFonts.roboto(
                  fontSize: 16, color: Colors.grey[700])));
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: _documents.length,
      itemBuilder: (context, index) {
        final doc = _documents[index];
        final title = doc['title'] ?? 'Sans titre';
        final type = doc['type'] ?? 'pdf';
        final url = doc['url'] ?? '';

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          color: Colors.white, // Revenir au fond blanc pour les documents
          child: ListTile(
            leading: Icon(
              type == 'pdf'
                  ? Icons.picture_as_pdf
                  : type == 'txt'
                      ? Icons.description
                      : Icons.insert_drive_file,
              color: Colors.grey[800],
              size: 30,
            ),
            title: Text(title,
                style: GoogleFonts.roboto(
                    fontWeight: FontWeight.bold, color: Colors.black87)),
            subtitle: Text('Type: ${type.toUpperCase()}',
                style: GoogleFonts.roboto(
                    fontSize: 14, color: Colors.grey[600])),
            trailing: IconButton(
              icon: Icon(Icons.download, color: Colors.grey[800]),
              onPressed: () {
                if (url.isNotEmpty) {
                  // Ouvrir le lien directement pour le téléchargement
                  final anchor = html.AnchorElement(href: url)
                    ..setAttribute("download", '$title.$type')
                    ..click();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fichier téléchargé avec succès')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('URL du fichier manquante.')),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }

  /// Méthode pour créer un nouveau dossier avec association de contacts
  Future<void> _createFolder(String name, List<String> contactIds) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      DocumentReference folderRef = await _firestore.collection('folders').add({
        'name': name,
        'userId': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint('Dossier "$name" créé avec succès.');

      String newFolderId = folderRef.id;

      if (contactIds.isNotEmpty) {
        WriteBatch batch = _firestore.batch();

        for (String contactId in contactIds) {
          DocumentReference contactRef = _firestore.collection('contacts').doc(contactId);
          batch.update(contactRef, {'folderId': newFolderId});
        }

        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dossier créé avec succès')),
        );
        _fetchAllFolders(); // Rafraîchir la liste des dossiers
      }
    } catch (e) {
      debugPrint('Erreur lors de la création du dossier: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la création du dossier')),
        );
      }
    }
  }

  /// Méthode pour soumettre le formulaire et ajouter un contact
  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      // Récupérer les données du formulaire
      String firstName = _firstNameController.text.trim();
      String lastName = _lastNameController.text.trim();
      String email = _emailController.text.trim();
      String phone = _phoneController.text.trim();
      String address = _addressController.text.trim();
      String company = _companyController.text.trim();
      String externalInfo = _externalInfoController.text.trim();

      // Récupérer l'ID de l'utilisateur actuel
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Utilisateur non authentifié')),
        );
        return;
      }

      // Créer un objet Contact avec des champs optionnels
      Contact newContact = Contact(
        id: '', // L'ID sera généré par Firestore
        userId: currentUser.uid, // Ajout du userId
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        address: address,
        company: company,
        externalInfo: externalInfo,
        folderId: _selectedFolderId ?? '', // Assurez-vous que folderId est non null
        timestamp: DateTime.now(), // Correction ici
      );

      try {
        // Ajouter le contact à Firestore
        await _firestore.collection('contacts').add(newContact.toMap());

        // Afficher un message de succès
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Contact ajouté avec succès')),
        );

        // Réinitialiser le formulaire
        _formKey.currentState!.reset();
        setState(() {
          _selectedFolderId = null;
        });
      } catch (e) {
        // Afficher un message d'erreur
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'ajout du contact')),
        );
        print('Erreur lors de l\'ajout du contact: $e');
      }
    }
  }

  /// Afficher un dialogue pour créer un nouveau dossier avec sélection de contacts
  void _showCreateFolderDialog() {
    String folderName = '';
    List<String> selectedContactIds = [];

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('Créer un Dossier'),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Champ pour entrer le nom du dossier
                TextField(
                  decoration: const InputDecoration(hintText: 'Nom du dossier'),
                  onChanged: (value) {
                    folderName = value;
                  },
                ),
                const SizedBox(height: 20),

                // Section pour sélectionner des contacts
                const Text(
                  'Associer des Contacts (Optionnel)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                // Liste des contacts avec des contraintes explicites
                Expanded(
                  child: _availableContacts.isNotEmpty
                      ? ListView.builder(
                          itemCount: _availableContacts.length,
                          itemBuilder: (context, index) {
                            final contact = _availableContacts[index];
                            return CheckboxListTile(
                              title: Text('${contact.firstName} ${contact.lastName}'),
                              value: selectedContactIds.contains(contact.id),
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    selectedContactIds.add(contact.id);
                                  } else {
                                    selectedContactIds.remove(contact.id);
                                  }
                                });
                              },
                            );
                          },
                        )
                      : const Text('Aucun contact disponible.'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (folderName.trim().isNotEmpty) {
                  _createFolder(folderName.trim(), selectedContactIds);
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Veuillez entrer un nom de dossier')),
                  );
                }
              },
              child: const Text('Créer'),
            ),
          ],
        );
      },
    );
  }

  /// Afficher un dialogue pour supprimer un contact
  Future<void> _deleteContact(String contactId) async {
    try {
      await _firestore.collection('contacts').doc(contactId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contact supprimé avec succès')),
      );
      _fetchAvailableContacts(); // Rafraîchir la liste des contacts
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression du contact')),
      );
      print('Erreur lors de la suppression du contact: $e');
    }
  }

  /// Afficher les détails du contact dans une boîte de dialogue
  void _showContactDetails(Contact contact) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('${contact.firstName} ${contact.lastName}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contact.email.isNotEmpty)
                  Text('Email: ${contact.email}'),
                SizedBox(height: 8),
                if (contact.phone.isNotEmpty)
                  Text('Téléphone: ${contact.phone}'),
                SizedBox(height: 8),
                if (contact.address.isNotEmpty)
                  Text('Adresse: ${contact.address}'),
                SizedBox(height: 8),
                if (contact.company.isNotEmpty)
                  Text('Entreprise: ${contact.company}'),
                SizedBox(height: 8),
                if (contact.externalInfo.isNotEmpty)
                  Text('Informations Externes: ${contact.externalInfo}'),
                SizedBox(height: 8),
                if (contact.folderId.isNotEmpty)
                  FutureBuilder<DocumentSnapshot>(
                    future: _firestore.collection('folders').doc(contact.folderId).get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Text('Dossier: Chargement...');
                      }
                      if (snapshot.hasError || !snapshot.data!.exists) {
                        return Text('Dossier: Inconnu');
                      }
                      final folder = Folder.fromFirestore(snapshot.data!);
                      return Text('Dossier: ${folder.name}');
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text('Fermer'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  /// Widget pour afficher la liste des contacts existants
  Widget _buildContactList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('contacts')
          .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Erreur: ${snapshot.error}',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'Aucun contact trouvé.',
              style: GoogleFonts.roboto(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          );
        }

        final contacts = snapshot.data!.docs.map((doc) => Contact.fromFirestore(doc)).toList();

        return ListView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: contacts.length,
          itemBuilder: (context, index) {
            final contact = contacts[index];
            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 6.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              color: Colors.white, // Revenir au fond blanc pour les contacts
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo[800],
                  child: Text(
                    contact.firstName.isNotEmpty
                        ? contact.firstName[0].toUpperCase()
                        : '?',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(
                  '${contact.firstName} ${contact.lastName}',
                  style: GoogleFonts.roboto(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (contact.email.isNotEmpty)
                      Text('Email: ${contact.email}'),
                    if (contact.phone.isNotEmpty)
                      Text('Téléphone: ${contact.phone}'),
                    if (contact.company.isNotEmpty)
                      Text('Entreprise: ${contact.company}'),
                    if (contact.folderId.isNotEmpty)
                      FutureBuilder<DocumentSnapshot>(
                        future: _firestore.collection('folders').doc(contact.folderId).get(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Text('Dossier: Chargement...');
                          }
                          if (snapshot.hasError || !snapshot.data!.exists) {
                            return Text('Dossier: Inconnu');
                          }
                          final folder = Folder.fromFirestore(snapshot.data!);
                          return Text('Dossier: ${folder.name}');
                        },
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('Confirmer la suppression'),
                            content: Text('Êtes-vous sûr de vouloir supprimer ce contact?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text('Annuler'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _deleteContact(contact.id);
                                },
                                child: Text('Supprimer'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.info_outline, color: Colors.blue),
                      onPressed: () {
                        _showContactDetails(contact);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Méthode pour télécharger un fichier
  Future<void> _downloadFile(String url, String fileName, String type) async {
    try {
      // Ouvrir le lien directement pour le téléchargement
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", '$fileName.$type')
        ..click();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fichier téléchargé avec succès')),
      );
    } catch (e) {
      debugPrint('Erreur lors du téléchargement du fichier: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du téléchargement du fichier')),
      );
    }
  }

  /// Fonction pour télécharger le dossier complet avec archive
  Future<void> _downloadFolder(Folder folder) async {
    setState(() {
      _downloadingFolders.add(folder.id);
    });

    try {
      // Récupérer tous les documents du dossier
      QuerySnapshot snapshot = await _firestore
          .collection('documents')
          .where('folderId', isEqualTo: folder.id)
          .get();

      if (snapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Le dossier est vide. Aucun fichier à télécharger.')),
        );
        return;
      }

      // Créer une archive ZIP
      Archive archive = Archive();

      for (var doc in snapshot.docs) {
        String url = doc['url'] ?? '';
        String title = doc['title'] ?? 'Sans titre';
        String type = doc['type'] ?? 'pdf';

        if (url.isEmpty) continue;

        // Télécharger le fichier
        http.Response response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          List<int> bytes = response.bodyBytes;

          // Déterminer le nom du fichier avec extension
          String fileName = '$title.${type == 'pdf' ? 'pdf' : 'txt'}';

          // Ajouter le fichier à l'archive
          archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
        } else {
          debugPrint('Erreur lors du téléchargement du fichier: $url');
        }
      }

      // Encoder l'archive en bytes ZIP
      List<int> zipData = ZipEncoder().encode(archive)!;
      Uint8List zipBytes = Uint8List.fromList(zipData);

      // Créer un blob à partir des bytes ZIP
      final blob = html.Blob([zipBytes], 'application/zip');

      // Créer un URL pour le blob
      final urlObject = html.Url.createObjectUrlFromBlob(blob);

      // Créer un élément <a> pour déclencher le téléchargement
      final anchor = html.AnchorElement(href: urlObject)
        ..setAttribute("download", '${folder.name}.zip')
        ..click();

      // Libérer l'URL du blob
      html.Url.revokeObjectUrl(urlObject);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('Dossier "${folder.name}" téléchargé avec succès.')),
      );
    } catch (e) {
      debugPrint('Erreur lors du téléchargement du dossier: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du téléchargement du dossier.')),
      );
    } finally {
      setState(() {
        _downloadingFolders.remove(folder.id);
      });
    }
  }

  /// Méthode pour générer un document via l'IA
  Future<void> _generateDocument(String title, String content) async {
    // Enregistrer votre méthode unique ici
    // Par exemple, si vous souhaitez implémenter la génération de PDF, gardez une seule définition
    final enrichedContent = content;

    // Créer un PDF
    await _createPDFDocument(title, enrichedContent);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Document généré avec succès')),
    );
  }

  /// Méthode pour créer un document PDF
  Future<void> _createPDFDocument(String title, String content) async {
    // Implémentez la logique de création PDF ici
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Création de PDF pour "$title"')),
    );
  }

  /// Section des tâches à venir
  Widget _buildUpcomingTasksSection() {
    // Récupérer toutes les tâches et les trier par date
    List<Task> upcomingTasks = _tasksByDate.values
        .expand((tasks) => tasks)
        .where((task) =>
            task.dueDate.isAfter(DateTime.now()) &&
            task.status != TaskStatus.Done)
        .toList();

    // Trier par date croissante (les plus proches en premier)
    upcomingTasks.sort((a, b) => a.dueDate.compareTo(b.dueDate));

    // Limiter à 5 tâches les plus proches
    upcomingTasks = upcomingTasks.take(5).toList();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Colors.white, // Revenir au fond blanc pour les tâches
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titre et bouton
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
                    // Navigation vers la page de suivi des tâches
                    Navigator.pushNamed(context, '/task_tracker');
                  },
                  child: Text(
                    'Voir Tout',
                    style: GoogleFonts.roboto(
                      color: primaryColor,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Afficher un message si aucune tâche n'est disponible
            upcomingTasks.isEmpty
                ? Center(
                    child: Text(
                      'Aucune tâche à venir',
                      style: GoogleFonts.roboto(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      // Prochaine tâche mise en évidence
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
                              offset: Offset(0, 3),
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
                                color:
                                    _getStatusColor(upcomingTasks.first.status),
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
                      // Liste des autres tâches avec scroll limité
                      Container(
                        height: 150, // Limitez la hauteur pour éviter l'overflow
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: upcomingTasks.length > 1
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

  /// Section de l'assistant de chat IA intégrée directement sur la page
  Widget _buildChatAssistantSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Colors.white, // Fond blanc pour l'assistant IA
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Titre de la section
            Text(
              'Assistant IA',
              style: GoogleFonts.roboto(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: neutralDark,
              ),
            ),
            const SizedBox(height: 10),
            // Liste des messages
            Expanded(
              child: StreamBuilder<List<ChatMessage>>(
                stream: _aiService.getChatHistory(),
                builder: (context, snapshot) {
                  print(
                      'StreamBuilder: ConnectionState - ${snapshot.connectionState}');
                  if (snapshot.hasError) {
                    print('StreamBuilder Error: ${snapshot.error}');
                    return Center(
                      child: Text(
                        'Erreur: ${snapshot.error}',
                        style: TextStyle(color: Colors.red),
                      ),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    print('StreamBuilder: No data available');
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

                  final messages = snapshot.data!;
                  print('StreamBuilder: Received ${messages.length} messages');

                  // Faire défiler vers le bas lorsque de nouveaux messages sont ajoutés
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        _scrollController.position.minScrollExtent,
                        duration: Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  });

                  return ListView.builder(
                    reverse: true, // Les messages les plus récents en bas
                    controller: _scrollController,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return Align(
                        alignment: message.type == MessageType.user
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: EdgeInsets.all(8),
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: message.type == MessageType.user
                                ? Colors.blue[200]
                                : Colors.grey[300],
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Column(
                            crossAxisAlignment: message.type == MessageType.user
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                message.content,
                                style: GoogleFonts.roboto(
                                  color: Colors.black87,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(height: 4),
                              // Affichage du statut du message
                              Text(
                                'Statut: ${message.status.toString().split('.').last}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                              // Boutons de validation si le message est en attente
                              if (message.status == MessageStatus.pending_validation)
                                Row(
                                  mainAxisAlignment: message.type == MessageType.user
                                      ? MainAxisAlignment.end
                                      : MainAxisAlignment.start,
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        // Rejeter le message
                                        _aiService.handleValidation(message.id, MessageStatus.rejected);
                                      },
                                      child: Text('Rejeter'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () {
                                        // Valider le message
                                        _aiService.handleValidation(message.id, MessageStatus.validated);
                                      },
                                      child: Text('Valider'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              // Bouton "Modifier" pour les messages utilisateur et AI
                              if (message.type == MessageType.user || message.type == MessageType.ai)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      if (message.type == MessageType.ai) {
                                        // Limiter la modification au contenu seulement pour les messages AI
                                        _showEditMessageDialog(message, isAIMessage: true);
                                      } else {
                                        _showEditMessageDialog(message);
                                      }
                                    },
                                    icon: Icon(Icons.edit, size: 16, color: Colors.black54),
                                    label: Text(
                                      'Modifier',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
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
            // Zone de saisie avec microphone et bouton de lecture vocale
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    focusNode:
                        _chatFocusNode, // Assignation du FocusNode
                    decoration: InputDecoration(
                      hintText: 'Posez votre question...',
                      filled: true,
                      fillColor: Colors.grey[200],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide:
                            BorderSide(color: Colors.grey[400]!),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 16.0,
                      ),
                    ),
                    style: TextStyle(color: Colors.black87),
                    onSubmitted: (value) async {
                      if (value.isNotEmpty) {
                        await _sendMessage(value);
                      }
                    },
                  ),
                ),
                SizedBox(width: 8),
                GestureDetector(
                  onTap: _toggleAssistantListening,
                  child: ScaleTransition(
                    scale: _animation,
                    child: CircleAvatar(
                      backgroundColor:
                          _isListening ? Colors.redAccent : Colors.grey[400],
                      child: Icon(
                        _isListening ? Icons.mic_off : Icons.mic,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                // Bouton de lecture vocale (casque)
                IconButton(
                  icon: Icon(
                    _isTtsEnabled ? Icons.headset : Icons.headset_off,
                    color: _isTtsEnabled ? Colors.blueAccent : Colors.grey,
                  ),
                  tooltip: _isTtsEnabled
                      ? 'Désactiver la lecture vocale'
                      : 'Activer la lecture vocale',
                  onPressed: () {
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
                SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.grey[400],
                  child: IconButton(
                    icon: Icon(Icons.send, color: Colors.white),
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

  /// Méthode pour afficher un dialogue de modification de message
  void _showEditMessageDialog(ChatMessage message, {bool isAIMessage = false}) {
    TextEditingController _editController = TextEditingController(text: message.content);
    bool isJson = false;
    bool isModified = false;
    
    // Vérifier si le contenu est du JSON
    try {
      jsonDecode(message.content);
      isJson = true;
    } catch (_) {
      isJson = false;
    }


    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Modifier le message'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _editController,
                    decoration: InputDecoration(
                      hintText: 'Entrez votre message',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: null,
                    readOnly: isAIMessage && !isJson,
                    onChanged: (value) {
                      setState(() {
                        isModified = value.trim() != message.content;
                      });
                    },
                  ),
                  if (isAIMessage && !isJson)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Seul le contenu JSON peut être modifié pour les messages AI',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  child: Text('Annuler'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                if (isJson && isModified)
                  TextButton(
                    child: Text('Modifier'),
                    onPressed: () {
                      // Enregistrer comme brouillon sans valider
                      _aiService.modifyAndExecute(message, _editController.text.trim());
                      Navigator.of(context).pop();
                    },
                  ),
                ElevatedButton(
                  child: Text(isJson ? 'Valider' : 'Enregistrer'),
                  onPressed: () async {
                    String newContent = _editController.text.trim();
                    if (newContent.isNotEmpty && newContent != message.content) {
                      if (isJson) {
                        // Vérifier que le JSON est valide avant enregistrement
                        try {
                          jsonDecode(newContent);
                          await _aiService.modifyAndExecute(message, newContent);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('JSON invalide, veuillez corriger')),
                          );
                          return;
                        }
                      } else {
                        await _aiService.modifyAndExecute(message, newContent);
                      }
                    }
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Méthode pour afficher un dialogue pour ajuster les paramètres de voix
  Widget _buildVoiceSettingsDialog() {
    return AlertDialog(
      title: Text('Paramètres de Voix'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sélecteur de voix pour le web
            if (kIsWeb) ...[
              DropdownButton<html.SpeechSynthesisVoice>(
                value: _selectedVoice,
                hint: Text('Sélectionnez une voix'),
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
                    print('Voix sélectionnée: ${voice?.name}');
                  });
                },
              ),
              SizedBox(height: 20),
              // Bouton pour écouter un exemple de la voix sélectionnée
              ElevatedButton(
                onPressed: () {
                  String sampleText = 'Bonjour, ceci est un exemple de voix.';
                  _speak(sampleText);
                },
                child: Text('Écouter un exemple'),
              ),
              SizedBox(height: 20),
            ],
            // Sélecteur de voix pour mobile
            if (!kIsWeb) ...[
              DropdownButton<String>(
                value: _selectedVoiceName,
                hint: Text('Sélectionnez une voix'),
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    child: Text('Voix A'),
                    value: 'fr-FR-Wavenet-D',
                  ),
                  DropdownMenuItem(
                    child: Text('Voix B'),
                    value: 'fr-FR-Wavenet-B',
                  ),
                  // Ajoutez d'autres voix disponibles
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedVoiceName = value!;
                    print('Voix mobile sélectionnée: $_selectedVoiceName');
                  });
                },
              ),
              SizedBox(height: 20),
              // Bouton pour écouter un exemple de la voix sélectionnée
              ElevatedButton(
                onPressed: () {
                  String sampleText = 'Bonjour, ceci est un exemple de voix.';
                  _speak(sampleText);
                },
                child: Text('Écouter un exemple'),
              ),
              SizedBox(height: 20),
            ],
            // Slider pour le taux de parole
            Row(
              children: [
                Text('Vitesse:'),
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
                        print('Taux de parole: $_selectedSpeakingRate');
                      });
                    },
                  ),
                ),
                Text('${_selectedSpeakingRate.toStringAsFixed(1)}x'),
              ],
            ),
            SizedBox(height: 20),
            // Slider pour la hauteur (pitch) - Optionnel pour le web
            if (kIsWeb) ...[
              Row(
                children: [
                  Text('Hauteur:'),
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
                          print('Hauteur (pitch): $_selectedPitch');
                        });
                      },
                    ),
                  ),
                  Text('${_selectedPitch.toStringAsFixed(1)}'),
                ],
              ),
              SizedBox(height: 20),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Fermer'),
        ),
        ElevatedButton(
          onPressed: () {
            // Appliquer les paramètres sélectionnés
            Navigator.of(context).pop();
            _saveVoiceSelection();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Paramètres de voix mis à jour')),
            );
          },
          child: Text('Appliquer'),
        ),
      ],
    );
  }

  /// Méthode pour ouvrir le dialogue des paramètres de voix
  void _openVoiceSettings() {
    showDialog(
      context: context,
      builder: (context) {
        return _buildVoiceSettingsDialog();
      },
    );
  }

  /// Widget pour créer le conteneur de chat vocal en bas à gauche
  Widget _buildVoiceChatContainer() {
    return Positioned(
      bottom: 20,
      left: 20,
      // Ajustement pour la largeur : seulement pour les écrans mobiles
      child: MediaQuery.of(context).size.width < 600
          ? Container(
              width: MediaQuery.of(context).size.width - 40, // Ajustez selon vos besoins
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, // Espacement entre les boutons
                children: [
                  // Bouton Microphone
                  GestureDetector(
                    onTap: _toggleAssistantListening,
                    child: ScaleTransition(
                      scale: _animation,
                      child: CircleAvatar(
                        backgroundColor:
                            _isListening ? Colors.redAccent : Colors.grey[400],
                        child: Icon(
                          _isListening ? Icons.mic_off : Icons.mic,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // Bouton Casque
                  IconButton(
                    icon: Icon(
                      _isTtsEnabled ? Icons.headset : Icons.headset_off,
                      color: _isTtsEnabled ? Colors.blueAccent : Colors.grey,
                    ),
                    tooltip: _isTtsEnabled
                        ? 'Désactiver la lecture vocale'
                        : 'Activer la lecture vocale',
                    onPressed: () {
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
                ],
              ),
            )
          : SizedBox.shrink(), // Pas de barre vocale en dehors du mobile
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: primaryColor, // Gris Foncé
        actions: [
          // Bouton pour ouvrir les paramètres de voix
          IconButton(
            icon: Icon(Icons.settings_voice, color: Colors.white),
            tooltip: 'Paramètres de Voix',
            onPressed: _openVoiceSettings,
          ),
          Spacer(),
          // Bouton Déconnexion
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Déconnexion',
            onPressed: () async {
              await authService.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
          ),
        ],
      ),
      backgroundColor: const Color.fromARGB(255, 197, 197, 197), // Fond global gris plus clair
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                if (constraints.maxWidth < 600)
                  _buildMobileLayout()
                else
                  _buildDesktopLayout(),
                // Conteneur pour le chat vocal uniquement sur mobile
                if (constraints.maxWidth < 600)
                  _buildVoiceChatContainer(),
              ],
            );
          },
        ),
      ),
      // Bouton d'assistant vocal flottant pour les mobiles - Supprimé car intégré dans le conteneur vocal
    );
  }

  /// Méthode pour la mise en page mobile
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Menu Latéral (en haut pour mobile)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ...dashboardItems.map((item) => FeatureCard(item: item)).toList(),
                SizedBox(height: 20),
                // La section vidéo a été supprimée
              ],
            ),
          ),
          SizedBox(height: 16),
          // Assistant IA
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              height: 400, // Définir une hauteur fixe pour éviter les problèmes de layout
              child: _buildChatAssistantSection(),
            ),
          ),
          SizedBox(height: 16),
          // Liste des Tâches
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildUpcomingTasksSection(),
          ),
          SizedBox(height: 16),
          // Assistant Vocal Intégré - Supprimé ici car intégré dans le conteneur vocal
        ],
      ),
    );
  }

  /// Méthode pour la mise en page desktop/tablette
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Section Gauche : Barre Latérale avec largeur fixe et informations utilisateur
        Container(
          width: 250, // Largeur fixe pour la barre latérale
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white, // Fond blanc
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
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
              // En-tête avec avatar et nom de l'utilisateur
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.indigo[800],
                    child: Text(
                      _auth.currentUser?.displayName != null &&
                              _auth.currentUser!.displayName!.isNotEmpty
                          ? _auth.currentUser!.displayName![0].toUpperCase()
                          : '?',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _auth.currentUser?.displayName ?? 'Utilisateur',
                      style: GoogleFonts.roboto(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              // Liste des fonctionnalités
              Expanded(
                child: ListView(
                  children: dashboardItems.map((item) => FeatureCard(item: item)).toList(),
                ),
              ),
              SizedBox(height: 20),
              // Bouton pour créer un nouveau dossier
              ElevatedButton.icon(
                onPressed: _showCreateFolderDialog,
                icon: Icon(Icons.create_new_folder),
                label: Text('Créer un Dossier'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  textStyle: TextStyle(fontSize: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              SizedBox(height: 20),
              // Barre Vocale intégrée dans la barre latérale
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
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
                    // Bouton Microphone
                    GestureDetector(
                      onTap: _toggleAssistantListening,
                      child: ScaleTransition(
                        scale: _animation,
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor:
                              _isListening ? Colors.redAccent : Colors.grey[400],
                          child: Icon(
                            _isListening ? Icons.mic_off : Icons.mic,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Bouton Casque
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
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 16), // Espacement entre les deux sections
        // Section Droite : Assistant IA, Tâches à Venir
        Expanded(
          child: Column(
            children: [
              // Assistant IA
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildChatAssistantSection(),
                ),
              ),
              SizedBox(height: 16),
              // Liste des Tâches
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildUpcomingTasksSection(),
                ),
              ),
              // Assistant Vocal Intégré n'est plus ici
            ],
          ),
        ),
      ],
    );
  }
}

/// Widget personnalisé pour les cartes de fonctionnalités avec effet de zoom et navigation
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

    _scaleAnimation =
        Tween<double>(begin: 1.0, end: 1.05).animate(_scaleController);
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
            color: Colors.white, // Revenir au fond blanc pour les FeatureCards
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white, // Fond blanc
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0), // Ajout d'un padding interne
                child: Row(
                  children: [
                    Icon(
                      widget.item.icon,
                      size: 30,
                      color: Colors.grey[800], // Icône gris foncé
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.item.title,
                        style: GoogleFonts.roboto(
                          textStyle: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87, // Texte noir foncé
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

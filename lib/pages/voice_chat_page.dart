// lib/pages/voice_assistant_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/ai_service.dart';
import '../services/speech_service.dart';
import '../services/auth_service.dart';
import '../models/chat_message.dart';
import 'package:provider/provider.dart';

class VoiceAssistantPage extends StatefulWidget {
  const VoiceAssistantPage({super.key});

  @override
  _VoiceAssistantPageState createState() => _VoiceAssistantPageState();
}

class _VoiceAssistantPageState extends State<VoiceAssistantPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isListening = false;
  bool _isProcessing = false;
  bool _isInitialized = false;

  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    // Initialisation de l'AnimationController pour l'effet de pulsation
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _animation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    // Initialiser les services via Provider
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final aiService = Provider.of<AIService>(context, listen: false);
      final speechService = Provider.of<SpeechService>(context, listen: false);
      await _initializeSpeechService(speechService);
      setState(() {
        _isInitialized = true;
      });
    });
  }

  Future<void> _initializeSpeechService(SpeechService speechService) async {
    bool available = await speechService.initialize();
    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La reconnaissance vocale n\'est pas disponible.')),
      );
      debugPrint('Reconnaissance vocale non disponible.');
    } else {
      debugPrint('Reconnaissance vocale initialisée.');
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _toggleListening() {
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  void _startListening() {
    final speechService = Provider.of<SpeechService>(context, listen: false);
    final aiService = Provider.of<AIService>(context, listen: false);

    debugPrint('Tentative de démarrage de la reconnaissance vocale...');
    speechService.startListening(
      onResult: (result) async {
        debugPrint('Résultat final de la reconnaissance vocale reçu: $result');
        setState(() {
          _isListening = false;
          _isProcessing = true;
        });

        String userMessage = result;
        if (userMessage.isNotEmpty) {
          try {
            await aiService.sendMessage(userMessage);
          } catch (e) {
            debugPrint('Erreur lors de l\'envoi du message à l\'IA: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erreur lors de la communication avec l\'IA.')),
            );
          }
        }

        setState(() {
          _isProcessing = false;
        });
      },
      onPartialResult: (partialResult) {
        debugPrint('Résultat partiel de la reconnaissance vocale: $partialResult');
        setState(() {
          _textController.text = partialResult;
          _textController.selection = TextSelection.fromPosition(
            TextPosition(offset: _textController.text.length),
          );
        });
      },
    );

    // Démarrer l'animation
    _animationController.reset();
    _animationController.repeat(reverse: true);

    setState(() {
      _isListening = true;
    });
    debugPrint('Reconnaissance vocale démarrée.');
  }

  void _stopListening() {
    final speechService = Provider.of<SpeechService>(context, listen: false);
    speechService.stopListening();
    _animationController.stop(); // Arrêter l'animation
    _animationController.reset(); // Réinitialiser l'animation
    setState(() {
      _isListening = false;
    });
    debugPrint('Reconnaissance vocale arrêtée.');
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final aiService = Provider.of<AIService>(context, listen: false);

    try {
      await aiService.sendMessage(text.trim());
      _textController.clear();
    } catch (e) {
      debugPrint('Erreur lors de l\'envoi du message à l\'IA: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la communication avec l\'IA.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      // Afficher un indicateur de chargement jusqu'à ce que les services soient initialisés
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Assistant Vocal',
            style: GoogleFonts.roboto(),
          ),
          backgroundColor: Colors.grey[800],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Assistant Vocal',
          style: GoogleFonts.roboto(),
        ),
        backgroundColor: Colors.grey[800],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Conteneur pour afficher les résultats
            Expanded(
              child: Container(
                alignment: Alignment.center,
                child: TextField(
                  controller: _textController,
                  maxLines: null,
                  readOnly: true,
                  decoration: const InputDecoration(
                    hintText: 'Résultat vocal...',
                    border: OutlineInputBorder(),
                  ),
                  style: TextStyle(fontSize: 16, color: Colors.black87),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Bouton de microphone avec animation
            ScaleTransition(
              scale: _animation,
              child: FloatingActionButton(
                onPressed: _toggleListening,
                backgroundColor:
                    _isListening ? Colors.redAccent : Colors.blue,
                child: Icon(
                  _isListening ? Icons.mic_off : Icons.mic,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Zone de saisie pour envoyer manuellement des messages
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'Texte transcrit',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (text) {
                _sendMessage(text);
              },
            ),
          ],
        ),
      ),
    );
  }
}

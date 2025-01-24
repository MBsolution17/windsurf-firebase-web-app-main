// lib/pages/voice_assistant_page.dart

import 'package:firebase_web_app/models/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async'; // Import nécessaire pour Timer

import '../services/speech_recognition_js.dart';
import '../services/ai_service.dart';

class VoiceAssistantPage extends StatefulWidget {
  const VoiceAssistantPage({Key? key}) : super(key: key);

  @override
  _VoiceAssistantPageState createState() => _VoiceAssistantPageState();
}

class _VoiceAssistantPageState extends State<VoiceAssistantPage> {
  bool _isListening = false;
  String _recognizedText = '';
  String _aiResponse = '';
  String _lastError = '';

  late WebSpeechRecognitionService _speechService;
  late AIService _aiService;

  Timer? _stopTimer; // Déclaration du Timer

  @override
  void initState() {
    super.initState();
    _speechService = Provider.of<WebSpeechRecognitionService>(context, listen: false);
    _aiService = Provider.of<AIService>(context, listen: false);

    _speechService.onResult = (transcript) async {
      setState(() {
        _recognizedText = transcript;
        _isListening = true; // Maintient l'état d'écoute
        _lastError = '';
        _aiResponse = 'En attente de la réponse de l\'IA...';
      });
      print('Texte reconnu : $transcript');

      // Réinitialiser le Timer à chaque résultat
      _stopTimer?.cancel();
      _stopTimer = Timer(Duration(seconds: 3), () {
        _stopListening();
      });

      // Envoyer le texte reconnu à l'AI Service
      try {
        ChatMessage aiMessage = await _aiService.sendMessage(transcript);
        String responseContent = aiMessage.content;
        setState(() {
          _aiResponse = responseContent;
        });
        print('Réponse de l\'IA : $responseContent');
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
      _stopTimer?.cancel(); // Annuler le Timer en cas d'erreur
    };
  }

  @override
  void dispose() {
    _stopTimer?.cancel(); // Annuler le Timer lors de la destruction du widget
    super.dispose();
  }

  void _startListening() async {
    setState(() {
      _isListening = true;
      _recognizedText = '';
      _aiResponse = '';
      _lastError = '';
    });

    _speechService.startListening();
    print("Reconnaissance vocale démarrée.");
  }

  void _stopListening() {
    _speechService.stopListening();
    setState(() {
      _isListening = false;
    });
    print("Reconnaissance vocale arrêtée.");
    _stopTimer?.cancel(); // Annuler le Timer lorsque l'écoute est arrêtée
  }

  void _cancelListening() {
    _speechService.stopListening();
    setState(() {
      _isListening = false;
      _recognizedText = '';
      _aiResponse = '';
      _lastError = '';
    });
    print("Reconnaissance vocale annulée.");
    _stopTimer?.cancel(); // Annuler le Timer lorsque l'écoute est annulée
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant Vocal'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildStatusIndicator(),
            const SizedBox(height: 20),
            _buildRecognizedTextSection(),
            const SizedBox(height: 20),
            _buildAIResponseSection(),
            const Spacer(),
            _buildControls(),
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

  Widget _buildStatusIndicator() {
    return Row(
      children: [
        Icon(
          _isListening ? Icons.mic : Icons.mic_none,
          color: _isListening ? Colors.red : Colors.grey,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _isListening
                ? "Je vous écoute..."
                : "Appuyez sur le micro pour commencer",
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildRecognizedTextSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Texte Reconnu :',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Text(
            _recognizedText.isEmpty
                ? 'Appuyez sur le micro et parlez.'
                : _recognizedText,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildAIResponseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Réponse de l\'IA :',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: Text(
            _aiResponse.isEmpty
                ? 'La réponse de l\'IA apparaîtra ici.'
                : _aiResponse,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          FloatingActionButton(
            onPressed: _isListening ? null : _startListening,
            tooltip: 'Commencer à parler',
            child: const Icon(Icons.mic),
            backgroundColor: Colors.blue,
          ),
          FloatingActionButton(
            onPressed: _isListening ? _stopListening : null,
            tooltip: 'Arrêter la reconnaissance',
            child: const Icon(Icons.stop),
            backgroundColor: Colors.red,
          ),
          FloatingActionButton(
            onPressed: _isListening ? _cancelListening : null,
            tooltip: 'Annuler la reconnaissance',
            child: const Icon(Icons.cancel),
            backgroundColor: Colors.orange,
          ),
        ],
      ),
    );
  }
}

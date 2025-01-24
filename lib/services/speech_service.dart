// lib/services/speech_service.dart

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

class SpeechService with ChangeNotifier {
  final SpeechToText _speech = SpeechToText();
  bool _hasSpeech = false;

  /// Getter pour la propriété hasSpeech
  bool get hasSpeech => _hasSpeech;

  /// Initialise le service de reconnaissance vocale.
  Future<bool> initialize() async {
    try {
      _hasSpeech = await _speech.initialize(
        onError: _errorListener,
        onStatus: _statusListener,
      );
      if (_hasSpeech) {
        print("Reconnaissance vocale initialisée.");
      } else {
        print("La reconnaissance vocale n'est pas disponible.");
      }
      notifyListeners();
      return _hasSpeech;
    } catch (e) {
      print("Erreur lors de l'initialisation : $e");
      _hasSpeech = false;
      notifyListeners();
      return false;
    }
  }

  /// Démarre l'écoute et la reconnaissance vocale.
  void startListening({
    required Function(String) onResult,
    Function(String)? onPartialResult,
  }) {
    if (!_hasSpeech) {
      print("La reconnaissance vocale n'est pas initialisée.");
      return;
    }

    _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
        } else if (onPartialResult != null) {
          onPartialResult(result.recognizedWords);
        }
      },
      localeId: 'fr_FR',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );

    print("Reconnaissance vocale démarrée.");
    notifyListeners();
  }

  /// Arrête l'écoute et la reconnaissance vocale.
  void stopListening() {
    if (_speech.isListening) {
      _speech.stop();
      print("Reconnaissance vocale arrêtée.");
      notifyListeners();
    }
  }

  /// Annule l'écoute et la reconnaissance vocale.
  void cancelListening() {
    if (_speech.isListening) {
      _speech.cancel();
      print("Reconnaissance vocale annulée.");
      notifyListeners();
    }
  }

  /// Callback pour les erreurs.
  void _errorListener(SpeechRecognitionError error) {
    print("Erreur de reconnaissance vocale : ${error.errorMsg} - Permanent : ${error.permanent}");
    notifyListeners();
  }

  /// Callback pour les statuts.
  void _statusListener(String status) {
    print("Statut de la reconnaissance vocale : $status");
    notifyListeners();
  }
}

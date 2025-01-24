import 'package:js/js.dart';
import 'dart:js_util' as js_util;
import 'dart:html' as html;

/// Classe interopérable avec le Web Speech API en utilisant @staticInterop
@staticInterop
@JS('SpeechRecognition')
class WebSpeechRecognition {}

/// Extension pour ajouter des méthodes à la classe interopérable
extension WebSpeechRecognitionExtension on WebSpeechRecognition {
  external void start();
  external void stop();
  external void addEventListener(String event, Function callback);
  external set lang(String language);
}

/// Service pour gérer la reconnaissance vocale via le Web Speech API
class WebSpeechRecognitionService {
  WebSpeechRecognition? _recognition;

  /// Callbacks pour les résultats et les erreurs
  Function(String)? onResult;
  Function(String)? onError;

  /// Constructeur avec initialisation de la langue par défaut
  WebSpeechRecognitionService({String language = 'fr-FR'}) {
    // Vérification si l'API est supportée, sinon afficher un message
    if (js_util.hasProperty(html.window, 'SpeechRecognition') ||
        js_util.hasProperty(html.window, 'webkitSpeechRecognition')) {
      _recognition = WebSpeechRecognition();
      _recognition!.lang = language;
      print('Langue de reconnaissance définie sur : $language');

      // Ajouter des écouteurs d'événements
      _recognition!.addEventListener('result', js_util.allowInterop((event) {
        if (onResult != null) {
          var results = js_util.getProperty(event, 'results');
          if (results != null && js_util.getProperty(results, 'length') > 0) {
            var firstResult = js_util.getProperty(results, '0');
            if (firstResult != null) {
              var firstAlternative = js_util.getProperty(firstResult, '0');
              if (firstAlternative != null) {
                var transcript =
                    js_util.getProperty(firstAlternative, 'transcript') ?? '';
                onResult!(transcript);
              }
            }
          }
        }
      }));

      _recognition!.addEventListener('error', js_util.allowInterop((event) {
        var error = js_util.getProperty(event, 'error') ?? 'Unknown error';
        if (onError != null) {
          onError!(error);
        }
      }));
    } else {
      print('Reconnaissance vocale non supportée dans ce navigateur.');
    }
  }

  /// Initialise le service et vérifie la disponibilité de l'API
  Future<bool> initialize() async {
    try {
      if (_recognition != null) {
        print("Reconnaissance vocale disponible.");
        return true;
      } else {
        print("Reconnaissance vocale non disponible.");
        return false;
      }
    } catch (e) {
      print("Erreur lors de l'initialisation de la reconnaissance vocale : $e");
      return false;
    }
  }

  /// Démarre l'écoute et la reconnaissance vocale
  void startListening() {
    if (_recognition != null) {
      _recognition!.start();
      print("Reconnaissance vocale démarrée.");
    } else {
      print("Reconnaissance vocale non initialisée.");
    }
  }

  /// Arrête l'écoute et la reconnaissance vocale
  void stopListening() {
    if (_recognition != null) {
      _recognition!.stop();
      print("Reconnaissance vocale arrêtée.");
    } else {
      print("Reconnaissance vocale non initialisée.");
    }
  }
}

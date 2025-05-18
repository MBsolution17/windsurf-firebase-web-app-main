import 'dart:convert';
import 'package:http/http.dart' as http;

class TextToSpeechService {
  // Remplacez <YOUR_REGION> et <YOUR_PROJECT_ID> par vos valeurs réelles
  final String _textToSpeechUrl = 'https://<YOUR_REGION>-<YOUR_PROJECT_ID>.cloudfunctions.net/textToSpeech';

  /// Convertit le texte en parole en utilisant une fonction cloud
  /// [text] : Le texte à convertir en parole
  /// Retourne un Future<void>, lance une exception en cas d'erreur
  Future<void> speak(String text) async {
    try {
      final response = await http.post(
        Uri.parse(_textToSpeechUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        // Si vous attendez un contenu audio dans la réponse (par exemple, base64)
        // vous pouvez le traiter ici. Exemple :
        // final audioBase64 = jsonDecode(response.body)['audioContent'];
        // print('Synthèse vocale réussie : $audioBase64');
      } else {
        throw Exception(
          'Échec de la synthèse vocale : Code ${response.statusCode}, ${response.reasonPhrase}',
        );
      }
    } catch (e) {
      // Gestion des erreurs (réseau, JSON invalide, etc.)
      throw Exception('Erreur lors de la synthèse vocale : $e');
    }
  }
}
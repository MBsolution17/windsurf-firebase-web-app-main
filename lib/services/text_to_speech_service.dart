import 'dart:convert';
import 'package:http/http.dart' as http;

class TextToSpeechService {
  final String _textToSpeechUrl = 'https://<YOUR_REGION>-<YOUR_PROJECT_ID>.cloudfunctions.net/textToSpeech';

  Future<void> speak(String text) async {
    final response = await http.post(
      Uri.parse(_textToSpeechUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );

    if (response.statusCode == 200) {
      // Traitement de la réponse si nécessaire
    } else {
      // Gérer les erreurs si la requête échoue
    }
  }
}

// lib/services/ai_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

import '../models/chat_message.dart';
import '../models/action_event.dart'; // Import de ActionEvent

/// Service d'IA responsable de l'interaction avec OpenAI et Firestore.
class AIService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Charger la clé API depuis les variables d'environnement pour plus de sécurité
  // Assurez-vous d'ajouter votre clé API dans un fichier .env et de l'inclure dans votre projet.
  // Ne stockez jamais de clés API directement dans le code source.



  
  // clef ici 




  // Map des handlers d'actions
  late final Map<AIActionType, Future<void> Function(Map<String, dynamic>)> _actionHandlers;

  // Variables pour la reconnaissance vocale et la synthèse vocale
  late stt.SpeechToText _speechRecognizer;
  late FlutterTts _flutterTts;
  bool _ttsEnabled = false;
  bool _isListening = false;

  // Variables pour la validation des messages
  bool _showValidationButtons = false;
  ChatMessage? _messageToValidate;

  // StreamController pour les événements d'action
  final StreamController<ActionEvent> _actionController = StreamController<ActionEvent>.broadcast();

  /// Expose le flux d'événements d'action.
  Stream<ActionEvent> get actionStream => _actionController.stream;

  /// Constructeur initialisant les handlers d'actions et les services vocaux.
  AIService() {
    _actionHandlers = {
      AIActionType.create_task: _handleCreateTask,
      AIActionType.update_task: _handleUpdateTask,
      AIActionType.delete_task: _handleDeleteTask,
      AIActionType.create_event: _handleCreateEvent,
      AIActionType.update_event: _handleUpdateEvent,
      AIActionType.delete_event: _handleDeleteEvent,
      AIActionType.create_folder_with_document: _handleCreateFolderWithDocument,
      AIActionType.add_contact: _handleAddContact,
      AIActionType.create_folder_and_add_contact: _handleCreateFolderAndAddContact,
      AIActionType.modify_document: _handleModifyDocument,
    };

    // Initialiser les services vocaux
    _speechRecognizer = stt.SpeechToText();
    _flutterTts = FlutterTts();
  }

  //----------------------------------------------------------------------------
  // 1) OBTENIR LA RÉPONSE DE L'IA
  //----------------------------------------------------------------------------

  /// Envoie une requête à l'API OpenAI et obtient la réponse.
  Future<String> getAIResponse(String prompt) async {
    if (_apiKey.isEmpty) {
      debugPrint('Clé API OpenAI non définie.');
      return 'Clé API OpenAI non définie.';
    }

    try {
      final String currentDate = DateTime.now().toUtc().toIso8601String();

      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('Utilisateur non authentifié.');
        return 'Utilisateur non authentifié.';
      }

      // Récupération des dossiers/documents pour le contexte
      QuerySnapshot folderSnapshot = await _firestore
          .collection('folders')
          .where('userId', isEqualTo: user.uid)
          .get();

      List<String> folderNames = folderSnapshot.docs.map((doc) => doc['name'] as String).toList();

      // Récupérer les documents de chaque dossier en parallèle
      Map<String, List<String>> folderDocuments = {};
      await Future.wait(folderSnapshot.docs.map((folder) async {
        QuerySnapshot docSnapshot = await _firestore
            .collection('documents')
            .where('folderId', isEqualTo: folder.id)
            .get();
        folderDocuments[folder['name']] = docSnapshot.docs.map((doc) => doc['title'] as String).toList();
      }));

      // Construire un texte décrivant l'existant
      String foldersContext = 'Voici les dossiers existants et leurs documents :\n';
      for (var folder in folderNames) {
        final docs = folderDocuments[folder] ?? [];
        final docsList = docs.isNotEmpty ? docs.join(", ") : "Aucun document";
        foldersContext += '- $folder : $docsList\n';
      }

      // Construire le prompt système avec la date actuelle et le contexte
      final String systemPrompt = '''
Tu es un assistant personnel intelligent qui aide l'utilisateur dans un réseau social d'entreprise. La date et l'heure actuelles sont ${currentDate}.
Voici les dossiers existants et leurs documents:
${foldersContext}

Lorsque je te demande d'effectuer une ou plusieurs actions liées à l'application, réponds uniquement avec un ou plusieurs JSON structurés selon les instructions fournies. Pour les autres questions, réponds normalement. Voici les formats à utiliser :

Pour créer une tâche, réponds avec le format suivant :

{
  "action": "create_task",
  "data": {
    "title": "Titre de la tâche",
    "description": "Description de la tâche",
    "dueDate": "2024-12-10T10:00:00Z",
    "priority": "High"
  }
}

Pour créer un dossier avec un document, utilise le format suivant :

{
  "action": "create_folder_with_document",
  "data": {
    "folderName": "Nom du dossier",
    "document": {
      "title": "Titre du document",
      "content": "Contenu du document"
    }
  }
}

Pour ajouter un contact, utilise le format suivant :

{
  "action": "add_contact",
  "data": {
    "firstName": "Prénom du contact",
    "lastName": "Nom de famille du contact",
    "email": "email@example.com",
    "phone": "06 30 68 44 68",
    "address": "Adresse du contact",
    "company": "Entreprise du contact",
    "externalInfo": "Informations externes"
  }
}

Pour créer un dossier et ajouter un contact simultanément, utilise le format suivant :

{
  "action": "create_folder_and_add_contact",
  "data": {
    "folderName": "Nom du dossier",
    "contact": {
      "firstName": "Prénom du contact",
      "lastName": "Nom de famille du contact",
      "email": "email@example.com",
      "phone": "06 30 68 44 68",
      "address": "Adresse du contact",
      "company": "Entreprise du contact",
      "externalInfo": "Informations externes"
    }
  }
}

Pour modifier un document, utilise le format suivant :

{
  "action": "modify_document",
  "data": {
    "folderName": "Nom_du_dossier",
    "documentName": "Nom_du_document",
    "variables": {
      "clé_variable": "valeur_variable"
    }
  }
}

Si plusieurs actions sont nécessaires, encapsule-les dans une liste comme suit :

[
  {
    "action": "create_task",
    "data": { ... }
  },
  {
    "action": "add_contact",
    "data": { ... }
  }
]
''';

      // Appel de l'API OpenAI
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo', // Remplacez par le modèle que vous utilisez
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': prompt},
          ],
          'max_tokens': 1000, // Augmenter si nécessaire
        }),
      );

      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final Map<String, dynamic> data = json.decode(decodedBody);
        final aiMessage = data['choices'][0]['message']['content'].trim();
        debugPrint('Réponse de l\'IA: $aiMessage');
        return aiMessage;
      } else {
        debugPrint('Erreur API OpenAI: ${response.statusCode} - ${response.body}');
        return 'Erreur OpenAI.';
      }
    } catch (e) {
      debugPrint('Exception lors de l\'appel à l\'API OpenAI: $e');
      return 'Une erreur est survenue : $e';
    }
  }

  //----------------------------------------------------------------------------
  // 2) ENVOYER UN MESSAGE ET GÉRER LA RÉPONSE
  //----------------------------------------------------------------------------

  /// Envoie un message utilisateur, obtient la réponse de l'IA et prépare les messages pour validation.
  Future<ChatMessage> sendMessage(String messageContent) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Utilisateur non connecté');
    }

    // Créer le message utilisateur avec statut pending_validation et version 0
    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: messageContent,
      type: MessageType.user,
      userId: currentUser.uid,
      userEmail: currentUser.email ?? 'Utilisateur Inconnu',
      timestamp: DateTime.now(),
      status: MessageStatus.pending_validation,
      version: 0,
    );

    // Permettre la modification du message avant enregistrement
    final modifiedMessage = await _modifyMessageBeforeSave(userMessage);
    
    // Enregistrer le message modifié
    await _saveMessage(modifiedMessage);

    // Afficher les boutons de validation pour les messages utilisateur
    if (modifiedMessage.type == MessageType.user) {
      _showValidationButtons = true;
      _messageToValidate = modifiedMessage;
      notifyListeners();
    }
    debugPrint('Message utilisateur enregistré.');

    // Obtenir la réponse IA
    String aiResponse = await getAIResponse(messageContent);
    debugPrint('Réponse IA reçue: $aiResponse');

    // Créer le message IA et l'enregistrer avec statut pending_validation et version 0
    final aiMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: aiResponse,
      type: MessageType.ai,
      userId: 'ai_assistant',
      userEmail: 'ai_assistant@example.com',
      timestamp: DateTime.now(),
      status: MessageStatus.pending_validation,
      version: 0,
    );

    // Afficher les boutons de validation pour les messages IA
    if (aiMessage.type == MessageType.ai) {
      _showValidationButtons = true;
      _messageToValidate = aiMessage;
      notifyListeners();
    }

    await _saveMessage(aiMessage);

    // Retourner le message pour affichage dans l'UI
    debugPrint('Message IA enregistré.');

    return aiMessage;
  }

  //----------------------------------------------------------------------------
  // 3) MODIFIER UN MESSAGE AVANT SAUVEGARDE
  //----------------------------------------------------------------------------

  /// Permet de modifier le contenu d'un message avant son enregistrement.
  ///
  /// [message] : Message utilisateur à modifier.
  ///
  /// Retourne le message modifié.
  Future<ChatMessage> _modifyMessageBeforeSave(ChatMessage message) async {
    // Ici vous pouvez implémenter votre logique de modification
    // Par exemple : 
    // - Corriger l'orthographe
    // - Ajouter des informations contextuelles
    // - Filtrer certains mots
    // - Formater le texte
    
    // Pour l'instant on retourne le message sans modification
    return message;
  }

  //----------------------------------------------------------------------------
  // 4) SAUVEGARDER UN MESSAGE (USER OU AI)
  //----------------------------------------------------------------------------

  /// Sauvegarde un message dans Firestore.
  ///
  /// [message] : Message à sauvegarder.
  Future<void> _saveMessage(ChatMessage message) async {
    try {
      debugPrint('Enregistrement du message Firestore: ${message.toMap()}');
      await _firestore.collection('chat_messages').doc(message.id).set(message.toMap());
      debugPrint('Message sauvegardé.');
      notifyListeners();
    } catch (e) {
      debugPrint('Erreur enregistrement message: $e');
      // Optionnel : Notifier l'utilisateur de l'erreur via un SnackBar ou autre
    }
  }

  //----------------------------------------------------------------------------
  // 5) STREAM D'HISTORIQUE DU CHAT
  //----------------------------------------------------------------------------

  /// Retourne un stream de l'historique des messages du chat.
  ///
  /// Inclut les messages de l'utilisateur actuel et de l'assistant IA.
  Stream<List<ChatMessage>> getChatHistory() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('chat_messages')
        .where('userId', whereIn: [currentUser.uid, 'ai_assistant'])
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatMessage.fromFirestore(doc))
            .where((msg) => !msg.isDraft) // Exclure les brouillons si nécessaire
            .toList());
  }

  //----------------------------------------------------------------------------
  // 6) TENTER D'EXÉCUTER UNE ACTION SI LA RÉPONSE EST EN JSON
  //----------------------------------------------------------------------------

  /// Tente d'exécuter des actions définies dans la réponse de l'IA.
  ///
  /// [aiResponse] : Réponse de l'IA potentiellement contenant des actions JSON.
  /// [executedActions] : Liste pour stocker les types d'actions exécutées.
  ///
  /// Retourne `true` si au moins une action a été exécutée, `false` sinon.
  Future<bool> _tryExecuteAction(String aiResponse, List<AIActionType> executedActions) async {
    try {
      // Extraire tous les blocs JSON de la réponse de l'IA
      List<Map<String, dynamic>> actions = _extractJsonResponses(aiResponse);
      
      if (actions.isEmpty) {
        debugPrint('Aucun JSON valide trouvé dans la réponse de l\'IA.');
        return false;
      }
      
      bool atLeastOneActionExecuted = false;

      for (var actionObj in actions) {
        debugPrint('JSON parsé: $actionObj');

        // Vérifier la présence des clés "action" et "data"
        if (!actionObj.containsKey('action') || !actionObj.containsKey('data')) {
          debugPrint('Clés "action" et/ou "data" manquantes dans la réponse de l\'IA.');
          continue; // Passer au JSON suivant
        }

        final action = actionObj['action'];
        final data = actionObj['data'];

        if (action == null || data == null) {
          debugPrint('Action ou données nulles dans la réponse de l\'IA.');
          continue; // Passer au JSON suivant
        }

        // Identifier l'action
        AIActionType? actionType;
        try {
          actionType = AIActionType.values.firstWhere(
            (e) => e.toString().split('.').last == action,
            orElse: () => throw Exception('Action inconnue'),
          );
          debugPrint('Action détectée: $actionType');
        } catch (_) {
          debugPrint('Action inconnue: $action');
          continue; // Passer au JSON suivant
        }

        // Appel du handler
        final handler = _actionHandlers[actionType];
        if (handler == null) {
          debugPrint('Pas de handler défini pour: $actionType');
          continue; // Passer au JSON suivant
        }

        // Appeler le handler avec les données
        await handler(data);
        await _saveActionLog(json.encode(actionObj));
        atLeastOneActionExecuted = true;
        executedActions.add(actionType);
      }

      if (atLeastOneActionExecuted) {
        // Émettre des événements pour chaque action exécutée
        for (var action in executedActions) {
          _actionController.add(ActionEvent(actionType: action));
        }
      }

      return atLeastOneActionExecuted;
      
    } catch (e) {
      debugPrint('Erreur parsing/exécution action: $e');
      return false;
    }
  }

  //----------------------------------------------------------------------------
  // 7) SAUVEGARDER UN LOG D'ACTION
  //----------------------------------------------------------------------------

  /// Sauvegarde un log d'action dans Firestore.
  ///
  /// [aiResponse] : Réponse de l'IA contenant l'action exécutée.
  Future<void> _saveActionLog(String aiResponse) async {
    try {
      await _firestore.collection('ai_actions_logs').add({
        'response': aiResponse,
        'timestamp': Timestamp.fromDate(DateTime.now()),
        'userId': _auth.currentUser?.uid ?? 'unknown',
      });
      debugPrint('Action log sauvegardé dans Firestore.');
    } catch (e) {
      debugPrint('Erreur sauvegarde action: $e');
    }
  }

  //----------------------------------------------------------------------------
  // 8) EXTRAIRE LES VARIABLES D'UN FICHIER DOCX
  //----------------------------------------------------------------------------

  /// Extrait les variables de type {{variable}} d'un fichier DOCX.
  ///
  /// [docxBytes] : Contenu binaire du fichier DOCX.
  ///
  /// Retourne une liste de noms de variables trouvées.
  Future<List<String>> extractVariablesFromDocx(Uint8List docxBytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(docxBytes);
      final documentFile = archive.files.firstWhere(
        (file) => file.name == 'word/document.xml',
        orElse: () => throw Exception('document.xml not found in archive.'),
      );

      final documentXmlStr = utf8.decode(documentFile.content as List<int>);
      final xmlDoc = XmlDocument.parse(documentXmlStr);
      // Recomposer le texte de chaque paragraphe
      final paragraphs = xmlDoc.findAllElements('w:p');
      final Set<String> foundVars = {};

      for (var paragraph in paragraphs) {
        final text = _recomposeParagraphText(paragraph);
        // Rechercher {{xxx}}
        final regex = RegExp(r'{{\s*(\w+)\s*}}');
        final matches = regex.allMatches(text);
        for (var m in matches) {
          final varName = m.group(1) ?? '';
          if (varName.isNotEmpty) {
            foundVars.add(varName.trim());
          }
        }
      }

      debugPrint('Variables détectées dans le document: $foundVars');
      return foundVars.toList();
    } catch (e) {
      debugPrint('Erreur lors de l\'extraction des variables: $e');
      return [];
    }
  }

  //----------------------------------------------------------------------------
  // 9) MODIFIER LE FICHIER DOCX AVEC LES VALEURS DES VARIABLES
  //----------------------------------------------------------------------------

  /// Modifie un fichier DOCX en remplaçant les variables par leurs valeurs.
  ///
  /// [docxBytes] : Contenu binaire du fichier DOCX.
  /// [fieldValues] : Map des variables et leurs valeurs.
  ///
  /// Retourne le contenu binaire du fichier DOCX modifié.
  Future<Uint8List> modifyDocx(
      Uint8List docxBytes, Map<String, String> fieldValues) async {
    try {
      final archive = ZipDecoder().decodeBytes(docxBytes);
      final documentFile = archive.files.firstWhere(
        (file) => file.name == 'word/document.xml',
        orElse: () => throw Exception('document.xml not found in archive.'),
      );

      final documentXmlStr = utf8.decode(documentFile.content as List<int>);
      final xmlDoc = XmlDocument.parse(documentXmlStr);

      // Traverse tous les <w:p>, recomposer le texte, effectuer les remplacements,
      // recréer un seul <w:r>
      for (var paragraph in xmlDoc.findAllElements('w:p')) {
        // Recomposer le texte complet
        String paragraphText = _recomposeParagraphText(paragraph);

        // Remplacer toutes les variables {{key}}
        fieldValues.forEach((key, value) {
          final pattern = RegExp(r'{{\s*' + RegExp.escape(key) + r'\s*}}');
          paragraphText = paragraphText.replaceAll(pattern, _escapeXml(value));
        });

        // Supprimer les <w:r> existants et créer un nouveau <w:r> unique
        final runs = paragraph.findAllElements('w:r').toList();
        for (var r in runs) {
          r.parent?.children.remove(r);
        }

        final newRun = XmlElement(XmlName('w:r'), [], [
          XmlElement(XmlName('w:t'), [], [XmlText(paragraphText)])
        ]);
        paragraph.children.add(newRun);
      }

      // Gérer les listes dynamiques comme invoice_items ici si nécessaire
      // Par exemple : _replaceInvoiceItems(xmlDoc, invoiceItemsJson);

      final modifiedXml = xmlDoc.toXmlString();
      debugPrint('XML modifié: $modifiedXml');

      // Mettre à jour l'archive
      final updatedDocumentFile = ArchiveFile(
        'word/document.xml',
        modifiedXml.length,
        utf8.encode(modifiedXml),
      );

      final updatedArchive = Archive();
      for (var file in archive.files) {
        if (file.name != 'word/document.xml') {
          updatedArchive.addFile(file);
        }
      }
      updatedArchive.addFile(updatedDocumentFile);

      final encodedArchive = ZipEncoder().encode(updatedArchive)!;
      debugPrint('Modification du DOCX réussie.');
      return Uint8List.fromList(encodedArchive);
    } catch (e) {
      debugPrint('Erreur lors de la modification du DOCX: $e');
      throw Exception('Erreur durant la modification: $e');
    }
  }

  //----------------------------------------------------------------------------
  // 10) REMPLACER LES LISTES DYNAMIQUES (invoice_items)
  //----------------------------------------------------------------------------

  /// Remplace les listes dynamiques `invoice_items` dans un document XML.
  ///
  /// [xmlDoc] : Document XML du fichier DOCX.
  /// [invoiceItemsJson] : JSON représentant les éléments de la facture.
  void _replaceInvoiceItems(XmlDocument xmlDoc, String invoiceItemsJson) {
    try {
      final List<dynamic> invoiceItems = json.decode(invoiceItemsJson);

      double totalHT = 0;
      double totalTva = 0;
      double totalTtc = 0;
      List<XmlNode> newRows = [];

      // Construire de nouvelles lignes
      for (var item in invoiceItems) {
        final description =
            _escapeXml(item["item_description"] ?? "Description manquante");
        final quantity =
            _escapeXml(item["item_quantity"]?.toString() ?? "1");
        final unit =
            _escapeXml(item["item_unit"] ?? "unit");
        final priceHT =
            _escapeXml(item["item_price_ht"]?.toString() ?? "100");
        final tvaRate =
            _escapeXml(item["item_tva_rate"]?.toString() ?? "20");
        final tvaTotal =
            _escapeXml(item["item_tva_total"]?.toString() ?? "20");
        final ttcTotal =
            _escapeXml(item["item_ttc_total"]?.toString() ?? "120");

        // Accumuler les totaux
        totalHT += double.tryParse(
                (item["item_price_ht"]
                        ?.toString()
                        .replaceAll('€', '')
                        .trim()) ??
                    "0") ??
            0;
        totalTva += double.tryParse(
                (item["item_tva_total"]
                        ?.toString()
                        .replaceAll('€', '')
                        .replaceAll(',', '.')
                        .trim()) ??
                    "0") ??
            0;
        totalTtc += double.tryParse(
                (item["item_ttc_total"]
                        ?.toString()
                        .replaceAll('EUR', '')
                        .trim()) ??
                    "0") ??
            0;

        // Nouvelle ligne
        newRows.add(XmlElement(XmlName('w:tr'), [], [
          _createTableCell(description),
          _createTableCell(quantity),
          _createTableCell(unit),
          _createTableCell(priceHT),
          _createTableCell(tvaRate),
          _createTableCell(tvaTotal),
          _createTableCell(ttcTotal),
        ]));
      }

      // Ajouter 3 lignes de totaux
      final totalHtStr =
          '${totalHT.toStringAsFixed(2).replaceAll('.', ',')} EUR';
      final totalTvaStr =
          '${totalTva.toStringAsFixed(2).replaceAll('.', ',')} EUR';
      final totalTtcStr =
          '${totalTtc.toStringAsFixed(2).replaceAll('.', ',')} EUR';

      newRows.addAll([
        XmlElement(XmlName('w:tr'), [], [
          _createTableCell('Total HT'),
          _createTableCell(''),
          _createTableCell(''),
          _createTableCell(totalHtStr),
          _createTableCell(''),
          _createTableCell(''),
          _createTableCell(''),
        ]),
        XmlElement(XmlName('w:tr'), [], [
          _createTableCell('Total TVA'),
          _createTableCell(''),
          _createTableCell(''),
          _createTableCell(totalTvaStr),
          _createTableCell(''),
          _createTableCell(''),
          _createTableCell(''),
        ]),
        XmlElement(XmlName('w:tr'), [], [
          _createTableCell('Total TTC'),
          _createTableCell(''),
          _createTableCell(''),
          _createTableCell(totalTtcStr),
          _createTableCell(''),
          _createTableCell(''),
          _createTableCell(''),
        ]),
      ]);

      // Localiser la section {{#invoice_items}} ... {{/invoice_items}}
      final startTag = '{{#invoice_items}}';
      final endTag = '{{/invoice_items}}';

      for (var paragraph in xmlDoc.findAllElements('w:p')) {
        // Parcourir tous les runs
        for (var run in paragraph.findAllElements('w:r')) {
          for (var text in run.findAllElements('w:t')) {
            if (text.text.contains(startTag)) {
              // Localiser le parent <w:tbl>
              final table = paragraph.parent?.parent;
              if (table is XmlElement && table.name.local == 'tbl') {
                // Supprimer les anciennes lignes
                final rows = table.findAllElements('w:tr').toList();
                bool inInvoiceBlock = false;
                List<XmlNode> toRemove = [];

                for (var tr in rows) {
                  for (var tc in tr.findAllElements('w:tc')) {
                    for (var p in tc.findAllElements('w:p')) {
                      for (var tt in p.findAllElements('w:t')) {
                        if (tt.text.contains(startTag)) {
                          inInvoiceBlock = true;
                        }
                        if (tt.text.contains(endTag)) {
                          inInvoiceBlock = false;
                          toRemove.add(tr);
                          break;
                        }
                      }
                    }
                  }
                  if (inInvoiceBlock) {
                    toRemove.add(tr);
                  }
                }

                for (var removed in toRemove) {
                  removed.parent?.children.remove(removed);
                }

                // Insérer les nouvelles lignes après la première ligne
                final firstRow = table.findAllElements('w:tr').first;
                final insertionIndex =
                    table.children.indexOf(firstRow) + 1;
                table.children.insertAll(insertionIndex, newRows);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Erreur lors du remplacement des invoice_items: $e');
    }
  }

  //----------------------------------------------------------------------------
  // 11) HANDLE MODIFY_DOCUMENT
  //----------------------------------------------------------------------------

  /// Gère la modification d'un document en remplissant les variables.
  ///
  /// [data] : Données contenant les informations nécessaires à la modification.
  Future<void> _handleModifyDocument(Map<String, dynamic> data) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final FirebaseAuth auth = FirebaseAuth.instance;

    final currentUser = auth.currentUser;
    if (currentUser == null) {
      debugPrint('Utilisateur non connecté pour modify_document.');
      return;
    }

    try {
      // Récupérer les informations depuis les données
      String folderName = _getValue(data, ['folderName', 'folder_name']);
      String documentName = _getValue(data, ['documentName', 'document_name']);
      Map<String, String> variables =
          Map<String, String>.from(data['variables'] ?? {});

      if (folderName.isEmpty || documentName.isEmpty) {
        debugPrint('folderName ou documentName manquant.');
        return;
      }

      debugPrint(
          'Modification du document "$documentName" dans le dossier "$folderName".');

      // Rechercher l'folderId basé sur le folderName et l'utilisateur actuel
      QuerySnapshot folderSnap = await firestore
          .collection('folders')
          .where('name', isEqualTo: folderName)
          .where('userId', isEqualTo: currentUser.uid)
          .limit(1)
          .get();

      if (folderSnap.docs.isEmpty) {
        debugPrint('Dossier non trouvé: "$folderName" pour l\'utilisateur.');
        return;
      }

      String folderId = folderSnap.docs.first.id;

      // Rechercher le document avec le documentName et le folderId
      final docSnap = await firestore
          .collection('documents')
          .where('title', isEqualTo: documentName)
          .where('folderId', isEqualTo: folderId)
          .limit(1)
          .get();

      if (docSnap.docs.isEmpty) {
        debugPrint('Document non trouvé: "$documentName" dans "$folderName".');
        return;
      }

      final docData = docSnap.docs.first.data() as Map<String, dynamic>;
      if (docData['url'] == null) {
        debugPrint('Données du document non trouvées ou URL manquante.');
        return;
      }

      String docUrl = docData['url'];
      String docType = docData['type'] ?? 'docx';
      if (docType.toLowerCase() != 'docx') {
        debugPrint('Type de document non supporté: $docType');
        return;
      }

      final resp = await http.get(Uri.parse(docUrl));
      if (resp.statusCode != 200) {
        debugPrint('Erreur lors du téléchargement du document: ${resp.statusCode}');
        return;
      }

      final docxBytes = resp.bodyBytes;
      debugPrint('DOCX téléchargé avec succès.');

      // Extraire les variables du document
      final docVars = await extractVariablesFromDocx(docxBytes);
      debugPrint('Variables dans le document: $docVars');

      // Remplir le map fieldValues = { var: val }
      final fieldValues = <String, String>{};
      variables.forEach((k, v) {
        if (docVars.contains(k)) {
          fieldValues[k] = v.toString(); // Convertir toutes les valeurs en String
        }
      });

      // Compléter les variables manquantes avec des valeurs par défaut
      await _checkAndFetchVariablesForDocument(docVars, fieldValues);

      debugPrint('Valeurs des champs: $fieldValues');

      // Modifier le document avec les données du dossier et des contacts
      final newDocxBytes = await modifyDocx(docxBytes, fieldValues);

      // Uploader le nouveau document sur Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('documents/$folderId/modified_$documentName.docx');
      final uploadTask = storageRef.putData(newDocxBytes);
      final snap = await uploadTask.whenComplete(() => null);
      final newUrl = await snap.ref.getDownloadURL();

      // Mettre à jour le document avec 'modifiedUrl' et incrémenter la version
      await _firestore.collection('documents').doc(docSnap.docs.first.id).update({
        'modifiedUrl': newUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'version': (docData['version'] ?? 0) + 1,
      });

      debugPrint('Document modifié et enregistré: $newUrl');
    } catch (e) {
      debugPrint('Erreur lors de la modification du document: $e');
    }
  }

  //----------------------------------------------------------------------------
  // 12) COMPLÉTER LES VARIABLES MANQUANTES
  //----------------------------------------------------------------------------

  /// Complète les variables manquantes avec des valeurs par défaut.
  ///
  /// [extractedVariables] : Liste des variables extraites du document.
  /// [fieldValues] : Map des variables et leurs valeurs actuelles.
  Future<void> _checkAndFetchVariablesForDocument(
      List<String> extractedVariables, Map<String, String> fieldValues) async {
    try {
      for (var key in extractedVariables) {
        if (!fieldValues.containsKey(key) || fieldValues[key]!.isEmpty) {
          // Assigner des valeurs par défaut en fonction de la clé
          fieldValues[key] = _getDefaultValueForVariable(key);
        }
      }
      debugPrint("Variables finales: $fieldValues");
    } catch (e) {
      debugPrint("Erreur lors de la vérification des variables: $e");
      throw Exception('Erreur lors de la vérification des variables du document.');
    }
  }

  /// Retourne une valeur par défaut en fonction de la clé de variable.
  ///
  /// [key] : Nom de la variable.
  ///
  /// Retourne la valeur par défaut associée.
  String _getDefaultValueForVariable(String key) {
    switch (key) {
      case 'siret':
        return '00000000000000';
      case 'entrepreneur_name':
        return 'Nom de l\'entrepreneur';
      case 'entrepreneur_status':
        return 'Statut de l\'entrepreneur';
      case 'client_name':
        return 'Nom du client';
      case 'client_email':
        return 'client@example.com';
      case 'client_phone':
        return '0123456789';
      case 'start_date':
        return DateTime.now().toIso8601String().split('T').first; // YYYY-MM-DD
      case 'payment_due_days':
        return '30';
      case 'item_quantity':
        return '1';
      case 'item_unit':
        return 'unit';
      case 'item_price_ht':
        return '100';
      case 'item_tva_total':
        return '20';
      case 'item_ttc_total':
        return '120';
      case 'total_ht':
        return '100';
      case 'total_tva':
        return '20';
      case 'total_ttc':
        return '120';
      case 'bank_name':
        return 'Nom de la banque';
      case 'entrepreneur_phone':
        return '0987654321';
      case 'bank_iban':
        return 'FR76 3000 6000 0112 3456 7890 189';
      case 'entrepreneur_email':
        return 'entrepreneur@example.com';
      case 'bank_swift':
        return 'BNPAFRPPXXX';
      default:
        return 'N/A';
    }
  }

  //----------------------------------------------------------------------------
  // Méthodes Utilitaires
  //----------------------------------------------------------------------------

  /// Recompose le texte d'un paragraphe XML.
  ///
  /// [paragraph] : Élément XML représentant un paragraphe.
  ///
  /// Retourne le texte reconstitué du paragraphe.
  String _recomposeParagraphText(XmlElement paragraph) {
    return paragraph.findAllElements('w:t').map((e) => e.text).join('');
  }

  /// Crée une cellule de tableau XML avec du texte.
  ///
  /// [text] : Texte à insérer dans la cellule.
  ///
  /// Retourne un élément XML représentant la cellule.
  XmlElement _createTableCell(String text) {
    return XmlElement(XmlName('w:tc'), [], [
      XmlElement(XmlName('w:p'), [], [
        XmlElement(XmlName('w:r'), [], [
          XmlElement(XmlName('w:t'), [], [XmlText(text)])
        ])
      ])
    ]);
  }

  /// Échappe les caractères XML spéciaux dans une chaîne.
  ///
  /// [input] : Chaîne à échapper.
  ///
  /// Retourne la chaîne échappée.
  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Récupère la valeur à partir d'une Map avec plusieurs clés possibles.
  ///
  /// [data] : Map contenant les données.
  /// [keys] : Liste des clés possibles.
  /// [defaultValue] : Valeur par défaut si aucune clé n'est trouvée.
  ///
  /// Retourne la valeur associée ou la valeur par défaut.
  String _getValue(Map<String, dynamic> data, List<String> keys,
      [String defaultValue = '']) {
    for (var key in keys) {
      if (data.containsKey(key) && data[key] != null) {
        return data[key].toString();
      }
    }
    return defaultValue;
  }

  //----------------------------------------------------------------------------
  // **Intégration de la Reconnaissance Vocale et de la Synthèse Vocale**
  //----------------------------------------------------------------------------

  /// Démarre l'écoute vocale.
  ///
  /// [onResult] : Callback appelé avec le texte reconnu une fois l'écoute terminée.
  Future<void> startListening(Function(String) onResult) async {
    bool available = await _speechRecognizer.initialize(
      onStatus: (status) {
        debugPrint('Statut de la reconnaissance vocale: $status');
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          notifyListeners();
        }
      },
      onError: (errorNotification) {
        debugPrint('Erreur de reconnaissance vocale: ${errorNotification.errorMsg}');
        _isListening = false;
        notifyListeners();
      },
    );

    if (available) {
      _speechRecognizer.listen(
        onResult: (result) {
          if (result.finalResult) {
            onResult(result.recognizedWords);
            stopListening();
          }
        },
      );
      _isListening = true;
      notifyListeners();
      debugPrint('Reconnaissance vocale démarrée.');
    } else {
      debugPrint('Reconnaissance vocale non disponible.');
    }
  }

  /// Arrête l'écoute vocale.
  void stopListening() {
    _speechRecognizer.stop();
    _isListening = false;
    notifyListeners();
    debugPrint('Reconnaissance vocale arrêtée.');
  }

  /// Active ou désactive la synthèse vocale.
  ///
  /// [enabled] : `true` pour activer, `false` pour désactiver.
  void setTtsEnabled(bool enabled) {
    _ttsEnabled = enabled;
    notifyListeners();
    debugPrint('Synthèse vocale ${enabled ? 'activée' : 'désactivée'}');
  }

  /// Indique si la synthèse vocale est activée.
  bool get isTtsEnabled => _ttsEnabled;

  /// Indique si l'écoute vocale est en cours.
  bool get isListening => _isListening;

  //----------------------------------------------------------------------------
  // Gestion de la validation des messages
  //----------------------------------------------------------------------------

  /// Gère la validation ou le rejet d'un message
  Future<void> handleValidation(String messageId, MessageStatus status) async {
    if (_messageToValidate == null || _messageToValidate!.id != messageId) return;

    try {
      final messageRef = _firestore.collection('chat_messages').doc(messageId);
      
      await _firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(messageRef);

        if (!snapshot.exists) {
          throw Exception("Le message n'existe pas!");
        }

        ChatMessage currentMessage = ChatMessage.fromFirestore(snapshot);

        // Vérifier la version pour éviter les conflits
        if (currentMessage.version != _messageToValidate!.version) {
          throw Exception("Conflit de version détecté!");
        }

        // Mettre à jour le statut et incrémenter la version
        transaction.update(messageRef, {
          'status': status.toString().split('.').last,
          'version': currentMessage.version! + 1,
        });
      });

      // Cacher les boutons de validation
      _showValidationButtons = false;
      _messageToValidate = null;
      notifyListeners();
      
      debugPrint('Message $messageId mis à jour avec le statut: $status');

      // Si le message est validé, exécuter les actions associées
      if (status == MessageStatus.validated) {
        // Obtenir le message mis à jour
        DocumentSnapshot updatedDoc = await _firestore.collection('chat_messages').doc(messageId).get();
        ChatMessage updatedMessage = ChatMessage.fromFirestore(updatedDoc);
        await executeActionsFromMessage(updatedMessage);
      }
    } catch (e) {
      debugPrint('Erreur lors de la validation du message: $e');
      // Optionnel : Notifier l'utilisateur de l'erreur via un SnackBar ou autre
    }
  }

  //----------------------------------------------------------------------------
  // HANDLERS POUR LES DIFFÉRENTES ACTIONS
  //----------------------------------------------------------------------------

  /// Gère la création d'une tâche.
  Future<void> _handleCreateTask(Map<String, dynamic> data) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final FirebaseAuth auth = FirebaseAuth.instance;

    final currentUser = auth.currentUser;
    if (currentUser == null) {
      debugPrint('Utilisateur non connecté pour create_task.');
      return;
    }

    try {
      // Valider et parser la date d'échéance
      DateTime dueDate;
      if (data['dueDate'] != null) {
        dueDate = DateTime.parse(data['dueDate']).toLocal();
      } else {
        dueDate = DateTime.now().add(const Duration(days: 1)); // Par défaut, demain
      }

      // Valider la priorité
      String priority = data['priority'] ?? 'Low';
      if (!['Low', 'Medium', 'High'].contains(priority)) {
        priority = 'Low'; // Valeur par défaut si invalide
      }

      // Créer la tâche
      await firestore.runTransaction((transaction) async {
        DocumentReference taskRef = firestore.collection('tasks').doc();
        transaction.set(taskRef, {
          'title': data['title'] ?? 'Nouvelle tâche',
          'description': data['description'] ?? '',
          'dueDate': Timestamp.fromDate(dueDate),
          'assignee': currentUser.uid,
          'status': 'pending', // Par défaut
          'priority': priority,
          'timestamp': FieldValue.serverTimestamp(),
          'requiresValidation': true,
          'validationStatus': 'pending',
          'createdBy': currentUser.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'version': 0, // Initialiser la version
        });
      });

      debugPrint('Tâche créée avec succès.');
    } catch (e) {
      debugPrint('Erreur lors de la création de la tâche: $e');
    }
  }

  /// Gère la mise à jour d'une tâche.
  Future<void> _handleUpdateTask(Map<String, dynamic> data) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    try {
      final taskId = data['taskId'];
      if (taskId == null) {
        debugPrint('ID de tâche manquant pour la mise à jour.');
        return;
      }

      DocumentReference taskRef = firestore.collection('tasks').doc(taskId);

      await firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(taskRef);

        if (!snapshot.exists) {
          throw Exception("La tâche n'existe pas!");
        }

        Map<String, dynamic> currentTask = snapshot.data() as Map<String, dynamic>;

        // Vérifier la version si vous avez une gestion de version pour les tâches
        // Supposons que vous avez une propriété 'version' dans les tâches
        int currentVersion = currentTask['version'] ?? 0;
        int newVersion = currentVersion + 1;

        // Préparer les données à mettre à jour
        Map<String, dynamic> updateData = {};
        if (data.containsKey('title')) updateData['title'] = data['title'];
        if (data.containsKey('description'))
          updateData['description'] = data['description'];
        if (data.containsKey('dueDate'))
          updateData['dueDate'] = Timestamp.fromDate(DateTime.parse(data['dueDate']));
        if (data.containsKey('priority'))
          updateData['priority'] = data['priority'];
        if (data.containsKey('status'))
          updateData['status'] = data['status'];
        updateData['version'] = newVersion;

        if (updateData.isNotEmpty) {
          transaction.update(taskRef, updateData);
          debugPrint('Tâche mise à jour avec succès.');
        } else {
          debugPrint('Aucune donnée à mettre à jour pour la tâche.');
        }
      });
    } catch (e) {
      debugPrint('Erreur lors de la mise à jour de la tâche: $e');
    }
  }

  /// Gère la suppression d'une tâche.
  Future<void> _handleDeleteTask(Map<String, dynamic> data) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    try {
      final taskId = data['taskId'];
      if (taskId == null) {
        debugPrint('ID de tâche manquant pour la suppression.');
        return;
      }

      DocumentReference taskRef = firestore.collection('tasks').doc(taskId);

      await firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(taskRef);

        if (!snapshot.exists) {
          throw Exception("La tâche n'existe pas!");
        }

        // Supprimer la tâche
        transaction.delete(taskRef);
        debugPrint('Tâche supprimée avec succès.');
      });
    } catch (e) {
      debugPrint('Erreur lors de la suppression de la tâche: $e');
    }
  }

  /// Gère la création d'un événement.
  Future<void> _handleCreateEvent(Map<String, dynamic> data) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final FirebaseAuth auth = FirebaseAuth.instance;

    final currentUser = auth.currentUser;
    if (currentUser == null) {
      debugPrint('Utilisateur non connecté.');
      return;
    }

    try {
      String title = data['title'] ?? 'Nouvel événement';
      String description = data['description'] ?? '';
      String dateStr = data['date'] ?? DateTime.now().toIso8601String();
      DateTime date = DateTime.parse(dateStr).toLocal();

      await firestore.runTransaction((transaction) async {
        DocumentReference eventRef = firestore.collection('events').doc();
        transaction.set(eventRef, {
          'title': title,
          'description': description,
          'date': Timestamp.fromDate(date),
          'userId': currentUser.uid,
          'timestamp': FieldValue.serverTimestamp(),
          'version': 0, // Initialiser la version
        });
      });

      debugPrint('Événement créé avec succès.');
    } catch (e) {
      debugPrint('Erreur lors de la création de l\'événement: $e');
    }
  }

  /// Gère la mise à jour d'un événement.
  Future<void> _handleUpdateEvent(Map<String, dynamic> data) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    try {
      final eventId = data['eventId'];
      if (eventId == null) {
        debugPrint('ID d\'événement manquant pour la mise à jour.');
        return;
      }

      DocumentReference eventRef = firestore.collection('events').doc(eventId);

      await firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(eventRef);

        if (!snapshot.exists) {
          throw Exception("L'événement n'existe pas!");
        }

        Map<String, dynamic> currentEvent = snapshot.data() as Map<String, dynamic>;

        // Vérifier la version si vous avez une gestion de version pour les événements
        // Supposons que vous avez une propriété 'version' dans les événements
        int currentVersion = currentEvent['version'] ?? 0;
        int newVersion = currentVersion + 1;

        // Préparer les données à mettre à jour
        Map<String, dynamic> updateData = {};
        if (data.containsKey('title')) updateData['title'] = data['title'];
        if (data.containsKey('description'))
          updateData['description'] = data['description'];
        if (data.containsKey('date'))
          updateData['date'] = Timestamp.fromDate(DateTime.parse(data['date']));
        updateData['version'] = newVersion;

        if (updateData.isNotEmpty) {
          transaction.update(eventRef, updateData);
          debugPrint('Événement mis à jour avec succès.');
        } else {
          debugPrint('Aucune donnée à mettre à jour pour l\'événement.');
        }
      });
    } catch (e) {
      debugPrint('Erreur lors de la mise à jour de l\'événement: $e');
    }
  }

  /// Gère la suppression d'un événement.
  Future<void> _handleDeleteEvent(Map<String, dynamic> data) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    try {
      final eventId = data['eventId'];
      if (eventId == null) {
        debugPrint('ID d\'événement manquant pour la suppression.');
        return;
      }

      DocumentReference eventRef = firestore.collection('events').doc(eventId);

      await firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(eventRef);

        if (!snapshot.exists) {
          throw Exception("L'événement n'existe pas!");
        }

        // Supprimer l'événement
        transaction.delete(eventRef);
        debugPrint('Événement supprimé avec succès.');
      });
    } catch (e) {
      debugPrint('Erreur lors de la suppression de l\'événement: $e');
    }
  }

  /// Gère la création d'un dossier avec un document.
  Future<void> _handleCreateFolderWithDocument(Map<String, dynamic> data) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final FirebaseAuth auth = FirebaseAuth.instance;

    final currentUser = auth.currentUser;
    if (currentUser == null) {
      debugPrint('Utilisateur non connecté.');
      return;
    }

    try {
      await firestore.runTransaction((transaction) async {
        // Créer le dossier
        DocumentReference folderRef = firestore.collection('folders').doc();
        transaction.set(folderRef, {
          'name': data['folderName'] ?? 'Nouveau Dossier',
          'userId': currentUser.uid,
          'timestamp': FieldValue.serverTimestamp(),
          'version': 0, // Initialiser la version
        });

        debugPrint('Dossier "${data['folderName']}" créé avec succès.');

        // Créer le document à l'intérieur du dossier
        Map<String, dynamic> documentData = data['document'] ?? {};
        String documentTitle = documentData['title'] ?? 'Nouveau Document';
        String documentContent = documentData['content'] ?? '';
        String format = documentData['format'] ?? 'txt'; // Ajout du format

        // Générer le contenu en bytes (ici, un fichier texte ou docx selon le format)
        Uint8List contentBytes;
        String fileExtension;
        if (format.toLowerCase() == 'doc') {
          // Pour simplifier, créer un fichier texte et renommer en docx
          contentBytes = Uint8List.fromList(utf8.encode(documentContent));
          fileExtension = 'docx';
        } else {
          contentBytes = Uint8List.fromList(utf8.encode(documentContent));
          fileExtension = 'txt';
        }

        // Uploader le fichier sur Firebase Storage
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('documents/${folderRef.id}/$documentTitle.$fileExtension');
        await storageRef.putData(contentBytes);
        final downloadURL = await storageRef.getDownloadURL();

        // Enregistrer le document dans Firestore
        DocumentReference docRef = firestore.collection('documents').doc();
        transaction.set(docRef, {
          'title': documentTitle,
          'type': fileExtension,
          'url': downloadURL,
          'folderId': folderRef.id,
          'timestamp': FieldValue.serverTimestamp(),
          'version': 0, // Initialiser la version
        });

        debugPrint('Document "$documentTitle.$fileExtension" créé et uploadé avec succès dans le dossier "${data['folderName']}".');
      });
    } catch (e) {
      debugPrint('Erreur lors de la création du dossier et du document: $e');
    }
  }

  /// Gère l'ajout d'un contact.
  Future<void> _handleAddContact(Map<String, dynamic> data) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final FirebaseAuth auth = FirebaseAuth.instance;

    final currentUser = auth.currentUser;
    if (currentUser == null) {
      debugPrint('Utilisateur non connecté.');
      return;
    }

    try {
      // Extraire les informations du contact depuis les données fournies
      String firstName = data['firstName'] ?? 'Prénom inconnu';
      String lastName = data['lastName'] ?? 'Nom de famille inconnu';
      String email = data['email'] ?? '';
      String phone = data['phone'] ?? '';
      String address = data['address'] ?? '';
      String company = data['company'] ?? '';
      String externalInfo = data['externalInfo'] ?? '';

      debugPrint(
          'Données reçues pour le contact: firstName=$firstName, lastName=$lastName, email=$email, phone=$phone');

      // Expression régulière adaptée pour les numéros de téléphone français
      final RegExp phoneRegex =
          RegExp(r'^(\+33\s?|0)[1-9]([-\s]?\d{2}){4}$');

      // Validation des champs
      if (email.isNotEmpty &&
          !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
        debugPrint(
            'Format d\'email invalide pour le contact "$firstName $lastName".');
        return;
      }

      if (phone.isNotEmpty && !phoneRegex.hasMatch(phone)) {
        debugPrint(
            'Format de téléphone invalide pour le contact "$firstName $lastName".');
        return;
      }

      // Ajouter le contact à la collection 'contacts'
      await firestore.runTransaction((transaction) async {
        DocumentReference contactRef = firestore.collection('contacts').doc();
        transaction.set(contactRef, {
          'firstName': firstName,
          'lastName': lastName,
          'email': email,
          'phone': phone,
          'userId': currentUser.uid,
          'address': address,
          'company': company,
          'externalInfo': externalInfo,
          'timestamp': FieldValue.serverTimestamp(),
          'version': 0, // Initialiser la version
        });
      });

      debugPrint('Contact "$firstName $lastName" ajouté avec succès.');
    } catch (e) {
      debugPrint('Erreur lors de l\'ajout du contact: $e');
    }
  }

  /// Gère la création d'un dossier et l'ajout d'un contact simultanément.
  Future<void> _handleCreateFolderAndAddContact(Map<String, dynamic> data) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final FirebaseAuth auth = FirebaseAuth.instance;

    final currentUser = auth.currentUser;
    if (currentUser == null) {
      debugPrint('Utilisateur non connecté.');
      return;
    }

    try {
      String folderName = data['folderName'] ?? 'Nouveau Dossier';
      Map<String, dynamic> contactData = data['contact'] ?? {};

      // Démarrer une transaction
      await firestore.runTransaction((transaction) async {
        // Créer le dossier
        DocumentReference folderRef = firestore.collection('folders').doc();
        transaction.set(folderRef, {
          'name': folderName,
          'userId': currentUser.uid,
          'timestamp': FieldValue.serverTimestamp(),
          'version': 0, // Initialiser la version
        });

        debugPrint('Dossier "$folderName" créé avec succès.');

        // Extraire les informations du contact depuis les données fournies
        String firstName = contactData['firstName'] ?? 'Prénom inconnu';
        String lastName = contactData['lastName'] ?? 'Nom de famille inconnu';
        String email = contactData['email'] ?? '';
        String phone = contactData['phone'] ?? '';
        String address = contactData['address'] ?? '';
        String company = contactData['company'] ?? '';
        String externalInfo = contactData['externalInfo'] ?? '';

        debugPrint(
            'Données reçues pour le contact: firstName=$firstName, lastName=$lastName, email=$email, phone=$phone');

        // Expression régulière adaptée pour les numéros de téléphone français
        final RegExp phoneRegex =
            RegExp(r'^(\+33\s?|0)[1-9]([-\s]?\d{2}){4}$');

        // Validation des champs
        if (email.isNotEmpty &&
            !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
          debugPrint(
              'Format d\'email invalide pour le contact "$firstName $lastName".');
          throw Exception('Format d\'email invalide.');
        }

        if (phone.isNotEmpty && !phoneRegex.hasMatch(phone)) {
          debugPrint(
              'Format de téléphone invalide pour le contact "$firstName $lastName".');
          throw Exception('Format de téléphone invalide.');
        }

        // Ajouter le contact avec le folderId
        DocumentReference contactRef = firestore.collection('contacts').doc();
        transaction.set(contactRef, {
          'firstName': firstName,
          'lastName': lastName,
          'email': email,
          'phone': phone,
          'userId': currentUser.uid,
          'address': address,
          'company': company,
          'externalInfo': externalInfo,
          'folderId': folderRef.id,
          'timestamp': FieldValue.serverTimestamp(),
          'version': 0, // Initialiser la version
        });

        debugPrint(
            'Contact "$firstName $lastName" ajouté avec succès dans le dossier "$folderName".');
      });
    } catch (e) {
      debugPrint(
          'Erreur lors de la création du dossier et de l\'ajout du contact: $e');
    }
  }

  //----------------------------------------------------------------------------
  // Nettoyage et extraction des blocs JSON de la réponse de l'IA
  //----------------------------------------------------------------------------

  /**
   * Extrait tous les blocs JSON de la réponse de l'IA en supprimant les blocs de code Markdown.
   * Retourne une liste de Map<String, dynamic>.
   */
  List<Map<String, dynamic>> _extractJsonResponses(String response) {
    // Supprimer les blocs de code Markdown
    response = response.replaceAll(RegExp(r'```json\s*'), '');
    response = response.replaceAll(RegExp(r'\s*```'), '');

    try {
      // Tenter de parser comme liste de JSON
      final List<dynamic> jsonList = json.decode(response);
      return jsonList.cast<Map<String, dynamic>>();
    } catch (e) {
      // Si ce n'est pas une liste, tenter de parser comme un seul JSON
      try {
        final Map<String, dynamic> jsonObj = json.decode(response);
        return [jsonObj];
      } catch (e) {
        debugPrint('Erreur lors de l\'extraction des JSONs: $e');
        return [];
      }
    }
  }

  //----------------------------------------------------------------------------
  // 13) MÉTHODE POUR VÉRIFIER SI UNE CHAÎNE EST UN JSON VALIDE
  //----------------------------------------------------------------------------

  /// Vérifie si une chaîne est un JSON valide.
  ///
  /// [str] : Chaîne à vérifier.
  ///
  /// Retourne `true` si c'est un JSON valide, sinon `false`.
  bool _isJson(String str) {
    try {
      json.decode(str);
      return true;
    } catch (e) {
      return false;
    }
  }

  //----------------------------------------------------------------------------
  // 14) EXÉCUTER LES ACTIONS À PARTIR DU MESSAGE
  //----------------------------------------------------------------------------

  /// Exécute les actions basées sur le contenu d'un message validé.
  ///
  /// [message] : Message validé contenant des actions JSON.
  Future<void> executeActionsFromMessage(ChatMessage message) async {
    if (message.status != MessageStatus.validated) {
      debugPrint('Message non validé: ${message.id}');
      return;
    }

    List<AIActionType> executedActions = [];

    bool actionExecuted = await _tryExecuteAction(message.content, executedActions);
    if (actionExecuted) {
      debugPrint('Actions exécutées pour le message: ${message.id}');
      // Émission des événements pour chaque action exécutée
      for (var action in executedActions) {
        _actionController.add(ActionEvent(actionType: action));
      }
    } else {
      debugPrint('Aucune action exécutée pour le message: ${message.id}');
    }
  }

  /// Modifie le contenu d'un message et exécute les actions basées sur le contenu modifié.
  ///
  /// [message] : Message à modifier.
  /// [newContent] : Nouveau contenu du message.
  Future<void> modifyAndExecuteActions(ChatMessage message, String newContent) async {
    // Valider que le nouveau contenu est un JSON valide
    if (!_isJson(newContent)) {
      throw Exception('Le contenu modifié doit être un JSON valide.');
    }

    // Mettre à jour le message avec le nouveau contenu
    await updateMessage(message.id, newContent, isDraft: false);

    // Obtenir le message mis à jour
    DocumentSnapshot updatedDoc = await _firestore.collection('chat_messages').doc(message.id).get();
    ChatMessage updatedMessage = ChatMessage.fromFirestore(updatedDoc);

    // Exécuter les actions basées sur le nouveau contenu
    bool actionExecuted = await _tryExecuteAction(updatedMessage.content, []);
    if (actionExecuted) {
      debugPrint('Actions exécutées pour le message modifié: ${message.id}');
    } else {
      debugPrint('Aucune action exécutée pour le message modifié: ${message.id}');
    }
  }

  //----------------------------------------------------------------------------
  // Méthode pour mettre à jour un message existant
  //----------------------------------------------------------------------------

  /// Met à jour le contenu d'un message existant dans Firestore.
  ///
  /// [messageId] : ID du message à mettre à jour.
  /// [newContent] : Nouveau contenu du message.
  /// [isDraft] : Indique si le message est enregistré comme brouillon.
  Future<void> updateMessage(String messageId, String newContent, {bool isDraft = false}) async {
    try {
      // Référence au document du message
      DocumentReference messageRef =
          _firestore.collection('chat_messages').doc(messageId);

      // Récupérer le document avec sa version
      DocumentSnapshot doc = await messageRef.get();
      if (!doc.exists) {
        debugPrint('Message avec ID $messageId non trouvé.');
        throw Exception('Message non trouvé.');
      }

      ChatMessage currentMessage = ChatMessage.fromFirestore(doc);

      // Mettre à jour le contenu, le statut, et incrémenter la version
      Map<String, dynamic> updateData = {
        'content': newContent,
        'timestamp': FieldValue.serverTimestamp(),
        'isDraft': isDraft,
        'version': (currentMessage.version ?? 0) + 1,
      };

      if (!isDraft) {
        updateData['status'] = 'validated'; // Optionnel: mettre à jour le statut si nécessaire
      }

      await messageRef.update(updateData);

      debugPrint('Message avec ID $messageId mis à jour avec succès.');

      // Optionnel : Ajouter une entrée dans l'historique des modifications
      await _firestore.collection('chat_messages_history').add({
        'messageId': messageId,
        'newContent': newContent,
        'timestamp': FieldValue.serverTimestamp(),
        'modifiedBy': _auth.currentUser?.uid ?? 'unknown',
        'isDraft': isDraft,
      });

      notifyListeners(); // Notifier les écouteurs si nécessaire
    } catch (e) {
      debugPrint('Erreur lors de la mise à jour du message: $e');
      throw Exception('Erreur lors de la mise à jour du message: $e');
    }
  }

  //----------------------------------------------------------------------------
  // Dispose des ressources
  //----------------------------------------------------------------------------

  @override
  void dispose() {
    _speechRecognizer.cancel();
    _flutterTts.stop();
    _actionController.close(); // Fermer le StreamController
    super.dispose();
  }
}

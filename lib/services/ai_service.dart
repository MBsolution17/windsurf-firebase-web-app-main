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

  // Charger la clé API depuis les variables d'environnement pour plus de sécurité.
  static const String _apiKey =
      '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';

  // Map des handlers d'actions.
  late final Map<AIActionType, Future<void> Function(Map<String, dynamic>)> _actionHandlers;

  // Variables pour la reconnaissance vocale et la synthèse vocale.
  late stt.SpeechToText _speechRecognizer;
  late FlutterTts _flutterTts;
  bool _ttsEnabled = false;
  bool _isListening = false;

  // Variables pour la validation des messages.
  bool _showValidationButtons = false;
  ChatMessage? _messageToValidate;

  // StreamController pour les événements d'action.
  final StreamController<ActionEvent> _actionController = StreamController<ActionEvent>.broadcast();

  /// Expose le flux d'événements d'action.
  Stream<ActionEvent> get actionStream => _actionController.stream;

  /// Constructeur initialisant les handlers d'actions et les services vocaux.
  AIService() {
    _actionHandlers = {
      AIActionType.create_task: handleCreateTask, // Changé en nom de méthode public
      AIActionType.update_task: handleUpdateTask, // Changé en nom de méthode public
      AIActionType.delete_task: handleDeleteTask, // Changé en nom de méthode public
      AIActionType.create_event: handleCreateEvent, // Changé en nom de méthode public
      AIActionType.update_event: handleUpdateEvent, // Changé en nom de méthode public
      AIActionType.delete_event: handleDeleteEvent, // Changé en nom de méthode public
      AIActionType.create_folder_with_document: handleCreateFolderWithDocument, // Changé en nom de méthode public
      AIActionType.add_contact: handleAddContact, // Changé en nom de méthode public
      AIActionType.create_folder_and_add_contact: handleCreateFolderAndAddContact, // Changé en nom de méthode public
      AIActionType.modify_document: handleModifyDocument, // Changé en nom de méthode public
    };

    // Initialiser les services vocaux.
    _speechRecognizer = stt.SpeechToText();
    _flutterTts = FlutterTts();
  }

  //----------------------------------------------------------------------------
  // Méthode pour obtenir le workspaceId de l'utilisateur actuel.
  //----------------------------------------------------------------------------
  Future<String> _getWorkspaceId() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utilisateur non authentifié');

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (!userDoc.exists) throw Exception('Document utilisateur introuvable');

    final workspaceId = userDoc.get('workspaceId') as String?; // Typage explicite
    if (workspaceId == null) throw Exception('Workspace non configuré');

    return workspaceId;
  }

  //----------------------------------------------------------------------------
  // 1) OBTENIR LA RÉPONSE DE L'IA SANS LIMITATION DE LONGUEUR
  //----------------------------------------------------------------------------
  Future<String> getAIResponse(String prompt) async {
    if (_apiKey.isEmpty) {
      debugPrint('Clé API OpenAI non définie.');
      return 'Clé API OpenAI non définie.';
    }

    try {
      final String currentDate = DateTime.now().toUtc().toIso8601String();
      final workspaceId = await _getWorkspaceId();
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('Utilisateur non authentifié.');
        return 'Utilisateur non authentifié.';
      }

      // Récupération des dossiers/documents pour le contexte.
      QuerySnapshot folderSnapshot = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('folders')
          .where('userId', isEqualTo: user.uid)
          .get();

      List<String> folderNames = folderSnapshot.docs.map((doc) => doc['name'] as String).toList();

      // Récupérer les documents de chaque dossier en parallèle.
      Map<String, List<String>> folderDocuments = {};
      await Future.wait(folderSnapshot.docs.map((folder) async {
        QuerySnapshot docSnapshot = await _firestore
            .collection('workspaces')
            .doc(workspaceId)
            .collection('documents')
            .where('folderId', isEqualTo: folder.id)
            .get();
        folderDocuments[folder['name'] as String] = docSnapshot.docs.map((doc) => doc['title'] as String).toList();
      }));

      String foldersContext = 'Voici les dossiers existants et leurs documents :\n';
      for (var folder in folderNames) {
        final docs = folderDocuments[folder] ?? [];
        final docsList = docs.isNotEmpty ? docs.join(", ") : "Aucun document";
        foldersContext += '- $folder : $docsList\n';
      }

      final String systemPrompt = '''
Tu es un assistant IA professionnel intégré à notre plateforme d'entreprise. La date et l'heure actuelles sont ${currentDate}.
Voici les dossiers existants et leurs documents:
${foldersContext}

## CE QUE JE PEUX FAIRE POUR VOUS ##

Voici les principales fonctionnalités que je peux réaliser pour vous :

1. GESTION DE LA FACTURATION ET DES FINANCES :
   - Créer, modifier et supprimer devis et factures en quelques clics
   - Envoyer automatiquement des relances de paiement selon des règles personnalisées
   - Suivre l'état des paiements et des échéances via un tableau de bord dédié

2. GESTION DE PLANNING ET D'ÉVÉNEMENTS :
   - Créer, modifier et supprimer des rendez-vous ou réunions dans votre calendrier
   - Synchroniser automatiquement plusieurs agendas (Google, Outlook…)
   - Vous envoyer des rappels intelligents pour éviter les conflits de planning

3. GÉNÉRATION ET ORGANISATION DE DOCUMENTS :
   - Créer des dossiers et sous-dossiers pour structurer vos fichiers
   - Générer automatiquement des documents (contrats, rapports, e-mails) à partir de modèles et de variables pré-remplies
   - Modifier en temps réel le contenu et partager directement avec vos collaborateurs

4. GESTION DE CONTACTS ET CRM :
   - Ajouter de nouveaux contacts (clients, fournisseurs, partenaires) avec toutes leurs coordonnées
   - Organiser vos contacts par dossier ou étiquette (prospects, VIP, fournisseurs…)
   - Suivre l'historique des échanges pour chaque contact

5. AUTOMATISATION INTELLIGENTE ET ASSISTANCE IA :
   - Répondre à vos questions sur l'utilisation de la plateforme
   - Exécuter des actions à votre demande (ex. "Génère-moi un rapport de ventes")
   - Proposer des suggestions automatiques que vous pouvez valider ou ajuster avant exécution

## EXEMPLES D'UTILISATION ##

Voici quelques exemples de la façon dont vous pouvez m'utiliser :

Pour les FACTURES et FINANCES :
- "Crée une facture pour le client Dupont pour la prestation de conseil"
- "Envoie une relance pour les factures impayées de plus de 30 jours"
- "Montre-moi l'état des paiements du mois dernier"

Pour les ÉVÉNEMENTS :
- "Planifie une réunion d'équipe jeudi prochain à 14h"
- "Déplace mon rendez-vous avec Martin à vendredi matin"
- "Crée un événement pour le salon professionnel du 15 au 17 octobre"

Pour les DOCUMENTS :
- "Crée un dossier 'Projet XYZ' avec un document de spécifications"
- "Génère un contrat de service pour le client ABC avec les tarifs standards"
- "Modifie le rapport trimestriel pour mettre à jour les chiffres de vente"

Pour les CONTACTS :
- "Ajoute Jean Dupont à mes contacts avec son email jean.dupont@example.com"
- "Crée un dossier 'Fournisseurs' et classe mes contacts concernés"
- "Montre-moi l'historique des échanges avec la société ABC"

Pour l'ASSISTANCE GÉNÉRALE :
- "Que peux-tu faire pour m'aider ?"
- "Comment puis-je créer une facture récurrente ?"
- "Génère-moi un rapport des ventes du dernier trimestre"

Lorsque je te demande d'effectuer une ou plusieurs actions liées à l'application, réponds uniquement avec un ou plusieurs JSON structurés selon les instructions fournies. Pour les autres questions, réponds normalement avec un ton professionnel et direct.

Si l'utilisateur demande ce que je peux faire ou mes fonctionnalités, présente simplement les 5 catégories de fonctionnalités avec leurs points principaux, sans fioritures marketing.

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

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo', // Resté sur gpt-3.5-turbo pour le coût
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.7, // Conserver pour un équilibre créativité/précision
        }),
      ).timeout(const Duration(seconds: 20)); // Augmenté pour permettre de longues réponses sans limite

      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final Map<String, dynamic> data = json.decode(decodedBody);
        String aiMessage = data['choices'][0]['message']['content'].trim();
        debugPrint('Réponse de l\'IA (avant déduplication) : $aiMessage');

        // Déduplication de la réponse JSON.
        if (isJson(aiMessage)) {
          aiMessage = deduplicateJsonActions(aiMessage);
          debugPrint('Réponse de l\'IA (après déduplication) : $aiMessage');
        }

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

  /// Cette fonction déduplication la réponse JSON en supprimant les actions de type "add_contact"
  /// si une action détaillée correspondante ("create_folder_and_add_contact" ou "create_folder_with_document")
  /// existe pour le même email.
  String deduplicateJsonActions(String jsonResponse) {
    try {
      final dynamic decoded = json.decode(jsonResponse);
      if (decoded is! List) return jsonResponse;
      List<Map<String, dynamic>> actions = List<Map<String, dynamic>>.from(decoded);
      List<Map<String, dynamic>> deduplicated = [];

      for (var action in actions) {
        String actionName = action['action']?.toString().toLowerCase() ?? '';
        if (actionName == 'add_contact') {
          // Récupérer l'email de l'action "add_contact".
          String? email = action['data']?['email']?.toString().toLowerCase();
          if (email != null && email.isNotEmpty) {
            // Vérifier s'il existe déjà une action détaillée pour ce même email.
            bool detailedExists = actions.any((a) {
              String aName = a['action']?.toString().toLowerCase() ?? '';
              if (aName == 'create_folder_and_add_contact' || aName == 'create_folder_with_document') {
                String? detailedEmail = a['data']?['contact']?['email']?.toString().toLowerCase();
                return (detailedEmail != null && detailedEmail == email);
              }
              return false;
            });
            if (detailedExists) {
              // On ne conserve pas l'action "add_contact" isolée.
              continue;
            }
          }
        }
        // On conserve toutes les autres actions (et les actions détaillées).
        deduplicated.add(action);
      }
      return jsonEncode(deduplicated);
    } catch (e) {
      debugPrint('Erreur lors de la déduplication du JSON: $e');
      return jsonResponse;
    }
  }

  //----------------------------------------------------------------------------
  // 2) ENVOYER UN MESSAGE ET GÉRER LA RÉPONSE
  //----------------------------------------------------------------------------
  Future<ChatMessage> sendMessage(String messageContent) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('Utilisateur non connecté');
    }
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
    final modifiedMessage = await _modifyMessageBeforeSave(userMessage);
    await _saveMessage(modifiedMessage);
    if (modifiedMessage.type == MessageType.user) {
      _showValidationButtons = true;
      _messageToValidate = modifiedMessage;
      notifyListeners();
    }
    debugPrint('Message utilisateur enregistré.');
    String aiResponse = await getAIResponse(messageContent);
    debugPrint('Réponse IA reçue: $aiResponse');
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
    if (aiMessage.type == MessageType.ai) {
      _showValidationButtons = true;
      _messageToValidate = aiMessage;
      notifyListeners();
    }
    await _saveMessage(aiMessage);
    debugPrint('Message IA enregistré.');
    return aiMessage;
  }

  //----------------------------------------------------------------------------
  // 3) MODIFIER UN MESSAGE AVANT SAUVEGARDE
  //----------------------------------------------------------------------------
  Future<ChatMessage> _modifyMessageBeforeSave(ChatMessage message) async {
    return message;
  }

  //----------------------------------------------------------------------------
  // 4) SAUVEGARDER UN MESSAGE (USER OU AI)
  //----------------------------------------------------------------------------
  Future<void> _saveMessage(ChatMessage message) async {
    try {
      final workspaceId = await _getWorkspaceId();
      debugPrint('Enregistrement du message Firestore: ${message.toMap()}');
      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('chat_messages')
          .doc(message.id)
          .set(message.toMap());
      debugPrint('Message sauvegardé.');
      notifyListeners();
    } catch (e) {
      debugPrint('Erreur enregistrement message: $e');
    }
  }

  //----------------------------------------------------------------------------
  // 5) STREAM D'HISTORIQUE DU CHAT
  //----------------------------------------------------------------------------
  Stream<List<ChatMessage>> getChatHistory() async* {
    final user = _auth.currentUser;
    if (user == null) {
      yield [];
      return;
    }
    final workspaceId = await _getWorkspaceId();
    yield* _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('chat_messages')
        .where('userId', whereIn: [user.uid, 'ai_assistant'])
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatMessage.fromFirestore(doc))
            .where((msg) => !msg.isDraft)
            .toList());
  }

  //----------------------------------------------------------------------------
  // 6) TENTER D'EXÉCUTER UNE ACTION SI LA RÉPONSE EST EN JSON
  //----------------------------------------------------------------------------
  Future<bool> _tryExecuteAction(String aiResponse, List<AIActionType> executedActions) async {
    try {
      List<Map<String, dynamic>> actions = _extractJsonResponses(aiResponse);
      if (actions.isEmpty) {
        debugPrint('Aucun JSON valide trouvé dans la réponse de l\'IA.');
        return false;
      }
      // Si une action combinée est présente, filtrer les actions "add_contact" isolées.
      bool combinedActionExists = actions.any((a) =>
          a['action']?.toString().toLowerCase() == 'create_folder_with_document' ||
          a['action']?.toString().toLowerCase() == 'create_folder_and_add_contact');
      if (combinedActionExists) {
        actions = actions.where((a) => a['action']?.toString().toLowerCase() != 'add_contact').toList();
      }
      // Déduplication : pour les actions de création de contact, si une action détaillée existe
      // pour le même email, on ne conserve que cette action détaillée.
      List<Map<String, dynamic>> deduplicatedActions = [];
      for (var action in actions) {
        String actionName = action['action']?.toString().toLowerCase() ?? '';
        if (actionName == 'add_contact') {
          String? email = action['data']?['email']?.toString().toLowerCase();
          if (email != null && email.isNotEmpty) {
            bool detailedExists = actions.any((a) {
              String aName = a['action']?.toString().toLowerCase() ?? '';
              if (aName == 'create_folder_and_add_contact' || aName == 'create_folder_with_document') {
                String? detailedEmail = a['data']?['contact']?['email']?.toString().toLowerCase();
                return (detailedEmail != null && detailedEmail == email);
              }
              return false;
            });
            if (detailedExists) continue;
          }
        }
        deduplicatedActions.add(action);
      }
      actions = deduplicatedActions;

      bool atLeastOneActionExecuted = false;
      for (var actionObj in actions) {
        debugPrint('JSON parsé: $actionObj');
        if (!actionObj.containsKey('action') || !actionObj.containsKey('data')) {
          debugPrint('Clés "action" et/ou "data" manquantes dans la réponse de l\'IA.');
          continue;
        }
        final action = actionObj['action'];
        final data = actionObj['data'];
        if (action == null || data == null) {
          debugPrint('Action ou données nulles dans la réponse de l\'IA.');
          continue;
        }
        AIActionType? actionType;
        try {
          actionType = AIActionType.values.firstWhere(
            (e) => e.toString().split('.').last.toLowerCase() == action.toString().toLowerCase(),
            orElse: () => throw Exception('Action inconnue'),
          );
          debugPrint('Action détectée: $actionType');
        } catch (_) {
          debugPrint('Action inconnue: $action');
          continue;
        }
        final handler = _actionHandlers[actionType];
        if (handler == null) {
          debugPrint('Pas de handler défini pour: $actionType');
          continue;
        }
        await handler(data);
        await _saveActionLog(json.encode(actionObj));
        atLeastOneActionExecuted = true;
        executedActions.add(actionType);
      }
      if (atLeastOneActionExecuted) {
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
  Future<void> _saveActionLog(String aiResponse) async {
    try {
      final workspaceId = await _getWorkspaceId();
      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('ai_actions_logs')
          .add({
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
  Future<List<String>> extractVariablesFromDocx(Uint8List docxBytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(docxBytes);
      final documentFile = archive.files.firstWhere(
        (file) => file.name == 'word/document.xml',
        orElse: () => throw Exception('document.xml not found in archive.'),
      );
      final documentXmlStr = utf8.decode(documentFile.content as List<int>);
      final xmlDoc = XmlDocument.parse(documentXmlStr);
      final paragraphs = xmlDoc.findAllElements('w:p');
      final Set<String> foundVars = {};
      for (var paragraph in paragraphs) {
        final text = _recomposeParagraphText(paragraph);
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
      for (var paragraph in xmlDoc.findAllElements('w:p')) {
        String paragraphText = _recomposeParagraphText(paragraph);
        fieldValues.forEach((key, value) {
          final pattern = RegExp(r'{{\s*' + RegExp.escape(key) + r'\s*}}');
          paragraphText = paragraphText.replaceAll(pattern, _escapeXml(value));
        });
        final runs = paragraph.findAllElements('w:r').toList();
        for (var r in runs) {
          r.parent?.children.remove(r);
        }
        final newRun = XmlElement(XmlName('w:r'), [], [
          XmlElement(XmlName('w:t'), [], [XmlText(paragraphText)])
        ]);
        paragraph.children.add(newRun);
      }
      final modifiedXml = xmlDoc.toXmlString();
      debugPrint('XML modifié: $modifiedXml');
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
  void _replaceInvoiceItems(XmlDocument xmlDoc, String invoiceItemsJson) {
    try {
      final List<dynamic> invoiceItems = json.decode(invoiceItemsJson);
      double totalHT = 0;
      double totalTva = 0;
      double totalTtc = 0;
      List<XmlNode> newRows = [];
      for (var item in invoiceItems) {
        final description = _escapeXml(item["item_description"] ?? "Description manquante");
        final quantity = _escapeXml(item["item_quantity"]?.toString() ?? "1");
        final unit = _escapeXml(item["item_unit"] ?? "unit");
        final priceHT = _escapeXml(item["item_price_ht"]?.toString() ?? "100");
        final tvaRate = _escapeXml(item["item_tva_rate"]?.toString() ?? "20");
        final tvaTotal = _escapeXml(item["item_tva_total"]?.toString() ?? "20");
        final ttcTotal = _escapeXml(item["item_ttc_total"]?.toString() ?? "120");
        totalHT += double.tryParse((item["item_price_ht"]?.toString().replaceAll('€', '').trim()) ?? "0") ?? 0;
        totalTva += double.tryParse((item["item_tva_total"]?.toString().replaceAll('€', '').replaceAll(',', '.').trim()) ?? "0") ?? 0;
        totalTtc += double.tryParse((item["item_ttc_total"]?.toString().replaceAll('EUR', '').trim()) ?? "0") ?? 0;
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
      final totalHtStr = '${totalHT.toStringAsFixed(2).replaceAll('.', ',')} EUR';
      final totalTvaStr = '${totalTva.toStringAsFixed(2).replaceAll('.', ',')} EUR';
      final totalTtcStr = '${totalTtc.toStringAsFixed(2).replaceAll('.', ',')} EUR';
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
      final startTag = '{{#invoice_items}}';
      final endTag = '{{/invoice_items}}';
      for (var paragraph in xmlDoc.findAllElements('w:p')) {
        for (var run in paragraph.findAllElements('w:r')) {
          for (var text in run.findAllElements('w:t')) {
            if (text.text.contains(startTag)) {
              final table = paragraph.parent?.parent;
              if (table is XmlElement && table.name.local == 'tbl') {
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
                final firstRow = table.findAllElements('w:tr').first;
                final insertionIndex = table.children.indexOf(firstRow) + 1;
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
  Future<void> handleModifyDocument(Map<String, dynamic> data) async {
    try {
      final workspaceId = await _getWorkspaceId();
      String folderName = getValue(data, ['folderName', 'folder_name']);
      String documentName = getValue(data, ['documentName', 'document_name']);
      Map<String, String> variables = Map<String, String>.from(data['variables'] ?? {});
      if (folderName.isEmpty || documentName.isEmpty) {
        debugPrint('folderName ou documentName manquant.');
        return;
      }
      debugPrint('Modification du document "$documentName" dans le dossier "$folderName".');
      QuerySnapshot folderSnap = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('folders')
          .where('name', isEqualTo: folderName)
          .where('userId', isEqualTo: _auth.currentUser?.uid)
          .limit(1)
          .get();
      if (folderSnap.docs.isEmpty) {
        debugPrint('Dossier non trouvé: "$folderName" pour l\'utilisateur.');
        return;
      }
      String folderId = folderSnap.docs.first.id;
      final docSnap = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
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
      String docUrl = docData['url'] as String;
      String docType = docData['type'] as String? ?? 'docx';
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
      final docVars = await extractVariablesFromDocx(docxBytes);
      debugPrint('Variables dans le document: $docVars');
      final fieldValues = <String, String>{};
      variables.forEach((k, v) {
        if (docVars.contains(k)) {
          fieldValues[k] = v.toString();
        }
      });
      await _checkAndFetchVariablesForDocument(docVars, fieldValues);
      debugPrint('Valeurs des champs: $fieldValues');
      final newDocxBytes = await modifyDocx(docxBytes, fieldValues);
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('workspaces/$workspaceId/documents/$folderId/modified_$documentName.docx');
      final uploadTask = storageRef.putData(newDocxBytes);
      final snap = await uploadTask.whenComplete(() => null);
      final newUrl = await snap.ref.getDownloadURL();
      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('documents')
          .doc(docSnap.docs.first.id)
          .update({
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
  Future<void> _checkAndFetchVariablesForDocument(
      List<String> extractedVariables, Map<String, String> fieldValues) async {
    try {
      for (var key in extractedVariables) {
        if (!fieldValues.containsKey(key) || fieldValues[key]!.isEmpty) {
          fieldValues[key] = getDefaultValueForVariable(key);
        }
      }
      debugPrint("Variables finales: $fieldValues");
    } catch (e) {
      debugPrint("Erreur lors de la vérification des variables: $e");
      throw Exception('Erreur lors de la vérification des variables du document.');
    }
  }

  String getDefaultValueForVariable(String key) {
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
        return DateTime.now().toIso8601String().split('T').first;
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
  String _recomposeParagraphText(XmlElement paragraph) {
    return paragraph.findAllElements('w:t').map((e) => e.text).join('');
  }

  XmlElement _createTableCell(String text) {
    return XmlElement(XmlName('w:tc'), [], [
      XmlElement(XmlName('w:p'), [], [
        XmlElement(XmlName('w:r'), [], [
          XmlElement(XmlName('w:t'), [], [XmlText(text)])
        ])
      ])
    ]);
  }

  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  String getValue(Map<String, dynamic> data, List<String> keys, [String defaultValue = '']) {
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

  void stopListening() {
    _speechRecognizer.stop();
    _isListening = false;
    notifyListeners();
    debugPrint('Reconnaissance vocale arrêtée.');
  }

  void setTtsEnabled(bool enabled) {
    _ttsEnabled = enabled;
    notifyListeners();
    debugPrint('Synthèse vocale ${enabled ? 'activée' : 'désactivée'}');
  }

  bool get isTtsEnabled => _ttsEnabled;
  bool get isListening => _isListening;

  //----------------------------------------------------------------------------
  // Gestion de la validation des messages
  //----------------------------------------------------------------------------
Future<void> handleValidation(String messageId, MessageStatus status) async {
  try {
    final workspaceId = await _getWorkspaceId();
    final messageRef = _firestore.collection('workspaces').doc(workspaceId).collection('chat_messages').doc(messageId);
    
    await _firestore.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(messageRef);
      if (!snapshot.exists) throw Exception("Message non trouvé");
      
      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
      if (data['status'] == 'validated') return;

      transaction.update(messageRef, {
        'status': status.toString().split('.').last,
        'version': (data['version'] ?? 0) + 1,
      });
    });

    // Déclencher IMMÉDIATEMENT l'exécution des actions
    if (status == MessageStatus.validated) {
      DocumentSnapshot updatedDoc = await messageRef.get();
      ChatMessage updatedMessage = ChatMessage.fromFirestore(updatedDoc);
      
      debugPrint('[EXECUTION] Début traitement pour message ${updatedMessage.id}');
      await executeActionsFromMessage(updatedMessage);
    }

  } catch (e) {
    debugPrint('[ERREUR VALIDATION] $e');
  }
}


  //----------------------------------------------------------------------------
  // HANDLERS POUR LES DIFFÉRENTES ACTIONS (rendu public)
  //----------------------------------------------------------------------------
  Future<void> handleCreateTask(Map<String, dynamic> data) async {
    try {
      final workspaceId = await _getWorkspaceId();
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('Utilisateur non connecté pour create_task.');
        return;
      }
      DateTime dueDate;
      if (data['dueDate'] != null) {
        dueDate = DateTime.parse(data['dueDate']).toLocal();
      } else {
        dueDate = DateTime.now().add(const Duration(days: 1));
      }
      String priority = data['priority'] ?? 'Low';
      if (!['Low', 'Medium', 'High'].contains(priority)) {
        priority = 'Low';
      }
      await _firestore.runTransaction((transaction) async {
        DocumentReference taskRef = _firestore
            .collection('workspaces')
            .doc(workspaceId)
            .collection('tasks')
            .doc();
        transaction.set(taskRef, {
          'title': data['title'] ?? 'Nouvelle tâche',
          'description': data['description'] ?? '',
          'dueDate': Timestamp.fromDate(dueDate),
          'assignee': currentUser.uid,
          'status': 'pending',
          'priority': priority,
          'timestamp': FieldValue.serverTimestamp(),
          'requiresValidation': true,
          'validationStatus': 'pending',
          'createdBy': currentUser.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'version': 0,
        });
      });
      debugPrint('Tâche créée avec succès.');
    } catch (e) {
      debugPrint('Erreur lors de la création de la tâche: $e');
    }
  }

  Future<void> handleUpdateTask(Map<String, dynamic> data) async {
    try {
      final workspaceId = await _getWorkspaceId();
      final taskId = data['taskId'];
      if (taskId == null) {
        debugPrint('ID de tâche manquant pour la mise à jour.');
        return;
      }
      DocumentReference taskRef = _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('tasks')
          .doc(taskId);
      await _firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(taskRef);
        if (!snapshot.exists) {
          throw Exception("La tâche n'existe pas!");
        }
        Map<String, dynamic> currentTask = snapshot.data() as Map<String, dynamic>;
        int currentVersion = currentTask['version'] ?? 0;
        int newVersion = currentVersion + 1;
        Map<String, dynamic> updateData = {};
        if (data.containsKey('title')) updateData['title'] = data['title'];
        if (data.containsKey('description')) updateData['description'] = data['description'];
        if (data.containsKey('dueDate')) updateData['dueDate'] = Timestamp.fromDate(DateTime.parse(data['dueDate']));
        if (data.containsKey('priority')) updateData['priority'] = data['priority'];
        if (data.containsKey('status')) updateData['status'] = data['status'];
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

  Future<void> handleDeleteTask(Map<String, dynamic> data) async {
    try {
      final workspaceId = await _getWorkspaceId();
      final taskId = data['taskId'];
      if (taskId == null) {
        debugPrint('ID de tâche manquant pour la suppression.');
        return;
      }
      DocumentReference taskRef = _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('tasks')
          .doc(taskId);
      await _firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(taskRef);
        if (!snapshot.exists) {
          throw Exception("La tâche n'existe pas!");
        }
        transaction.delete(taskRef);
        debugPrint('Tâche supprimée avec succès.');
      });
    } catch (e) {
      debugPrint('Erreur lors de la suppression de la tâche: $e');
    }
  }

  Future<void> handleCreateEvent(Map<String, dynamic> data) async {
    try {
      final workspaceId = await _getWorkspaceId();
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('Utilisateur non connecté pour create_event.');
        return;
      }
      String title = data['title'] ?? 'Nouvel événement';
      String description = data['description'] ?? '';
      String dateStr = data['date'] ?? DateTime.now().toIso8601String();
      DateTime date = DateTime.parse(dateStr).toLocal();
      await _firestore.runTransaction((transaction) async {
        DocumentReference eventRef = _firestore
            .collection('workspaces')
            .doc(workspaceId)
            .collection('events')
            .doc();
        transaction.set(eventRef, {
          'title': title,
          'description': description,
          'date': Timestamp.fromDate(date),
          'userId': currentUser.uid,
          'timestamp': FieldValue.serverTimestamp(),
          'version': 0,
        });
      });
      debugPrint('Événement créé avec succès.');
    } catch (e) {
      debugPrint('Erreur lors de la création de l\'événement: $e');
    }
  }

  Future<void> handleUpdateEvent(Map<String, dynamic> data) async {
    try {
      final workspaceId = await _getWorkspaceId();
      final eventId = data['eventId'];
      if (eventId == null) {
        debugPrint('ID d\'événement manquant pour la mise à jour.');
        return;
      }
      DocumentReference eventRef = _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('events')
          .doc(eventId);
      await _firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(eventRef);
        if (!snapshot.exists) {
          throw Exception("L'événement n'existe pas!");
        }
        Map<String, dynamic> currentEvent = snapshot.data() as Map<String, dynamic>;
        int currentVersion = currentEvent['version'] ?? 0;
        int newVersion = currentVersion + 1;
        Map<String, dynamic> updateData = {};
        if (data.containsKey('title')) updateData['title'] = data['title'];
        if (data.containsKey('description')) updateData['description'] = data['description'];
        if (data.containsKey('date')) updateData['date'] = Timestamp.fromDate(DateTime.parse(data['date']));
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

  Future<void> handleDeleteEvent(Map<String, dynamic> data) async {
    try {
      final workspaceId = await _getWorkspaceId();
      final eventId = data['eventId'];
      if (eventId == null) {
        debugPrint('ID d\'événement manquant pour la suppression.');
        return;
      }
      DocumentReference eventRef = _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('events')
          .doc(eventId);
      await _firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(eventRef);
        if (!snapshot.exists) {
          throw Exception("L'événement n'existe pas!");
        }
        transaction.delete(eventRef);
        debugPrint('Événement supprimé avec succès.');
      });
    } catch (e) {
      debugPrint('Erreur lors de la suppression de l\'événement: $e');
    }
  }

  Future<void> handleCreateFolderWithDocument(Map<String, dynamic> data) async {
    try {
      final workspaceId = await _getWorkspaceId();
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('Utilisateur non connecté.');
        return;
      }
      await _firestore.runTransaction((transaction) async {
        DocumentReference folderRef = _firestore
            .collection('workspaces')
            .doc(workspaceId)
            .collection('folders')
            .doc();
        transaction.set(folderRef, {
          'name': data['folderName'] ?? 'Nouveau Dossier',
          'userId': currentUser.uid,
          'timestamp': FieldValue.serverTimestamp(),
          'version': 0,
        });
        debugPrint('Dossier "${data['folderName']}" créé avec succès.');
        Map<String, dynamic> documentData = data['document'] ?? {};
        String documentTitle = documentData['title'] ?? 'Nouveau Document';
        String documentContent = documentData['content'] ?? '';
        String format = documentData['format'] ?? 'txt';
        Uint8List contentBytes;
        String fileExtension;
        if (format.toLowerCase() == 'doc') {
          contentBytes = Uint8List.fromList(utf8.encode(documentContent));
          fileExtension = 'docx';
        } else {
          contentBytes = Uint8List.fromList(utf8.encode(documentContent));
          fileExtension = 'txt';
        }
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('workspaces/$workspaceId/documents/${folderRef.id}/$documentTitle.$fileExtension');
        await storageRef.putData(contentBytes);
        final downloadURL = await storageRef.getDownloadURL();
        DocumentReference docRef = _firestore
            .collection('workspaces')
            .doc(workspaceId)
            .collection('documents')
            .doc();
        transaction.set(docRef, {
          'title': documentTitle,
          'type': fileExtension,
          'url': downloadURL,
          'folderId': folderRef.id,
          'timestamp': FieldValue.serverTimestamp(),
          'version': 0,
        });
        debugPrint('Document "$documentTitle.$fileExtension" créé et uploadé avec succès dans le dossier "${data['folderName']}".');
      });
    } catch (e) {
      debugPrint('Erreur lors de la création du dossier et du document: $e');
    }
  }

 Future<void> handleAddContact(Map<String, dynamic> data) async {
  try {
    final workspaceId = await _getWorkspaceId();
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      debugPrint('Utilisateur non connecté.');
      return;
    }
    String firstName = data['firstName'] ?? 'Prénom inconnu';
    String lastName = data['lastName'] ?? 'Nom de famille inconnu';
    String email = data['email'] ?? '';
    String rawPhone = data['phone'] ?? '';
    String address = data['address'] ?? '';
    String company = data['company'] ?? '';
    String externalInfo = data['externalInfo'] ?? '';
    debugPrint('Données reçues pour le contact: firstName=$firstName, lastName=$lastName, email=$email, phone=$rawPhone, company=$company');

    // Validation de l'email
    if (email.isNotEmpty && !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      debugPrint('Format d\'email invalide pour le contact "$firstName $lastName": $email');
      return;
    }

    // Normalisation et validation du téléphone
    String phone = _normalizePhoneNumber(rawPhone);
    final RegExp phoneRegex = RegExp(r'^(?:\+33\s?|0)?[1-9]\d{0,2}(?:[\s.-]?\d{2}){0,4}$');
    if (phone.isNotEmpty && !phoneRegex.hasMatch(phone)) {
      debugPrint('Format de téléphone invalide pour le contact "$firstName $lastName": $phone. Utilisation sans téléphone.');
      phone = '';
    } else {
      debugPrint('Numéro de téléphone accepté après normalisation: $phone');
    }

    await _firestore.runTransaction((transaction) async {
      DocumentReference contactRef = _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('contacts')
          .doc();
      Map<String, dynamic> contactData = {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'userId': currentUser.uid,
        'address': address,
        'company': company,
        'externalInfo': externalInfo,
        'timestamp': FieldValue.serverTimestamp(),
        'version': 0,
      };
      debugPrint('Données du contact avant enregistrement: $contactData');
      transaction.set(contactRef, contactData);
      debugPrint('Contact "$firstName $lastName" ajouté avec ID: ${contactRef.id}');
    });
  } catch (e) {
    debugPrint('Erreur lors de l\'ajout du contact: $e');
  }
}

Future<void> handleCreateFolderAndAddContact(Map<String, dynamic> data) async {
  try {
    final workspaceId = await _getWorkspaceId();
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      debugPrint('Utilisateur non connecté.');
      return;
    }
    String folderName = data['folderName'] ?? 'Nouveau Dossier';
    Map<String, dynamic> contactData = data['contact'] ?? {};

    await _firestore.runTransaction((transaction) async {
      // Création du dossier
      DocumentReference folderRef = _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('folders')
          .doc();
      transaction.set(folderRef, {
        'name': folderName,
        'userId': currentUser.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'version': 0,
      });
      debugPrint('Dossier "$folderName" créé avec ID: ${folderRef.id}');

      // Préparation des données du contact
      String firstName = contactData['firstName'] ?? 'Prénom inconnu';
      String lastName = contactData['lastName'] ?? 'Nom de famille inconnu';
      String email = contactData['email'] ?? '';
      String rawPhone = contactData['phone'] ?? '';
      String address = contactData['address'] ?? '';
      String company = contactData['company'] ?? '';
      String externalInfo = contactData['externalInfo'] ?? '';

      String phone = _normalizePhoneNumber(rawPhone);
      final RegExp phoneRegex = RegExp(r'^(?:\+33\s?|0)?[1-9]\d{0,2}(?:[\s.-]?\d{2}){0,4}$');
      if (phone.isNotEmpty && !phoneRegex.hasMatch(phone)) {
        debugPrint('Format de téléphone invalide pour "$firstName $lastName": $phone. Utilisation sans téléphone.');
        phone = '';
      } else {
        debugPrint('Numéro de téléphone accepté après normalisation: $phone');
      }

      if (email.isNotEmpty && !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
        debugPrint('Format d\'email invalide pour "$firstName $lastName". Utilisation sans email.');
        email = '';
      }

      // Création du contact
      DocumentReference contactRef = _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('contacts')
          .doc();
      Map<String, dynamic> contactPayload = {
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
        'version': 0,
      };
      debugPrint('Données du contact avant enregistrement: $contactPayload');
      transaction.set(contactRef, contactPayload);
      debugPrint('Contact "$firstName $lastName" ajouté avec ID: ${contactRef.id} dans le dossier "$folderName" (folderId: ${folderRef.id}).');
    });

    // Vérification post-transaction
    DocumentSnapshot folderSnap = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('folders')
        .where('name', isEqualTo: folderName)
        .limit(1)
        .get()
        .then((snap) => snap.docs.first);
    debugPrint('Vérification dossier après transaction: ${folderSnap.data()}');

    QuerySnapshot contactSnap = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('contacts')
        .where('firstName', isEqualTo: contactData['firstName'])
        .where('lastName', isEqualTo: contactData['lastName'])
        .limit(1)
        .get();
    if (contactSnap.docs.isNotEmpty) {
      debugPrint('Vérification contact après transaction: ${contactSnap.docs.first.data()}');
    } else {
      debugPrint('Contact non trouvé après transaction.');
    }
  } catch (e) {
    debugPrint('Erreur lors de la création du dossier et de l\'ajout du contact: $e');
    rethrow;
  }
}

// Méthode pour normaliser le numéro de téléphone
String _normalizePhoneNumber(String phone) {
  if (phone.isEmpty) return '';
  // Supprimer tous les caractères non numériques sauf le "+"
  String cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  
  // Si le numéro commence par "00", remplacer par "+"
  if (cleaned.startsWith('00')) {
    cleaned = '+' + cleaned.substring(2);
  }
  
  // Si le numéro commence par "+33" suivi d'un "0", retirer le "0"
  if (cleaned.startsWith('+330')) {
    cleaned = '+33' + cleaned.substring(4);
  } else if (cleaned.startsWith('+33')) {
    // Si ça commence par "+33" mais pas un "0", on garde tel quel
  } else if (cleaned.length == 9 && RegExp(r'^[1-9]').hasMatch(cleaned)) {
    // Si c'est un numéro français de 9 chiffres commençant par 1-9, ajouter "0"
    cleaned = '0$cleaned';
  }

  debugPrint('Numéro normalisé: $cleaned');
  return cleaned;
}
  //----------------------------------------------------------------------------
  // 13) MÉTHODE POUR VÉRIFIER SI UNE CHAÎNE EST UN JSON VALIDE
  //----------------------------------------------------------------------------
  bool isJson(String str) {
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
  Future<void> executeActionsFromMessage(ChatMessage message) async {
    if (message.status != MessageStatus.validated) {
      debugPrint('Message non validé: ${message.id}');
      return;
    }
    List<AIActionType> executedActions = [];
    bool actionExecuted = await _tryExecuteAction(message.content, executedActions);
    if (actionExecuted) {
      debugPrint('Actions exécutées pour le message: ${message.id}');
      for (var action in executedActions) {
        _actionController.add(ActionEvent(actionType: action));
      }
    } else {
      debugPrint('Aucune action exécutée pour le message: ${message.id}');
    }
  }

  Future<void> modifyAndExecuteActions(ChatMessage message, String newContent) async {
    if (!isJson(newContent)) {
      throw Exception('Le contenu modifié doit être un JSON valide.');
    }
    await updateMessage(message.id, newContent, isDraft: false);
    final workspaceId = await _getWorkspaceId();
    DocumentSnapshot updatedDoc = await _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('chat_messages')
        .doc(message.id)
        .get();
    ChatMessage updatedMessage = ChatMessage.fromFirestore(updatedDoc);
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
  Future<void> updateMessage(String messageId, String newContent, {bool isDraft = false}) async {
    try {
      final workspaceId = await _getWorkspaceId();
      DocumentReference messageRef = _firestore.collection('workspaces').doc(workspaceId).collection('chat_messages').doc(messageId);
      DocumentSnapshot doc = await messageRef.get();
      if (!doc.exists) {
        debugPrint('Message avec ID $messageId non trouvé.');
        throw Exception('Message non trouvé.');
      }
      ChatMessage currentMessage = ChatMessage.fromFirestore(doc);
      Map<String, dynamic> updateData = {
        'content': newContent,
        'timestamp': FieldValue.serverTimestamp(),
        'isDraft': isDraft,
        'version': (currentMessage.version ?? 0) + 1,
      };
      if (!isDraft) {
        updateData['status'] = 'validated';
      }
      await messageRef.update(updateData);
      debugPrint('Message avec ID $messageId mis à jour avec succès.');
      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('chat_messages_history')
          .add({
        'messageId': messageId,
        'newContent': newContent,
        'timestamp': FieldValue.serverTimestamp(),
        'modifiedBy': _auth.currentUser?.uid ?? 'unknown',
        'isDraft': isDraft,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Erreur lors de la mise à jour du message: $e');
      throw Exception('Erreur lors de la mise à jour du message: $e');
    }
  }

  //----------------------------------------------------------------------------
  // Nettoyage et extraction des blocs JSON de la réponse de l'IA
  //----------------------------------------------------------------------------
  List<Map<String, dynamic>> _extractJsonResponses(String response) {
    response = response.replaceAll(RegExp(r'```json\s*'), '');
    response = response.replaceAll(RegExp(r'\s*```'), '');
    try {
      final List<dynamic> jsonList = json.decode(response);
      return jsonList.cast<Map<String, dynamic>>();
    } catch (e) {
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
  // Dispose des ressources
  //----------------------------------------------------------------------------
  @override
  void dispose() {
    _speechRecognizer.cancel();
    _flutterTts.stop();
    _actionController.close();
    super.dispose();
  }
}
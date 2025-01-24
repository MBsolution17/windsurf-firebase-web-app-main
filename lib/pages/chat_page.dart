// lib/pages/chat_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';

class ChatPage extends StatefulWidget {
  final String channelId;
  final String channelName;
  final bool isVoiceChannel;

  const ChatPage({
    super.key,
    required this.channelId,
    required this.channelName,
    this.isVoiceChannel = false,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  // Clé API OpenAI (ATTENTION : Ne pas exposer la clé en production)
  static const String apiKey =
      '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';
  final String apiUrl = 'https://api.openai.com/v1/chat/completions';

  // Fonction pour obtenir la réponse de ChatGPT avec contexte
  Future<String> getChatGPTResponse(List<Map<String, dynamic>> messages) async {
    try {
      print('Envoi des messages à ChatGPT: $messages');
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo', // Vérifiez que le modèle est correct
          'messages': messages,
          'max_tokens': 150, // Ajustez si nécessaire
        }),
      );

      print('Réponse de l\'API: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'].trim();
      } else if (response.statusCode == 429) {
        // Gestion spécifique de l'erreur 429
        return 'Erreur : Vous avez dépassé votre quota. Veuillez vérifier vos détails de facturation sur OpenAI.';
      } else {
        throw Exception(
            'Erreur lors de la récupération de la réponse ChatGPT : ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Erreur : $e');
      return 'Erreur : Impossible de récupérer la réponse de ChatGPT.';
    }
  }

  // Fonction pour envoyer un message
  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isLoading) return;

    setState(() => _isLoading = true);

    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Utilisateur non authentifié')),
      );
      return;
    }

    try {
      final userMessage = _messageController.text.trim();
      _messageController.clear();

      // Créer un ChatMessage pour l'utilisateur
      final chatMessage = ChatMessage(
        id: '', // ID généré par Firestore
        content: userMessage,
        type: MessageType.user,
        userId: user.uid, // Ajout du userId
        userEmail: user.email ?? 'Utilisateur Inconnu', // Ajout du userEmail
        status: MessageStatus.validated, // Statut validé
      );

      // Ajouter le message de l'utilisateur dans Firestore
      await FirebaseFirestore.instance
          .collection('channels')
          .doc(widget.channelId)
          .collection('messages')
          .add(chatMessage.toMap());

      setState(() => _isLoading = false);

      // Auto-scroll vers le dernier message
      _scrollController.animateTo(
        0.0,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } catch (e) {
      print('Erreur : $e');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'envoi du message: $e')),
      );
    }
  }

  // Fonction pour gérer les requêtes ChatGPT avec contexte
  void _queryChatGPT() async {
    TextEditingController queryController = TextEditingController();

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Ask ChatGPT'),
          content: TextField(
            controller: queryController,
            decoration: InputDecoration(hintText: 'Enter your question'),
          ),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Submit'),
              onPressed: () async {
                String query = queryController.text.trim();
                Navigator.of(context).pop(); // Fermer le dialogue immédiatement

                if (query.isNotEmpty) {
                  setState(() => _isLoading = true);
                  try {
                    print('Requête utilisateur: $query');

                    // Récupérer les derniers 10 messages pour le contexte
                    QuerySnapshot snapshot = await FirebaseFirestore.instance
                        .collection('channels')
                        .doc(widget.channelId)
                        .collection('messages')
                        .orderBy('timestamp', descending: true) // Utiliser 'timestamp' au lieu de 'createdAt'
                        .limit(10)
                        .get();

                    print('Messages récupérés: ${snapshot.docs.length}');

                    // Inverser l'ordre pour avoir les messages chronologiques
                    List<DocumentSnapshot> docs = snapshot.docs.reversed.toList();

                    // Construire le tableau des messages pour ChatGPT
                    List<Map<String, dynamic>> chatMessages = [
                      {
                        'role': 'system',
                        'content': 'Vous êtes un assistant utile.'
                      },
                    ];

                    for (var doc in docs) {
                      ChatMessage taskMessage = ChatMessage.fromFirestore(doc);
                      String userId = taskMessage.userId;
                      String text = taskMessage.content;

                      if (userId == 'ChatGPT') {
                        chatMessages.add({'role': 'assistant', 'content': text});
                      } else {
                        chatMessages.add({'role': 'user', 'content': text});
                      }
                    }

                    // Ajouter la requête actuelle de l'utilisateur
                    chatMessages.add({'role': 'user', 'content': query});

                    print('Messages envoyés à ChatGPT: $chatMessages');

                    // Obtenir la réponse de ChatGPT avec le contexte
                    String response = await getChatGPTResponse(chatMessages);

                    print('Réponse de ChatGPT: $response');

                    if (response.startsWith('Erreur')) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(response)),
                      );
                    } else {
                      // Créer un ChatMessage pour ChatGPT
                      final chatGPTMessage = ChatMessage(
                        id: '', // ID généré par Firestore
                        content: response,
                        type: MessageType.ai,
                        userId: 'ChatGPT', // Ajout du userId
                        userEmail: 'ChatGPT', // Ajout du userEmail
                        status: MessageStatus.pending_validation, // Statut pending_validation
                      );

                      // Ajouter la réponse de ChatGPT dans Firestore pour l'affichage dans le chat
                      await FirebaseFirestore.instance
                          .collection('channels')
                          .doc(widget.channelId)
                          .collection('messages')
                          .add(chatGPTMessage.toMap());

                      // Auto-scroll vers le dernier message
                      _scrollController.animateTo(
                        0.0,
                        duration: Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  } catch (e) {
                    print('Erreur : $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur : $e')),
                    );
                  } finally {
                    setState(() => _isLoading = false);
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  /// Affiche une boîte de dialogue pour modifier le message.
  ///
  /// [message] : Le message à modifier.
  Future<String?> _showEditMessageDialog(ChatMessage message) async {
    final TextEditingController controller = TextEditingController(text: message.content);
    String? newContent;
    
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Modifier le message'),
          content: TextField(
            controller: controller,
            maxLines: 5,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Entrez votre message modifié',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Annuler'),
            ),
            TextButton(
              onPressed: () async {
                newContent = controller.text.trim();
                if (newContent!.isNotEmpty && newContent != message.content) {
                  try {
                    // Mettre à jour le message dans Firestore
                    await FirebaseFirestore.instance
                        .collection('channels')
                        .doc(widget.channelId)
                        .collection('messages')
                        .doc(message.id)
                        .update({
                          'content': newContent,
                          'status': 'modified',
                          'timestamp': FieldValue.serverTimestamp(),
                        });
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Message modifié avec succès')),
                    );
                  } catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur lors de la modification : $e')),
                    );
                  }
                } else {
                  Navigator.pop(context);
                }
              },
              child: Text('Enregistrer'),
            ),
          ],
        );
      },
    );
    return newContent;
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channelName),
        actions: [
          if (widget.isVoiceChannel)
            IconButton(
              icon: const Icon(Icons.mic),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Voice chat coming soon!')),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('channels')
                  .doc(widget.channelId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true) // Utiliser 'timestamp' au lieu de 'createdAt'
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Erreur: ${snapshot.error}'));
                } else if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Aucun message trouvé'));
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    // Passer directement le DocumentSnapshot à fromFirestore
                    final message = ChatMessage.fromFirestore(messages[index]);
                    final isCurrentUser = message.userId ==
                        Provider.of<AuthService>(context, listen: false)
                            .currentUser
                            ?.uid;
                    final isChatGPT = message.userId == 'ChatGPT';

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      child: Align(
                        alignment: isCurrentUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isCurrentUser
                                ? Colors.blue
                                : (isChatGPT
                                    ? Colors.green[300]
                                    : Colors.grey[300]),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message.userEmail,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isCurrentUser
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                message.content,
                                style: TextStyle(
                                  color: isCurrentUser
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                              SizedBox(height: 4),
                              // Affichage du statut du message
                              Text(
                                'Statut: ${message.status.toString().split('.').last}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isCurrentUser
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                              ),
                              // Boutons de validation pour les messages en attente
                              if (message.status == MessageStatus.pending_validation)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      ),
                                      onPressed: () async {
                                        await FirebaseFirestore.instance
                                            .collection('channels')
                                            .doc(widget.channelId)
                                            .collection('messages')
                                            .doc(message.id)
                                            .update({
                                              'status': MessageStatus.validated.toString(),
                                              'timestamp': FieldValue.serverTimestamp(),
                                            });
                                      },
                                      child: Text('Valider'),
                                    ),
                                    SizedBox(width: 8),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      ),
                                      onPressed: () async {
                                        await FirebaseFirestore.instance
                                            .collection('channels')
                                            .doc(widget.channelId)
                                            .collection('messages')
                                            .doc(message.id)
                                            .update({
                                              'status': MessageStatus.rejected.toString(),
                                              'timestamp': FieldValue.serverTimestamp(),
                                            });
                                      },
                                      child: Text('Rejeter'),
                                    ),
                                  ],
                                ),
                              // Bouton "Modifier" et indicateur de modification
                              if ((isCurrentUser || isChatGPT) && message.status != MessageStatus.pending_validation)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (message.status == MessageStatus.modified)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          'Modifié',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isCurrentUser
                                                ? Colors.white70
                                                : Colors.black54,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () async {
                                          try {
                                            // Pour les messages AI, limiter la modification au contenu seulement
                                            if (isChatGPT) {
                                              final newContent = await _showEditMessageDialog(message);
                                              if (newContent != null && newContent != message.content) {
                                                await FirebaseFirestore.instance
                                                    .collection('channels')
                                                    .doc(widget.channelId)
                                                    .collection('messages')
                                                    .doc(message.id)
                                                    .update({
                                                      'content': newContent,
                                                      'status': MessageStatus.modified.toString(),
                                                      'timestamp': FieldValue.serverTimestamp(),
                                                    });
                                              }
                                            } else {
                                              await _showEditMessageDialog(message);
                                            }
                                          } catch (e) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Erreur lors de la modification : $e')),
                                            );
                                          }
                                        },
                                        icon: Icon(Icons.edit,
                                            size: 16, color: Colors.white),
                                        label: Text(
                                          'Modifier',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Tapez un message...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _queryChatGPT,
                  child: Text('Query ChatGPT'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

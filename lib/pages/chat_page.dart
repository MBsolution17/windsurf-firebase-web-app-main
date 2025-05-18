// lib/pages/chat_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:html' as html;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_web_app/theme_provider.dart'; // Import du ThemeProvider

import '../services/auth_service.dart';
import '../services/ai_service.dart';
import '../models/chat_message.dart' as myChat;

// Constantes pour l'API OpenAI
const String kApiKey =
    '';
const String kApiUrl = 'https://api.openai.com/v1/chat/completions';

/// =========================================================
/// Classe pour désactiver l'effet d'overscroll (glow)
/// =========================================================
class NoGlowScrollBehavior extends ScrollBehavior {
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

/// =========================================================
/// Déclaration de la classe Participant
/// =========================================================
class Participant {
  final String id;
  final String name;
  final String profileImageUrl;
  bool videoEnabled;
  MediaStream? stream;

  Participant({
    required this.id,
    required this.name,
    required this.profileImageUrl,
    this.videoEnabled = false,
    this.stream,
  });
}

/// =========================================================
/// Page d'appel vocal (VoiceCallPage)
/// =========================================================
class VoiceCallPage extends StatefulWidget {
  final String channelId;
  final String channelName;
  const VoiceCallPage({
    Key? key,
    required this.channelId,
    required this.channelName,
  }) : super(key: key);

  @override
  _VoiceCallPageState createState() => _VoiceCallPageState();
}

class _VoiceCallPageState extends State<VoiceCallPage> {
  MediaStream? _localStream;
  bool _isMuted = false;
  bool _isListening = false;
  String _chatGPTResponse = '';
  String _lastRecognizedText = '';

  stt.SpeechToText _speech = stt.SpeechToText();
  FlutterTts _flutterTts = FlutterTts();

  List<html.MediaDeviceInfo> _audioInputDevices = [];
  String? _selectedAudioDeviceId;

  @override
  void initState() {
    super.initState();
    _enumerateAudioDevices();
    _initLocalStream();
  }

  Future<void> _enumerateAudioDevices() async {
    try {
      final devices = await html.window.navigator.mediaDevices!
          .enumerateDevices()
          .then((list) => list.cast<html.MediaDeviceInfo>());
      setState(() {
        _audioInputDevices =
            devices.where((device) => device.kind == 'audioinput').toList();
        if (_audioInputDevices.isNotEmpty) {
          _selectedAudioDeviceId = _audioInputDevices.first.deviceId;
        }
      });
    } catch (e) {
      debugPrint("Erreur lors de l'énumération des périphériques audio: $e");
    }
  }

  Future<void> _initLocalStream() async {
    final mediaConstraints = {
      'audio': _selectedAudioDeviceId != null
          ? {'deviceId': _selectedAudioDeviceId}
          : true,
      'video': false,
    };
    try {
      MediaStream stream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      setState(() {
        _localStream = stream;
      });
    } catch (e) {
      debugPrint('Erreur lors de la récupération du flux audio: $e');
    }
  }

  void _toggleMute() {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = !track.enabled;
      });
      setState(() {
        _isMuted = !_isMuted;
      });
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      _speech.stop();
      setState(() {
        _isListening = false;
      });
      if (_lastRecognizedText.isNotEmpty) {
        final aiService = Provider.of<AIService>(context, listen: false);
        String response = await aiService
            .sendMessage(_lastRecognizedText)
            .then((aiMsg) => aiMsg.content);
        setState(() {
          _chatGPTResponse = response;
        });
        await _flutterTts.speak(response);
        await showDialog(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: Text('Réponse de l\'IA',
                  style: Theme.of(context).textTheme.titleMedium),
              content: Text(response,
                  style: Theme.of(context).textTheme.bodyLarge),
              actions: [
                TextButton(
                  child: const Text('Fermer'),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      }
    } else {
      bool available = await _speech.initialize();
      if (available) {
        setState(() {
          _isListening = true;
          _lastRecognizedText = '';
          _chatGPTResponse = "Je vous écoute, dites ce que vous voulez";
        });
        _speech.listen(
          onResult: (result) {
            _lastRecognizedText = result.recognizedWords;
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'La reconnaissance vocale n\'est pas disponible.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        );
      }
    }
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sélectionnez votre microphone',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              DropdownButton<String>(
                isExpanded: true,
                underline: Container(),
                value: _selectedAudioDeviceId,
                onChanged: (String? newDeviceId) async {
                  setState(() {
                    _selectedAudioDeviceId = newDeviceId;
                  });
                  await _initLocalStream();
                  Navigator.pop(context);
                },
                items: _audioInputDevices.map((device) {
                  return DropdownMenuItem<String>(
                    value: device.deviceId,
                    child: Text(
                      device.label ?? 'Microphone ${device.deviceId}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _localStream?.dispose();
    _speech.stop();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channelId.isEmpty) {
      return Scaffold(
        body: Center(
            child: Text("Erreur : channelId est vide",
                style: Theme.of(context).textTheme.bodyLarge)),
      );
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Appel vocal - ${widget.channelName}',
            style: Theme.of(context).textTheme.titleLarge),
        actions: [
          IconButton(
            icon: Icon(Icons.settings,
                color: Theme.of(context).iconTheme.color),
            onPressed: _showSettings,
            tooltip: 'Options microphone',
          ),
        ],
      ),
      body: _localStream == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_circle,
                      size: 120,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[400]
                          : Colors.grey[700],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Appel vocal en cours...',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _toggleListening,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(_isListening
                          ? 'Arrêter l\'écoute'
                          : 'Démarrer l\'écoute'),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _chatGPTResponse,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: Icon(
                            _isMuted ? Icons.mic_off : Icons.mic,
                            size: 32,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          onPressed: _toggleMute,
                        ),
                        const SizedBox(width: 40),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Terminer l\'appel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// =========================================================
/// Page d'appel vidéo (VideoCallPage)
/// =========================================================
class VideoCallPage extends StatefulWidget {
  final String channelId;
  final String channelName;
  const VideoCallPage({
    Key? key,
    required this.channelId,
    required this.channelName,
  }) : super(key: key);

  @override
  _VideoCallPageState createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  bool _isMuted = false;
  bool _localVideoEnabled = false;

  List<html.MediaDeviceInfo> _audioInputDevices = [];
  List<html.MediaDeviceInfo> _videoInputDevices = [];
  String? _selectedAudioDeviceId;
  String? _selectedVideoDeviceId;

  List<Participant> _participants = [];

  stt.SpeechToText _speech = stt.SpeechToText();
  FlutterTts _flutterTts = FlutterTts();
  bool _isChatGPTQuerying = false;
  String _lastRecognizedText = '';
  String _chatGPTResponse = '';

  final TextEditingController _chatMessageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  bool _showChat = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _enumerateDevices().then((_) => _initLocalStream());
    _initParticipants();
  }

  void _initParticipants() {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    final String profileImageUrl =
        currentUser?.photoURL ?? 'https://via.placeholder.com/150';
    _participants.add(Participant(
      id: 'local',
      name: 'Moi',
      profileImageUrl: profileImageUrl,
      videoEnabled: _localVideoEnabled,
      stream: _localStream,
    ));
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
  }

  Future<void> _enumerateDevices() async {
    try {
      final devices = await html.window.navigator.mediaDevices!
          .enumerateDevices()
          .then((list) => list.cast<html.MediaDeviceInfo>());
      setState(() {
        _audioInputDevices =
            devices.where((device) => device.kind == 'audioinput').toList();
        _videoInputDevices =
            devices.where((device) => device.kind == 'videoinput').toList();
        if (_audioInputDevices.isNotEmpty) {
          _selectedAudioDeviceId = _audioInputDevices.first.deviceId;
        }
        if (_videoInputDevices.isNotEmpty) {
          _selectedVideoDeviceId = _videoInputDevices.first.deviceId;
        }
      });
    } catch (e) {
      debugPrint("Erreur lors de l'énumération des périphériques: $e");
    }
  }

  Future<void> _initLocalStream() async {
    final mediaConstraints = {
      'audio': _selectedAudioDeviceId != null
          ? {'deviceId': _selectedAudioDeviceId}
          : true,
      'video': _localVideoEnabled && _selectedVideoDeviceId != null
          ? {
              'deviceId': {'exact': _selectedVideoDeviceId},
              'width': {'min': 640},
              'height': {'min': 480},
              'frameRate': {'min': 30},
            }
          : false,
    };

    try {
      MediaStream stream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = stream;
      setState(() {
        _localStream = stream;
        final localIndex =
            _participants.indexWhere((participant) => participant.id == 'local');
        if (localIndex != -1) {
          _participants[localIndex].stream = stream;
          _participants[localIndex].videoEnabled = _localVideoEnabled;
        }
      });
    } catch (e) {
      debugPrint('Erreur lors de la récupération du flux vidéo/audio: $e');
    }
  }

  Future<void> _toggleLocalVideo() async {
    setState(() {
      _localVideoEnabled = !_localVideoEnabled;
    });
    if (!_localVideoEnabled) {
      if (_localStream != null) {
        _localStream!.getVideoTracks().forEach((track) {
          track.enabled = false;
        });
      }
    } else {
      await _initLocalStream();
    }
    final localIndex =
        _participants.indexWhere((participant) => participant.id == 'local');
    if (localIndex != -1) {
      _participants[localIndex].videoEnabled = _localVideoEnabled;
      _participants[localIndex].stream = _localVideoEnabled ? _localStream : null;
    }
  }

  void _toggleMute() {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = !track.enabled;
      });
      setState(() {
        _isMuted = !_isMuted;
      });
    }
  }

  void _showDeviceSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Paramètres des périphériques',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.mic, color: Colors.blueAccent),
                title: DropdownButton<String>(
                  isExpanded: true,
                  underline: Container(),
                  value: _selectedAudioDeviceId,
                  onChanged: (String? newDeviceId) async {
                    setState(() {
                      _selectedAudioDeviceId = newDeviceId;
                    });
                    await _initLocalStream();
                    Navigator.pop(context);
                  },
                  items: _audioInputDevices.map((device) {
                    return DropdownMenuItem<String>(
                      value: device.deviceId,
                      child: Text(
                        device.label ?? 'Microphone ${device.deviceId}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    );
                  }).toList(),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.videocam, color: Colors.redAccent),
                title: DropdownButton<String>(
                  isExpanded: true,
                  underline: Container(),
                  value: _selectedVideoDeviceId,
                  onChanged: (String? newDeviceId) async {
                    setState(() {
                      _selectedVideoDeviceId = newDeviceId;
                    });
                    await _initLocalStream();
                    Navigator.pop(context);
                  },
                  items: _videoInputDevices.map((device) {
                    return DropdownMenuItem<String>(
                      value: device.deviceId,
                      child: Text(
                        device.label ?? 'Caméra ${device.deviceId}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _listenForQuery() async {
    if (_isChatGPTQuerying) {
      _speech.stop();
      setState(() {
        _isChatGPTQuerying = false;
      });
      return;
    }
    setState(() {
      _chatGPTResponse = "Je vous écoute, dites ce que vous voulez";
    });
    bool available = await _speech.initialize();
    if (available) {
      setState(() {
        _isChatGPTQuerying = true;
        _lastRecognizedText = '';
      });
      _speech.listen(
        onResult: (result) async {
          if (result.finalResult) {
            String query = result.recognizedWords;
            _speech.stop();
            final aiService = Provider.of<AIService>(context, listen: false);
            String response = await aiService
                .sendMessage(query)
                .then((aiMsg) => aiMsg.content);
            setState(() {
              _isChatGPTQuerying = false;
              _chatGPTResponse = response;
            });
            await _flutterTts.speak(response);
            await showDialog(
              context: context,
              builder: (BuildContext dialogContext) {
                return AlertDialog(
                  title: Text('Réponse de l\'IA',
                      style: Theme.of(context).textTheme.titleMedium),
                  content: Text(response,
                      style: Theme.of(context).textTheme.bodyLarge),
                  actions: [
                    TextButton(
                      child: const Text('Fermer'),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                );
              },
            );
          }
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Reconnaissance vocale non disponible.',
                style: Theme.of(context).textTheme.bodyLarge)),
      );
    }
  }

  void _sendChatMessage() async {
    if (_chatMessageController.text.trim().isEmpty) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Utilisateur non authentifié',
                  style: Theme.of(context).textTheme.bodyLarge)));
      return;
    }
    final messageContent = _chatMessageController.text.trim();
    _chatMessageController.clear();
    final chatMsg = myChat.ChatMessage(
      id: '',
      content: messageContent,
      type: myChat.MessageType.user,
      userId: user.uid,
      userEmail: user.email ?? 'Utilisateur Inconnu',
      status: myChat.MessageStatus.validated,
    );
    await FirebaseFirestore.instance
        .collection('channels')
        .doc(widget.channelId)
        .collection('messages')
        .add(chatMsg.toMap());
    _chatScrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _localStream?.dispose();
    _chatMessageController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channelId.isEmpty) {
      return Scaffold(
        body: Center(
            child: Text("Erreur : channelId est vide",
                style: Theme.of(context).textTheme.bodyLarge)),
      );
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Appel vidéo - ${widget.channelName}',
            style: Theme.of(context).textTheme.titleLarge),
        actions: [
          IconButton(
            icon: Icon(Icons.settings,
                color: Theme.of(context).iconTheme.color),
            onPressed: _showDeviceSettings,
            tooltip: 'Options périphériques',
          ),
        ],
      ),
      body: Row(
        children: [
          Container(
            width: 40,
            color: Theme.of(context).dividerColor,
            child: IconButton(
              icon: Icon(_showChat ? Icons.arrow_left : Icons.arrow_right,
                  color: Theme.of(context).iconTheme.color),
              onPressed: () {
                setState(() {
                  _showChat = !_showChat;
                });
              },
            ),
          ),
          if (_showChat)
            Expanded(
              flex: 1,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                      left: BorderSide(
                          color: Theme.of(context).dividerColor ?? Colors.grey.shade300)),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('channels')
                            .doc(widget.channelId)
                            .collection('messages')
                            .orderBy('timestamp', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return Center(
                                child: Text("Aucun message",
                                    style: Theme.of(context).textTheme.bodyLarge));
                          }
                          final messages = snapshot.data!.docs;
                          final currentUser =
                              Provider.of<AuthService>(context, listen: false)
                                  .currentUser;
                          return ListView.builder(
                            controller: _chatScrollController,
                            reverse: true,
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message =
                                  myChat.ChatMessage.fromFirestore(messages[index]);
                              final isCurrentUser = message.userId == currentUser?.uid;
                              Color containerColor = Theme.of(context).cardColor;
                              if (message.userId == "ChatGPT") {
                                containerColor = Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.blueGrey[800]!
                                    : Colors.blueGrey[100]!;
                              } else if (isCurrentUser) {
                                containerColor = Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.grey[700]!
                                    : Colors.grey[400]!;
                              } else {
                                containerColor = Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.grey[600]!
                                    : Colors.grey[200]!;
                              }
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 8),
                                child: Align(
                                  alignment: isCurrentUser
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: containerColor,
                                      border: Border.all(
                                          color: Theme.of(context).dividerColor ??
                                              Colors.grey.shade400),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: message.userId == "ChatGPT"
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Assistant IA",
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: Theme.of(context)
                                                            .brightness ==
                                                        Brightness.dark
                                                        ? Colors.grey[400]
                                                        : Colors.grey[700]),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                message.content,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge,
                                              ),
                                            ],
                                          )
                                        : message.userId.isEmpty
                                            ? Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    message.userEmail,
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: Theme.of(context)
                                                                .brightness ==
                                                            Brightness.dark
                                                            ? Colors.grey[500]
                                                            : Colors.grey[700],
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    message.content,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge,
                                                  ),
                                                ],
                                              )
                                            : FutureBuilder<DocumentSnapshot>(
                                                future: FirebaseFirestore.instance
                                                    .collection('users')
                                                    .doc(message.userId)
                                                    .get(),
                                                builder: (context, userSnapshot) {
                                                  if (!userSnapshot.hasData ||
                                                      userSnapshot.data == null) {
                                                    return Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          message.userEmail,
                                                          style: TextStyle(
                                                              fontSize: 12,
                                                              color: Theme.of(
                                                                          context)
                                                                      .brightness ==
                                                                  Brightness.dark
                                                              ? Colors.grey[500]
                                                              : Colors.grey[700],
                                                              fontWeight:
                                                                  FontWeight.bold),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          message.content,
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .bodyLarge,
                                                        ),
                                                      ],
                                                    );
                                                  }
                                                  final userData =
                                                      userSnapshot.data!.data()
                                                          as Map<String, dynamic>?;
                                                  final displayName =
                                                      userData?['displayName'] ??
                                                          message.userEmail;
                                                  return Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        displayName,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Theme.of(context)
                                                                  .brightness ==
                                                              Brightness.dark
                                                              ? Colors.grey[400]
                                                              : Colors.grey[700],
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        message.content,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodyLarge,
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _chatMessageController,
                              decoration: InputDecoration(
                                hintText: 'Tapez un message...',
                                border: OutlineInputBorder(
                                  borderSide: BorderSide(
                                      color: Theme.of(context).dividerColor),
                                ),
                                fillColor: Theme.of(context)
                                    .inputDecorationTheme
                                    .fillColor,
                              ),
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.send,
                                color: Theme.of(context).iconTheme.color),
                            onPressed: _sendChatMessage,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: _showChat ? 3 : 4,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      crossAxisCount: 1,
                      childAspectRatio:
                          constraints.maxWidth / constraints.maxHeight,
                      children:
                          _participants.map(_buildParticipantTile).toList(),
                    ),
                    Positioned(
                      bottom: 20,
                      left: (constraints.maxWidth - 300) / 2,
                      child: Container(
                        width: 300,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.black.withOpacity(0.8)
                              : Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: Icon(
                                _isMuted ? Icons.mic_off : Icons.mic,
                                color: Colors.white,
                                size: 30,
                              ),
                              onPressed: _toggleMute,
                            ),
                            IconButton(
                              icon: Icon(
                                _localVideoEnabled
                                    ? Icons.videocam
                                    : Icons.videocam_off,
                                color: Colors.white,
                                size: 30,
                              ),
                              onPressed: _toggleLocalVideo,
                            ),
                            ElevatedButton.icon(
                              onPressed: _listenForQuery,
                              icon: _isChatGPTQuerying
                                  ? SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.phone, color: Colors.white),
                              label: Text(
                                _isChatGPTQuerying ? "Écoute" : "IA",
                                style: const TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(12),
                              ),
                              child: const Icon(Icons.call_end,
                                  color: Colors.white, size: 30),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantTile(Participant participant) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.black87
            : Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: participant.videoEnabled && participant.stream != null
            ? RTCVideoView(
                participant.id == 'local'
                    ? _localRenderer
                    : RTCVideoRenderer()..srcObject = participant.stream,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundImage:
                          NetworkImage(participant.profileImageUrl),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      participant.name,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// =========================================================
/// Page de chat textuel (ChatPage)
/// =========================================================
class ChatPage extends StatefulWidget {
  final String channelId;
  final String channelName;
  final bool isVoiceChannel;

  const ChatPage({
    Key? key,
    required this.channelId,
    required this.channelName,
    this.isVoiceChannel = false,
  }) : super(key: key);

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<String> getChatGPTResponse(List<Map<String, dynamic>> messages) async {
    try {
      debugPrint('Envoi des messages à ChatGPT: $messages');
      final response = await http.post(
        Uri.parse(kApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kApiKey',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',
          'messages': messages,
          'max_tokens': 150,
        }),
      );
      debugPrint('Réponse de l\'API: ${response.body}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'].trim();
      } else if (response.statusCode == 429) {
        return 'Erreur : Vous avez dépassé votre quota.';
      } else {
        throw Exception('Erreur : ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Erreur : $e');
      return 'Erreur : Impossible de récupérer la réponse de ChatGPT.';
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isLoading) return;
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Utilisateur non authentifié',
                  style: Theme.of(context).textTheme.bodyLarge)));
      return;
    }
    try {
      final messageContent = _messageController.text.trim();
      _messageController.clear();
      final chatMsg = myChat.ChatMessage(
        id: '',
        content: messageContent,
        type: myChat.MessageType.user,
        userId: user.uid,
        userEmail: user.email ?? 'Utilisateur Inconnu',
        status: myChat.MessageStatus.validated,
      );
      await FirebaseFirestore.instance
          .collection('channels')
          .doc(widget.channelId)
          .collection('messages')
          .add(chatMsg.toMap());
      setState(() => _isLoading = false);
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } catch (e) {
      debugPrint('Erreur : $e');
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erreur lors de l\'envoi du message: $e',
                style: Theme.of(context).textTheme.bodyLarge)),
      );
    }
  }

  void _queryChatGPT() async {
    TextEditingController queryController = TextEditingController();
    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Question à ChatGPT',
              style: Theme.of(context).textTheme.titleMedium),
          content: TextField(
            controller: queryController,
            decoration: const InputDecoration(hintText: 'Entrez votre question'),
          ),
          actions: [
            TextButton(
              child: const Text('Annuler'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Envoyer'),
              onPressed: () async {
                String query = queryController.text.trim();
                Navigator.of(dialogContext).pop();
                if (query.isNotEmpty) {
                  setState(() => _isLoading = true);
                  try {
                    QuerySnapshot snapshot = await FirebaseFirestore.instance
                        .collection('channels')
                        .doc(widget.channelId)
                        .collection('messages')
                        .orderBy('timestamp', descending: true)
                        .limit(10)
                        .get();
                    List<DocumentSnapshot> docs =
                        snapshot.docs.reversed.toList();
                    List<Map<String, dynamic>> chatMessages = [
                      {'role': 'system', 'content': 'Vous êtes un assistant utile.'},
                    ];
                    for (var doc in docs) {
                      myChat.ChatMessage chatMsg =
                          myChat.ChatMessage.fromFirestore(doc);
                      String role = chatMsg.userId == 'ChatGPT' ? 'assistant' : 'user';
                      chatMessages.add({'role': role, 'content': chatMsg.content});
                    }
                    chatMessages.add({'role': 'user', 'content': query});
                    String response = await getChatGPTResponse(chatMessages);
                    if (response.startsWith('Erreur')) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(response)));
                    } else {
                      final chatGPTMessage = myChat.ChatMessage(
                        id: '',
                        content: response,
                        type: myChat.MessageType.ai,
                        userId: 'ChatGPT',
                        userEmail: 'ChatGPT',
                        status: myChat.MessageStatus.pending_validation,
                      );
                      await FirebaseFirestore.instance
                          .collection('channels')
                          .doc(widget.channelId)
                          .collection('messages')
                          .add(chatGPTMessage.toMap());
                      _scrollController.animateTo(
                        0.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  } catch (e) {
                    debugPrint('Erreur : $e');
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Erreur : $e')));
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

  @override
  Widget build(BuildContext context) {
    if (widget.channelId.isEmpty) {
      return Scaffold(
        body: Center(
            child: Text("Erreur : channelId est vide",
                style: Theme.of(context).textTheme.bodyLarge)),
      );
    }
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) => Scaffold(
        backgroundColor: themeProvider.themeData.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(widget.channelName,
              style: themeProvider.themeData.textTheme.titleLarge),
          actions: [
            if (!widget.isVoiceChannel)
              IconButton(
                icon: Icon(Icons.call,
                    color: themeProvider.themeData.iconTheme.color),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VoiceCallPage(
                        channelId: widget.channelId,
                        channelName: widget.channelName,
                      ),
                    ),
                  );
                },
              ),
            if (!widget.isVoiceChannel)
              IconButton(
                icon: Icon(Icons.videocam,
                    color: themeProvider.themeData.iconTheme.color),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VideoCallPage(
                        channelId: widget.channelId,
                        channelName: widget.channelName,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ScrollConfiguration(
                behavior: NoGlowScrollBehavior(),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('channels')
                      .doc(widget.channelId)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Center(
                          child: Text('Erreur: ${snapshot.error}',
                              style: Theme.of(context).textTheme.bodyLarge));
                    } else if (!snapshot.hasData ||
                        snapshot.data!.docs.isEmpty) {
                      return Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: themeProvider.themeData.scaffoldBackgroundColor,
                        child: Center(
                          child: Text(
                            'Aucun message trouvé',
                            style: themeProvider.themeData.textTheme.bodyLarge,
                          ),
                        ),
                      );
                    }
                    final messages = snapshot.data!.docs;
                    final currentUser =
                        Provider.of<AuthService>(context, listen: false)
                            .currentUser;
                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message =
                            myChat.ChatMessage.fromFirestore(messages[index]);
                        final isCurrentUser =
                            message.userId == currentUser?.uid;
                        Color containerColor = themeProvider.themeData.cardColor;
                        if (message.userId == "ChatGPT") {
                          containerColor = themeProvider.themeData.brightness ==
                                  Brightness.dark
                              ? Colors.blueGrey[800]!
                              : Colors.blueGrey[100]!;
                        } else if (isCurrentUser) {
                          containerColor = themeProvider.themeData.brightness ==
                                  Brightness.dark
                              ? Colors.grey[700]!
                              : Colors.grey[400]!;
                        } else {
                          containerColor = themeProvider.themeData.brightness ==
                                  Brightness.dark
                              ? Colors.grey[600]!
                              : Colors.grey[200]!;
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 8),
                          child: Align(
                            alignment: isCurrentUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: containerColor,
                                border: Border.all(
                                    color: themeProvider.themeData.dividerColor ??
                                        Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: message.userId == "ChatGPT"
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Assistant IA",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: themeProvider
                                                          .themeData.brightness ==
                                                      Brightness.dark
                                                  ? Colors.grey[400]
                                                  : Colors.grey[700]),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          message.content,
                                          style: themeProvider
                                              .themeData.textTheme.bodyLarge,
                                        ),
                                      ],
                                    )
                                  : message.userId.isEmpty
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              message.userEmail,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: themeProvider
                                                              .themeData
                                                              .brightness ==
                                                          Brightness.dark
                                                      ? Colors.grey[500]
                                                      : Colors.grey[700],
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              message.content,
                                              style: themeProvider
                                                  .themeData.textTheme.bodyLarge,
                                            ),
                                          ],
                                        )
                                      : FutureBuilder<DocumentSnapshot>(
                                          future: FirebaseFirestore.instance
                                              .collection('users')
                                              .doc(message.userId)
                                              .get(),
                                          builder: (context, userSnapshot) {
                                            if (!userSnapshot.hasData ||
                                                userSnapshot.data == null) {
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    message.userEmail,
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: themeProvider
                                                                    .themeData
                                                                    .brightness ==
                                                                Brightness.dark
                                                            ? Colors.grey[500]
                                                            : Colors.grey[700],
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    message.content,
                                                    style: themeProvider
                                                        .themeData
                                                        .textTheme
                                                        .bodyLarge,
                                                  ),
                                                ],
                                              );
                                            }
                                            final userData =
                                                userSnapshot.data!.data()
                                                    as Map<String, dynamic>?;
                                            final displayName =
                                                userData?['displayName'] ??
                                                    message.userEmail;
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  displayName,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: themeProvider
                                                                .themeData
                                                                .brightness ==
                                                            Brightness.dark
                                                        ? Colors.grey[400]
                                                        : Colors.grey[700],
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  message.content,
                                                  style: themeProvider
                                                      .themeData
                                                      .textTheme
                                                      .bodyLarge,
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: LinearProgressIndicator(
                  color: themeProvider.themeData.primaryColor,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Tapez un message...',
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: themeProvider.themeData.dividerColor),
                        ),
                        fillColor: themeProvider
                            .themeData.inputDecorationTheme.fillColor,
                      ),
                      style: themeProvider.themeData.textTheme.bodyLarge,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.send,
                        color: themeProvider.themeData.iconTheme.color),
                    onPressed: _sendMessage,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _queryChatGPT,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeProvider.themeData.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Demander à l\'IA'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =========================================================
/// Classe FeatureCard, DashboardItem et UserModel (inchangées)
/// =========================================================
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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
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
      Navigator.pushNamed(context, widget.item.routeName, arguments: {
        'workspaceId': ''
      });
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
            color: Theme.of(context).cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      widget.item.icon,
                      size: 30,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.item.title,
                        style: Theme.of(context).textTheme.titleMedium,
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

class UserModel {
  final String id;
  final String displayName;
  final bool isOnline;

  UserModel({
    required this.id,
    required this.displayName,
    required this.isOnline,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      displayName: data['displayName'] ?? 'Utilisateur',
      isOnline: data['isOnline'] ?? false,
    );
  }
}
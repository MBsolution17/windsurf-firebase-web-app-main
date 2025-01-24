// lib/services/create_channel_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class CreateChannelPage extends StatefulWidget {
  const CreateChannelPage({super.key});

  @override
  State<CreateChannelPage> createState() => _CreateChannelPageState();
}

class _CreateChannelPageState extends State<CreateChannelPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isVoiceChannel = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createChannel() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        print('Starting channel creation...');

        final user = Provider.of<AuthService>(context, listen: false).currentUser;
        if (user == null) {
          throw Exception('User not authenticated');
        }

        print('User authenticated: ${user.uid}');

        // Créer une référence à la collection channels
        final channelsRef = FirebaseFirestore.instance.collection('channels');

        // Préparer les données du canal
        final channelData = {
          'name': _nameController.text.trim(),
          'description': _descriptionController.text.trim(),
          'createdBy': user.uid,
          'createdAt': Timestamp.now(),
          'isVoiceChannel': _isVoiceChannel,
          'members': [user.uid],
          'lastActivity': Timestamp.now(),
        };

        print('Attempting to create channel with data: $channelData');

        // Ajouter le document sans timeout pour éviter des erreurs de latence
        final docRef = await channelsRef.add(channelData);
        print('Channel created successfully with ID: ${docRef.id}');

        // Ajouter le message initial sans timeout
        await docRef.collection('messages').add({
          'type': 'system',
          'content': 'Channel created',
          'timestamp': Timestamp.now(),
          'createdBy': user.uid,
        });
        print('Initial message added to channel');

        // Vérifier que le channel a bien été créé
        final verifyDoc = await docRef.get();
        if (!verifyDoc.exists) {
          print('Channel verification failed: document does not exist');
          throw Exception('Channel was not created properly');
        }

        print('Channel verified successfully');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Channel created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushReplacementNamed(context, '/channel_list');
        }
      } catch (e, stackTrace) {
        print('Error creating channel: $e');
        print('Stack trace: $stackTrace');

        String errorMessage = 'Error creating channel: ';
        if (e is FirebaseException) {
          errorMessage += 'Firebase error: ${e.message}';
        } else {
          errorMessage += e.toString();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: _createChannel,
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Channel')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Channel Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a channel name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Voice Channel'),
                subtitle: const Text(
                  'Enable voice chat for this channel',
                ),
                value: _isVoiceChannel,
                onChanged: (bool value) {
                  setState(() {
                    _isVoiceChannel = value;
                  });
                },
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _createChannel,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Theme.of(context).primaryColor,
                      ),
                      child: const Text(
                        'Create Channel',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

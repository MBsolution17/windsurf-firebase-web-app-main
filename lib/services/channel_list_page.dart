import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChannelListPage extends StatelessWidget {
  const ChannelListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Channels'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.pushNamed(context, '/create_channel'),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('channels').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final channels = snapshot.data!.docs;

          if (channels.isEmpty) {
            return const Center(
              child: Text('No channels available. Create one to get started!'),
            );
          }

          return ListView.builder(
            itemCount: channels.length,
            itemBuilder: (context, index) {
              final channel = channels[index].data() as Map<String, dynamic>;
              final channelId = channels[index].id;
              final isVoiceChannel = channel['isVoiceChannel'] ?? false;

              return ListTile(
                leading: Icon(
                  isVoiceChannel ? Icons.mic : Icons.chat,
                  color: Colors.blue,
                ),
                title: Text(channel['name'] ?? 'Unnamed Channel'),
                subtitle: Text(channel['description'] ?? ''),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/chat',
                    arguments: {
                      'channelId': channelId,
                      'channelName': channel['name'],
                      'isVoiceChannel': isVoiceChannel,
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

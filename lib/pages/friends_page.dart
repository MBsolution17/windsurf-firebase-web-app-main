// lib/pages/friends_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class FriendsPage extends StatelessWidget {
  const FriendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUser = authService.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mes amis'),
          backgroundColor: Colors.indigo,
        ),
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              bool success = await authService.signInWithGoogle();
              if (!success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Échec de la connexion avec Google'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Se connecter avec Google'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes amis'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Déconnecté avec succès.')),
              );
            },
            tooltip: 'Se Déconnecter',
          ),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1, thickness: 2),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .collection('friends')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erreur : ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final friends = snapshot.data!.docs;

                if (friends.isEmpty) {
                  return const Center(
                    child: Text(
                      'Aucun ami ajouté. Ajoutez des amis pour collaborer !',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friendData =
                        friends[index].data() as Map<String, dynamic>;
                    final friendName =
                        friendData['displayName'] as String? ?? 'Inconnu';
                    final friendEmail =
                        friendData['email'] as String? ?? 'Inconnu';
                    final friendGrade =
                        friendData['grade'] as String? ?? 'Aucun grade';

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.indigo,
                        child: Text(
                          friendName.isNotEmpty
                              ? friendName[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(friendName),
                      subtitle: Text('$friendEmail\nGrade: $friendGrade'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(currentUser.uid)
                              .collection('friends')
                              .doc(friends[index].id)
                              .delete();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Ami supprimé'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddFriendDialog(context, currentUser.uid, authService);
        },
        child: const Icon(Icons.person_add),
      ),
    );
  }

  void _showAddFriendDialog(
      BuildContext context, String userId, AuthService authService) {
    final TextEditingController emailController = TextEditingController();
    final TextEditingController pseudoController = TextEditingController();
    final TextEditingController gradeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ajouter un ami'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Adresse e-mail',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pseudoController,
                  decoration: const InputDecoration(
                    labelText: 'Pseudo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: gradeController,
                  decoration: const InputDecoration(
                    labelText: 'Grade',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () async {
                final friendEmail = emailController.text.trim();
                final friendPseudo = pseudoController.text.trim();
                final friendGrade = gradeController.text.trim();

                if (friendEmail.isEmpty ||
                    !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(friendEmail)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Veuillez entrer une adresse e-mail valide.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  // Rechercher l'utilisateur par email dans Firestore
                  final userQuery = await FirebaseFirestore.instance
                      .collection('users')
                      .where('email', isEqualTo: friendEmail)
                      .limit(1)
                      .get();

                  final friendUid = userQuery.docs.isNotEmpty
                      ? userQuery.docs.first.id
                      : null;
                  final friendDisplayName = friendPseudo.isNotEmpty
                      ? friendPseudo
                      : userQuery.docs.isNotEmpty
                          ? (userQuery.docs.first.data())['displayName'] ??
                              friendEmail.split('@')[0]
                          : friendEmail.split('@')[0];

                  // Vérifiez si l'ami est déjà ajouté
                  final existingFriend = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .collection('friends')
                      .where('email', isEqualTo: friendEmail)
                      .get();

                  if (existingFriend.docs.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cet ami est déjà ajouté.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }

                  // Ajouter dans Firestore
                  final friendRef = await FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .collection('friends')
                      .add({
                    'uid': friendUid ?? '',
                    'displayName': friendDisplayName,
                    'email': friendEmail,
                    'grade': friendGrade.isNotEmpty ? friendGrade : 'Aucun grade',
                    'timestamp': FieldValue.serverTimestamp(),
                  });

                  // Envoyer un e-mail via Gmail API
                  try {
                    await authService.sendEmail(
                      recipientEmail: friendEmail,
                      subject: 'Invitation à collaborer sur Boundly',
                      bodyText:
                          'Bonjour $friendDisplayName, vous avez été invité à rejoindre notre espace de collaboration !',
                      bodyHtml:
                          '<p>Bonjour $friendDisplayName, vous avez été invité à rejoindre notre <strong>espace de collaboration</strong> sur Boundly.</p>',
                    );

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invitation envoyée avec succès !'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    // Supprimez l'entrée si l'envoi échoue
                    await friendRef.delete();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Erreur lors de l\'envoi de l\'e-mail: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }

                  Navigator.of(context).pop();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Erreur: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Ajouter'),
            ),
          ],
        );
      },
    );
  }
}

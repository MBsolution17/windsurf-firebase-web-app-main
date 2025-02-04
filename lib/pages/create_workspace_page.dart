import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateWorkspacePage extends StatefulWidget {
  @override
  _CreateWorkspacePageState createState() => _CreateWorkspacePageState();
}

class _CreateWorkspacePageState extends State<CreateWorkspacePage> {
  final TextEditingController _workspaceNameController = TextEditingController();
  bool _isLoading = false;

  Future<void> _createWorkspace() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      String workspaceId = FirebaseFirestore.instance.collection('workspaces').doc().id;

      await FirebaseFirestore.instance.collection('workspaces').doc(workspaceId).set({
        'id': workspaceId,
        'name': _workspaceNameController.text,
        'ownerId': user.uid,
        'createdAt': Timestamp.now(),
      });

      // Mettre à jour le profil utilisateur avec le workspaceId
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'workspaceId': workspaceId,
      });

      // Aller au Dashboard
      Navigator.pushReplacementNamed(context, '/dashboard');
    } catch (e) {
      print('Erreur lors de la création du workspace: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Créer un Workspace')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nom du Workspace', style: TextStyle(fontSize: 18)),
            TextField(controller: _workspaceNameController),
            SizedBox(height: 20),
            _isLoading
                ? Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _createWorkspace,
                    child: Text('Créer'),
                  ),
          ],
        ),
      ),
    );
  }
}

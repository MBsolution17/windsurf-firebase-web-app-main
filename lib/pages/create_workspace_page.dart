import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/workspace.dart';
import 'onboarding/onboarding_page.dart';

class CreateWorkspacePage extends StatefulWidget {
  const CreateWorkspacePage({Key? key}) : super(key: key);
  @override
  State<CreateWorkspacePage> createState() => _CreateWorkspacePageState();
}

class _CreateWorkspacePageState extends State<CreateWorkspacePage> {
  final TextEditingController _workspaceNameController = TextEditingController();
  final TextEditingController _joinCodeController = TextEditingController();
  bool _isLoading = false;
  bool _isCreatingNew = true;
  String? _workspaceId;

  @override
  void dispose() {
    _workspaceNameController.dispose();
    _joinCodeController.dispose();
    super.dispose();
  }

  Future<void> _createOrJoinWorkspace() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isCreatingNew) {
        // Créer un nouveau workspace
        String workspaceId = FirebaseFirestore.instance.collection('workspaces').doc().id;
        String joinCode = Workspace.generateJoinCode(); // Génère un code unique

        await FirebaseFirestore.instance.collection('workspaces').doc(workspaceId).set({
          'id': workspaceId,
          'name': _workspaceNameController.text.trim(),
          'ownerUid': user.uid,
          'members': [user.uid], // Le créateur est le premier membre
          'joinCode': joinCode,
          'createdAt': Timestamp.now(),
        });

        // Mettre à jour le profil utilisateur avec le workspaceId
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'workspaceId': workspaceId,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Workspace créé avec succès ! Code de join : $joinCode')),
        );

        // Stocker l’workspaceId localement
        _workspaceId = workspaceId;
      } else {
        // Rejoindre un workspace existant avec le code
        String joinCode = _joinCodeController.text.trim().toUpperCase();
        QuerySnapshot workspaceQuery = await FirebaseFirestore.instance
            .collection('workspaces')
            .where('joinCode', isEqualTo: joinCode)
            .limit(1)
            .get();

        if (workspaceQuery.docs.isEmpty) {
          throw Exception('Code de join invalide ou workspace inexistant.');
        }

        DocumentSnapshot workspaceDoc = workspaceQuery.docs.first;
        Workspace workspace = Workspace.fromFirestore(workspaceDoc as DocumentSnapshot<Map<String, dynamic>>);

        String workspaceId = workspace.id;

        // Vérifier si l’utilisateur n’est pas déjà membre
        if (!workspace.members.contains(user.uid)) {
          // Ajouter l’utilisateur aux membres
          Workspace updatedWorkspace = workspace.addMember(user.uid);
          await FirebaseFirestore.instance.collection('workspaces').doc(workspaceId).update(
            updatedWorkspace.toMap(),
          );

          // Mettre à jour le profil utilisateur avec le workspaceId
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'workspaceId': workspaceId,
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Vous avez rejoint le workspace "${workspace.name}" avec succès !')),
          );

          // Stocker l’workspaceId localement
          _workspaceId = workspaceId;
        } else {
          throw Exception('Vous êtes déjà membre de ce workspace.');
        }
      }

      // Rediriger vers le Dashboard après création ou join avec l’workspaceId correct
      if (_workspaceId != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => OnboardingPage(workspaceId: _workspaceId!),
          ),
        );
      } else {
        throw Exception('Erreur : workspaceId non défini.');
      }
    } catch (e) {
      print('Erreur lors de la création/rejoindre du workspace: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isCreatingNew ? 'Créer un Workspace' : 'Rejoindre un Workspace')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isCreatingNew = true;
                      _workspaceNameController.clear();
                      _joinCodeController.clear();
                    });
                  },
                  child: Text('Créer un nouveau', style: TextStyle(color: _isCreatingNew ? Colors.blue : Colors.black)),
                ),
                Text(' | ', style: TextStyle(fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isCreatingNew = false;
                      _workspaceNameController.clear();
                      _joinCodeController.clear();
                    });
                  },
                  child: Text('Rejoindre un existant', style: TextStyle(color: !_isCreatingNew ? Colors.blue : Colors.black)),
                ),
              ],
            ),
            SizedBox(height: 20),
            if (_isCreatingNew)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nom du Workspace', style: TextStyle(fontSize: 18)),
                  TextField(
                    controller: _workspaceNameController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Entrez un nom pour le workspace',
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Code de join', style: TextStyle(fontSize: 18)),
                  TextField(
                    controller: _joinCodeController,
                    decoration: InputDecoration(
                      hintText: 'Entrez le code de join (6 caractères)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            SizedBox(height: 20),
            _isLoading
                ? Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _createOrJoinWorkspace,
                    child: Text(_isCreatingNew ? 'Créer' : 'Rejoindre'),
                  ),
          ],
        ),
      ),
    );
  }
}
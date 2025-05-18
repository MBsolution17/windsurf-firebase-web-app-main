import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart'; // Ajout pour accéder au ThemeProvider

import '../models/contact.dart';
import '../models/folder.dart';
import '../models/task.dart';
import '../theme_provider.dart'; // Assurez-vous que le chemin est correct

class ContactDetailPage extends StatefulWidget {
  final String workspaceId;
  final Contact contact;

  const ContactDetailPage({
    Key? key,
    required this.workspaceId,
    required this.contact,
  }) : super(key: key);

  @override
  _ContactDetailPageState createState() => _ContactDetailPageState();
}

class _ContactDetailPageState extends State<ContactDetailPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _noteController = TextEditingController();

  Future<Folder?> _fetchFolder() async {
    if (widget.contact.folderId.isEmpty) return null;
    final doc = await _firestore
        .collection('workspaces')
        .doc(widget.workspaceId)
        .collection('folders')
        .doc(widget.contact.folderId)
        .get();
    if (doc.exists) {
      return Folder.fromFirestore(doc);
    }
    return null;
  }

  Future<List<Task>> _fetchTasks() async {
    QuerySnapshot snapshot = await _firestore
        .collection('workspaces')
        .doc(widget.workspaceId)
        .collection('tasks')
        .where('contactId', isEqualTo: widget.contact.id)
        .get();
    return snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();
  }

  // Récupère la liste des notes stockées dans le document du contact
  Future<List<String>> _fetchNotes() async {
    final doc = await _firestore
        .collection('workspaces')
        .doc(widget.workspaceId)
        .collection('contacts')
        .doc(widget.contact.id)
        .get();
    if (doc.exists && doc.data() != null && doc.data()!.containsKey('notes')) {
      return List<String>.from(doc.data()!['notes'] as List);
    }
    return [];
  }

  // Ajoute une nouvelle note au document du contact
  Future<void> _addNote(String note) async {
    if (note.trim().isEmpty) return;
    await _firestore
        .collection('workspaces')
        .doc(widget.workspaceId)
        .collection('contacts')
        .doc(widget.contact.id)
        .update({
      'notes': FieldValue.arrayUnion([note.trim()])
    });
    _noteController.clear();
    setState(() {}); // Pour rafraîchir l'affichage des notes
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor, // Couleur principale du thème
        title: Text(
          '${widget.contact.firstName} ${widget.contact.lastName}',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: Colors.white),
        ),
        iconTheme: Theme.of(context).iconTheme, // Icônes selon le thème
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // Fond selon le thème
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Informations du contact
            Text(
              'Détails du Contact',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _buildDetailRow('Email', widget.contact.email),
            _buildDetailRow('Téléphone', widget.contact.phone),
            _buildDetailRow('Adresse', widget.contact.address),
            _buildDetailRow('Entreprise', widget.contact.company),
            _buildDetailRow('Infos complémentaires', widget.contact.externalInfo),
            const SizedBox(height: 20),
            // Dossier associé
            FutureBuilder<Folder?>(
              future: _fetchFolder(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data == null) {
                  return Text(
                    'Aucun dossier associé',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontStyle: FontStyle.italic),
                  );
                }
                Folder folder = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dossier associé',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nom : ${folder.name}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            // Tâches liées au contact
            FutureBuilder<List<Task>>(
              future: _fetchTasks(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Text(
                    'Aucune tâche liée à ce contact',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontStyle: FontStyle.italic),
                  );
                }
                List<Task> tasks = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tâches liées',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...tasks.map((task) => Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          color: Theme.of(context).cardColor, // Couleur de la carte selon le thème
                          child: ListTile(
                            title: Text(
                              task.title,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            subtitle: Text(
                              task.description,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontSize: 12),
                            ),
                          ),
                        )),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            // Section Notes externes
            Text(
              'Notes externes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<String>>(
              future: _fetchNotes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                List<String> notes = snapshot.data ?? [];
                if (notes.isEmpty) {
                  return Text(
                    'Aucune note enregistrée',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontStyle: FontStyle.italic),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: notes
                      .map((note) => Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .dividerColor
                                  ?.withOpacity(0.2), // Nuance subtile selon le thème
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              note,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 12),
            // Formulaire pour ajouter une note
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteController,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: 'Ajouter une note...',
                      filled: true,
                      fillColor:
                          Theme.of(context).dividerColor?.withOpacity(0.2),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ), // Utilise le style par défaut du thème
                  onPressed: () => _addNote(_noteController.text),
                  child: Text(
                    'Ajouter',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Méthode d'affichage d'une ligne de détail
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label : ',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '-',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
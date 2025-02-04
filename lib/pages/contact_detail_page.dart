import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/contact.dart';
import '../models/folder.dart';
import '../models/task.dart';

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
    // Fond gris clair pour l'ensemble de la page
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.grey[800],
        title: Text('${widget.contact.firstName} ${widget.contact.lastName}',
            style: GoogleFonts.roboto()),
      ),
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Informations du contact
            Text(
              'Détails du Contact',
              style: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey[800]),
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
                  return Text('Aucun dossier associé', style: GoogleFonts.roboto(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.grey[600]));
                }
                Folder folder = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dossier associé', style: GoogleFonts.roboto(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                    const SizedBox(height: 8),
                    Text('Nom : ${folder.name}', style: GoogleFonts.roboto(fontSize: 16)),
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
                  return Text('Aucune tâche liée à ce contact', style: GoogleFonts.roboto(fontSize: 16, fontStyle: FontStyle.italic, color: Colors.grey[600]));
                }
                List<Task> tasks = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tâches liées', style: GoogleFonts.roboto(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                    const SizedBox(height: 8),
                    ...tasks.map((task) => Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            title: Text(task.title, style: GoogleFonts.roboto()),
                            subtitle: Text(task.description, style: GoogleFonts.roboto(fontSize: 12)),
                          ),
                        )),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            // Section Notes externes
            Text('Notes externes', style: GoogleFonts.roboto(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800])),
            const SizedBox(height: 8),
            FutureBuilder<List<String>>(
              future: _fetchNotes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                List<String> notes = snapshot.data ?? [];
                if (notes.isEmpty) {
                  return Text('Aucune note enregistrée', style: GoogleFonts.roboto(fontStyle: FontStyle.italic, color: Colors.grey[600]));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: notes.map((note) => Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(note, style: GoogleFonts.roboto()),
                  )).toList(),
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
                    style: GoogleFonts.roboto(),
                    decoration: InputDecoration(
                      hintText: 'Ajouter une note...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _addNote(_noteController.text),
                  child: Text('Ajouter', style: GoogleFonts.roboto(color: Colors.white)),
                )
              ],
            )
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
          Text('$label : ', style: GoogleFonts.roboto(fontWeight: FontWeight.bold, color: Colors.grey[800])),
          Expanded(child: Text(value.isNotEmpty ? value : '-', style: GoogleFonts.roboto())),
        ],
      ),
    );
  }
}

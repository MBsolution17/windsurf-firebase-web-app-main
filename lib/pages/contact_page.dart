// lib/pages/contact_page.dart

import 'dart:io'; // Pour la lecture de fichier (mobile/desktop)
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/contact.dart';
import '../models/folder.dart';
import 'contact_detail_page.dart';

class ContactPage extends StatefulWidget {
  final String workspaceId;
  const ContactPage({Key? key, required this.workspaceId}) : super(key: key);

  @override
  _ContactPageState createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  // Listes
  List<Folder> _folders = [];
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  // Pour harmoniser avec le Dashboard
  final Color primaryColor = Colors.grey[800]!;
  final Color backgroundColor = const Color.fromARGB(255, 197, 197, 197);

  @override
  void initState() {
    super.initState();
    _fetchFolders();
    _fetchContacts();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Filtrage dès que le texte change
  void _onSearchChanged() {
    _filterContacts(_searchController.text);
  }

  void _filterContacts(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredContacts = List.from(_contacts);
      });
    } else {
      setState(() {
        final q = query.toLowerCase();
        _filteredContacts = _contacts.where((contact) {
          return contact.firstName.toLowerCase().contains(q) ||
              contact.lastName.toLowerCase().contains(q) ||
              contact.email.toLowerCase().contains(q);
        }).toList();
      });
    }
  }

  // Récupération des dossiers
  void _fetchFolders() {
    _firestore
        .collection('workspaces')
        .doc(widget.workspaceId)
        .collection('folders')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _folders =
              snapshot.docs.map((doc) => Folder.fromFirestore(doc)).toList();
        });
      }
    }, onError: (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la récupération des dossiers')),
      );
    });
  }

  // Récupération des contacts
  void _fetchContacts() {
    _firestore
        .collection('workspaces')
        .doc(widget.workspaceId)
        .collection('contacts')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _contacts =
              snapshot.docs.map((doc) => Contact.fromFirestore(doc)).toList();
          _filterContacts(_searchController.text);
        });
      }
    }, onError: (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la récupération des contacts')),
      );
    });
  }

  // Suppression d'un contact
  Future<void> _deleteContact(String contactId) async {
    try {
      await _firestore
          .collection('workspaces')
          .doc(widget.workspaceId)
          .collection('contacts')
          .doc(contactId)
          .delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact supprimé avec succès')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la suppression du contact')),
      );
    }
  }

  // Import CSV
  Future<void> _importCSV() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final csvString = await file.readAsString();
        List<List<dynamic>> csvTable =
            const CsvToListConverter().convert(csvString);

        bool isFirstLine = true;
        for (var row in csvTable) {
          if (isFirstLine) {
            isFirstLine = false;
            continue;
          }
          // Adapter les colonnes selon votre CSV
          String firstName = row[0].toString();
          String lastName = row[1].toString();
          String email = row[2].toString();
          String phone = row[3].toString();
          String address = row[4].toString();
          String company = row[5].toString();
          String externalInfo = row[6].toString();

          Contact newContact = Contact(
            id: '',
            userId: FirebaseAuth.instance.currentUser!.uid,
            firstName: firstName,
            lastName: lastName,
            email: email,
            phone: phone,
            address: address,
            company: company,
            externalInfo: externalInfo,
            folderId: '',
            timestamp: DateTime.now(),
          );

          await _firestore
              .collection('workspaces')
              .doc(widget.workspaceId)
              .collection('contacts')
              .add(newContact.toMap());
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import CSV effectué avec succès')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'import CSV: $e')),
      );
    }
  }

  // Affichage de la liste des contacts groupés par première lettre
  Widget _buildContactList() {
    List<Contact> contactsToDisplay = _filteredContacts;
    contactsToDisplay.sort((a, b) =>
        a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase()));

    List<Widget> contactWidgets = [];
    String currentLetter = '';

    for (var contact in contactsToDisplay) {
      String firstLetter = contact.firstName.isNotEmpty
          ? contact.firstName[0].toUpperCase()
          : '#';
      if (firstLetter != currentLetter) {
        currentLetter = firstLetter;
        contactWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
            child: Text(
              currentLetter,
              style: GoogleFonts.roboto(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
          ),
        );
      }
      contactWidgets.add(
        Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: CircleAvatar(
              backgroundColor: primaryColor,
              child: Text(
                contact.firstName.isNotEmpty
                    ? contact.firstName[0].toUpperCase()
                    : '?',
                style: GoogleFonts.roboto(color: Colors.white),
              ),
            ),
            title: Text(
              '${contact.firstName} ${contact.lastName}',
              style: GoogleFonts.roboto(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contact.email.isNotEmpty)
                  Text('Email: ${contact.email}', style: GoogleFonts.roboto(fontSize: 12)),
                if (contact.phone.isNotEmpty)
                  Text('Tél: ${contact.phone}', style: GoogleFonts.roboto(fontSize: 12)),
                if (contact.company.isNotEmpty)
                  Text('Entreprise: ${contact.company}', style: GoogleFonts.roboto(fontSize: 12)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.blue),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ContactDetailPage(
                          workspaceId: widget.workspaceId,
                          contact: contact,
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: Colors.white,
                        title: Text('Confirmer la suppression', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
                        content: Text('Êtes-vous sûr de vouloir supprimer ce contact ?', style: GoogleFonts.roboto()),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text('Annuler', style: GoogleFonts.roboto()),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _deleteContact(contact.id);
                            },
                            child: Text('Supprimer', style: GoogleFonts.roboto(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ContactDetailPage(
                    workspaceId: widget.workspaceId,
                    contact: contact,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return ListView(
      children: contactWidgets,
    );
  }

  // Dialogue pour ajouter un nouveau contact
  Future<void> _showAddContactDialog() async {
    final _formKeyAdd = GlobalKey<FormState>();
    final TextEditingController firstNameController = TextEditingController();
    final TextEditingController lastNameController  = TextEditingController();
    final TextEditingController emailController     = TextEditingController();
    final TextEditingController phoneController     = TextEditingController();
    final TextEditingController addressController   = TextEditingController();
    final TextEditingController companyController   = TextEditingController();
    final TextEditingController externalInfoController = TextEditingController();
    String? selectedFolderId;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text('Ajouter un Contact', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Form(
              key: _formKeyAdd,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: firstNameController,
                    style: GoogleFonts.roboto(),
                    decoration: InputDecoration(
                      labelText: 'Prénom',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    validator: (value) => (value == null || value.isEmpty) ? 'Champ requis' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: lastNameController,
                    style: GoogleFonts.roboto(),
                    decoration: InputDecoration(
                      labelText: 'Nom',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    validator: (value) => (value == null || value.isEmpty) ? 'Champ requis' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailController,
                    style: GoogleFonts.roboto(),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final RegExp emailRegex = RegExp(
                            r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+\-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
                        if (!emailRegex.hasMatch(value)) {
                          return 'Email invalide';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    style: GoogleFonts.roboto(),
                    decoration: InputDecoration(
                      labelText: 'Téléphone',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) => (value == null || value.isEmpty) ? 'Champ requis' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: addressController,
                    style: GoogleFonts.roboto(),
                    decoration: InputDecoration(
                      labelText: 'Adresse',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: companyController,
                    style: GoogleFonts.roboto(),
                    decoration: InputDecoration(
                      labelText: 'Entreprise',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: externalInfoController,
                    style: GoogleFonts.roboto(),
                    decoration: InputDecoration(
                      labelText: 'Infos supplémentaires',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedFolderId,
                    decoration: InputDecoration(
                      labelText: 'Dossier (Optionnel)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Aucun'),
                      ),
                      ..._folders.map(
                        (folder) => DropdownMenuItem(
                          value: folder.id,
                          child: Text(folder.name),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      selectedFolderId = value;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Annuler', style: GoogleFonts.roboto()),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              onPressed: () async {
                if (_formKeyAdd.currentState!.validate()) {
                  User? currentUser = FirebaseAuth.instance.currentUser;
                  if (currentUser == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Utilisateur non authentifié')),
                    );
                    return;
                  }
                  Contact newContact = Contact(
                    id: '',
                    userId: currentUser.uid,
                    firstName: firstNameController.text.trim(),
                    lastName: lastNameController.text.trim(),
                    email: emailController.text.trim(),
                    phone: phoneController.text.trim(),
                    address: addressController.text.trim(),
                    company: companyController.text.trim(),
                    externalInfo: externalInfoController.text.trim(),
                    folderId: selectedFolderId ?? '',
                    timestamp: DateTime.now(),
                  );
                  try {
                    await _firestore
                        .collection('workspaces')
                        .doc(widget.workspaceId)
                        .collection('contacts')
                        .add(newContact.toMap());
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Contact ajouté avec succès')),
                    );
                    Navigator.of(context).pop();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Erreur lors de l\'ajout du contact')),
                    );
                  }
                }
              },
              child: Text('Ajouter', style: GoogleFonts.roboto(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        title: Text('Annuaire des Contacts', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Importer CSV',
            onPressed: _importCSV,
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'Créer un dossier',
            onPressed: () {
              // Si vous souhaitez activer la création de dossier, décommentez ici:
              // _showCreateFolderDialog();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Barre de recherche
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.roboto(),
                decoration: InputDecoration(
                  hintText: 'Rechercher un contact...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            // Liste des contacts
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildContactList(),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: primaryColor,
        onPressed: _showAddContactDialog,
        tooltip: 'Ajouter un nouveau contact',
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

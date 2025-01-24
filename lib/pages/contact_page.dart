// lib/pages/contact_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/contact.dart';
import '../models/folder.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  _ContactPageState createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Contrôleurs de texte pour le formulaire
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _externalInfoController = TextEditingController();

  // Liste des dossiers
  List<Folder> _folders = [];

  // Liste des contacts disponibles pour l'association lors de la création de dossier
  List<Contact> _availableContacts = [];

  // Selected folder ID
  String? _selectedFolderId;

  // Firestore reference
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Dossier actuellement sélectionné (si nécessaire)
  Folder? _selectedFolder;

  @override
  void initState() {
    super.initState();
    _fetchFolders();
    _fetchAvailableContacts();
  }

  @override
  void dispose() {
    // Dispose des contrôleurs de texte
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _companyController.dispose();
    _externalInfoController.dispose();
    super.dispose();
  }

  // Récupère les dossiers depuis Firestore
  void _fetchFolders() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _firestore
        .collection('folders')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _folders = snapshot.docs.map((doc) => Folder.fromFirestore(doc)).toList();
        });
      }
    }, onError: (error) {
      debugPrint('Erreur lors de la récupération des dossiers: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la récupération des dossiers')),
        );
      }
    });
  }

  // Récupère les contacts disponibles pour l'association lors de la création de dossier
  void _fetchAvailableContacts() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _firestore
        .collection('contacts')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _availableContacts = snapshot.docs.map((doc) => Contact.fromFirestore(doc)).toList();
        });
      }
    }, onError: (error) {
      debugPrint('Erreur lors de la récupération des contacts disponibles: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la récupération des contacts disponibles')),
        );
      }
    });
  }

  // Méthode pour créer un nouveau dossier avec association de contacts
  Future<void> _createFolder(String name, List<String> contactIds) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      DocumentReference folderRef = await _firestore.collection('folders').add({
        'name': name,
        'userId': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });

      String newFolderId = folderRef.id;

      if (contactIds.isNotEmpty) {
        WriteBatch batch = _firestore.batch();

        for (String contactId in contactIds) {
          DocumentReference contactRef = _firestore.collection('contacts').doc(contactId);
          batch.update(contactRef, {'folderId': newFolderId});
        }

        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dossier créé avec succès')),
        );
      }
    } catch (e) {
      debugPrint('Erreur lors de la création du dossier: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la création du dossier')),
        );
      }
    }
  }

  // Méthode pour soumettre le formulaire et ajouter un contact
  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      // Récupérer les données du formulaire
      String firstName = _firstNameController.text.trim();
      String lastName = _lastNameController.text.trim();
      String email = _emailController.text.trim();
      String phone = _phoneController.text.trim();
      String address = _addressController.text.trim();
      String company = _companyController.text.trim();
      String externalInfo = _externalInfoController.text.trim();

      // Récupérer l'ID de l'utilisateur actuel
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Utilisateur non authentifié')),
        );
        return;
      }

      // Créer un objet Contact avec des champs optionnels
      Contact newContact = Contact(
        id: '', // L'ID sera généré par Firestore
        userId: currentUser.uid, // Ajout du userId
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        address: address,
        company: company,
        externalInfo: externalInfo,
        folderId: _selectedFolderId ?? '', // Assurez-vous que folderId est non null
        timestamp: DateTime.now(), // Correction ici
      );

      try {
        // Ajouter le contact à Firestore
        await _firestore.collection('contacts').add(newContact.toMap());

        // Afficher un message de succès
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Contact ajouté avec succès')),
        );

        // Réinitialiser le formulaire
        _formKey.currentState!.reset();
        setState(() {
          _selectedFolderId = null;
        });
      } catch (e) {
        // Afficher un message d'erreur
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'ajout du contact')),
        );
        print('Erreur lors de l\'ajout du contact: $e');
      }
    }
  }

  // Afficher un dialogue pour créer un nouveau dossier avec sélection de contacts
// Afficher un dialogue pour créer un nouveau dossier avec sélection de contacts
// Afficher un dialogue pour créer un nouveau dossier avec sélection de contacts
void _showCreateFolderDialog() {
  String folderName = '';
  List<String> selectedContactIds = [];

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return AlertDialog(
        title: const Text('Créer un Dossier'),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Champ pour entrer le nom du dossier
              TextField(
                decoration: const InputDecoration(hintText: 'Nom du dossier'),
                onChanged: (value) {
                  folderName = value;
                },
              ),
              const SizedBox(height: 20),

              // Section pour sélectionner des contacts
              const Text(
                'Associer des Contacts (Optionnel)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // Liste des contacts avec des contraintes explicites
              Expanded(
                child: _availableContacts.isNotEmpty
                    ? ListView.builder(
                        itemCount: _availableContacts.length,
                        itemBuilder: (context, index) {
                          final contact = _availableContacts[index];
                          return CheckboxListTile(
                            title: Text('${contact.firstName} ${contact.lastName}'),
                            value: selectedContactIds.contains(contact.id),
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  selectedContactIds.add(contact.id);
                                } else {
                                  selectedContactIds.remove(contact.id);
                                }
                              });
                            },
                          );
                        },
                      )
                    : const Text('Aucun contact disponible.'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              if (folderName.trim().isNotEmpty) {
                _createFolder(folderName.trim(), selectedContactIds);
                Navigator.of(context).pop();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Veuillez entrer un nom de dossier')),
                );
              }
            },
            child: const Text('Créer'),
          ),
        ],
      );
    },
  );
}

  // Afficher un dialogue pour supprimer un contact
  Future<void> _deleteContact(String contactId) async {
    try {
      await _firestore.collection('contacts').doc(contactId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contact supprimé avec succès')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression du contact')),
      );
      print('Erreur lors de la suppression du contact: $e');
    }
  }

  // Afficher les détails du contact dans une boîte de dialogue
  void _showContactDetails(Contact contact) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('${contact.firstName} ${contact.lastName}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contact.email.isNotEmpty)
                  Text('Email: ${contact.email}'),
                SizedBox(height: 8),
                if (contact.phone.isNotEmpty)
                  Text('Téléphone: ${contact.phone}'),
                SizedBox(height: 8),
                if (contact.address.isNotEmpty)
                  Text('Adresse: ${contact.address}'),
                SizedBox(height: 8),
                if (contact.company.isNotEmpty)
                  Text('Entreprise: ${contact.company}'),
                SizedBox(height: 8),
                if (contact.externalInfo.isNotEmpty)
                  Text('Informations Externes: ${contact.externalInfo}'),
                SizedBox(height: 8),
                if (contact.folderId.isNotEmpty)
                  FutureBuilder<DocumentSnapshot>(
                    future: _firestore.collection('folders').doc(contact.folderId).get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Text('Dossier: Chargement...');
                      }
                      if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                        return Text('Dossier: Inconnu');
                      }
                      final folder = Folder.fromFirestore(snapshot.data!);
                      return Text('Dossier: ${folder.name}');
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text('Fermer'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  // Widget pour afficher la liste des contacts existants
  Widget _buildContactList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('contacts')
          .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Erreur: ${snapshot.error}',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'Aucun contact trouvé.',
              style: GoogleFonts.roboto(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          );
        }

        final contacts = snapshot.data!.docs.map((doc) => Contact.fromFirestore(doc)).toList();

        return ListView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: contacts.length,
          itemBuilder: (context, index) {
            final contact = contacts[index];
            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 6.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo[800],
                  child: Text(
                    contact.firstName.isNotEmpty
                        ? contact.firstName[0].toUpperCase()
                        : '?',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(
                  '${contact.firstName} ${contact.lastName}',
                  style: GoogleFonts.roboto(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (contact.email.isNotEmpty)
                      Text('Email: ${contact.email}'),
                    if (contact.phone.isNotEmpty)
                      Text('Téléphone: ${contact.phone}'),
                    if (contact.company.isNotEmpty)
                      Text('Entreprise: ${contact.company}'),
                    if (contact.folderId.isNotEmpty)
                      FutureBuilder<DocumentSnapshot>(
                        future: _firestore.collection('folders').doc(contact.folderId).get(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Text('Dossier: Chargement...');
                          }
                          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                            return Text('Dossier: Inconnu');
                          }
                          final folder = Folder.fromFirestore(snapshot.data!);
                          return Text('Dossier: ${folder.name}');
                        },
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text('Confirmer la suppression'),
                            content: Text('Êtes-vous sûr de vouloir supprimer ce contact?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text('Annuler'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _deleteContact(contact.id);
                                },
                                child: Text('Supprimer'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.info_outline, color: Colors.blue),
                      onPressed: () {
                        _showContactDetails(contact);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Widget principal de la page
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gestion des Contacts'),
        backgroundColor: Colors.indigo[800],
        actions: [
          IconButton(
            icon: Icon(Icons.create_new_folder),
            tooltip: 'Créer un dossier',
            onPressed: _showCreateFolderDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ListView(
            children: [
              // Formulaire d'ajout de contact
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                color: Colors.white, // Fond blanc pour contraste
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ajouter un Nouveau Contact',
                          style: GoogleFonts.roboto(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo[800],
                          ),
                        ),
                        SizedBox(height: 20),
                        // Champ Prénom
                        TextFormField(
                          controller: _firstNameController,
                          decoration: InputDecoration(
                            labelText: 'Prénom',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          // Champ optionnel
                        ),
                        SizedBox(height: 20),
                        // Champ Nom de Famille
                        TextFormField(
                          controller: _lastNameController,
                          decoration: InputDecoration(
                            labelText: 'Nom de Famille',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          // Champ optionnel
                        ),
                        SizedBox(height: 20),
                        // Champ Email
                        TextFormField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              final RegExp emailRegex = RegExp(
                                  r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
                              if (!emailRegex.hasMatch(value)) {
                                return 'Veuillez entrer un email valide';
                              }
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 20),
                        // Champ Numéro de Téléphone
                        TextFormField(
                          controller: _phoneController,
                          decoration: InputDecoration(
                            labelText: 'Numéro de Téléphone',
                            prefixIcon: Icon(Icons.phone),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          keyboardType: TextInputType.phone,
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              final RegExp phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');
                              if (!phoneRegex.hasMatch(value)) {
                                return 'Veuillez entrer un numéro de téléphone valide';
                              }
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 20),
                        // Champ Adresse
                        TextFormField(
                          controller: _addressController,
                          decoration: InputDecoration(
                            labelText: 'Adresse',
                            prefixIcon: Icon(Icons.home),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          // Champ optionnel
                        ),
                        SizedBox(height: 20),
                        // Champ Entreprise
                        TextFormField(
                          controller: _companyController,
                          decoration: InputDecoration(
                            labelText: 'Entreprise',
                            prefixIcon: Icon(Icons.business),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          // Champ optionnel
                        ),
                        SizedBox(height: 20),
                        // Champ Informations Externes
                        TextFormField(
                          controller: _externalInfoController,
                          decoration: InputDecoration(
                            labelText: 'Informations Externes',
                            prefixIcon: Icon(Icons.info_outline),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          maxLines: 3,
                          // Champ optionnel
                        ),
                        SizedBox(height: 20),
                        // Dropdown pour sélectionner un dossier
                        DropdownButtonFormField<String>(
                          value: _selectedFolderId,
                          decoration: InputDecoration(
                            labelText: 'Dossier (Optionnel)',
                            prefixIcon: Icon(Icons.folder),
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.grey[100],
                          ),
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text('Aucun Dossier'),
                            ),
                            ..._folders.map(
                              (folder) => DropdownMenuItem(
                                value: folder.id,
                                child: Text(folder.name),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedFolderId = value;
                            });
                          },
                        ),
                        SizedBox(height: 30),
                        // Bouton de Soumission
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _submitForm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo[800],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: Text(
                              'Ajouter Contact',
                              style: GoogleFonts.roboto(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: 30),
              // Liste des Contacts Existants
              Text(
                'Contacts Existants',
                style: GoogleFonts.roboto(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo[800],
                ),
              ),
              SizedBox(height: 10),
              SizedBox(
                // Ajuster la hauteur pour éviter l'overflow
                height: MediaQuery.of(context).size.height * 0.6,
                child: _buildContactList(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateFolderDialog,
        tooltip: 'Créer un dossier',
        backgroundColor: Colors.indigo[800],
        child: Icon(Icons.create_new_folder),
      ),
    );
  }
}

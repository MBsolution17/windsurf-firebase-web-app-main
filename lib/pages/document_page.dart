// lib/pages/document_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;
import 'package:firebase_web_app/pages/docx_editor_page.dart'; // Import de DocxEditorPage
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import '../services/ai_service.dart';
import '../models/chat_message.dart';
import '../models/folder.dart';
import '../models/contact.dart';
import '../models/document.dart'; // Correction de l'import
import '../widgets/document_form_dialog.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart'; // Importation de google_fonts
import 'package:intl/intl.dart'; // Importation de intl pour formater les dates
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf_pdf; // Importation de syncfusion_flutter_pdf avec alias

class DocumentPage extends StatefulWidget {
  const DocumentPage({super.key});

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage> {
  final AIService _aiService = AIService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Liste des dossiers
  List<Folder> _folders = [];

  // Liste des documents du dossier sélectionné
  List<DocumentModel> _documents = [];

  // Liste des contacts du dossier sélectionné
  List<Contact> _contacts = [];

  // Liste des contacts disponibles pour l'association lors de la création de dossier
  List<Contact> _availableContacts = [];

  // Dossier actuellement sélectionné
  Folder? _selectedFolder;

  // ID du dossier actuellement sélectionné
  String? _selectedFolderId;

  // Polices Roboto
  late pw.Font robotoRegular;
  late pw.Font robotoBold;
  bool _fontsLoaded = false;

  // Ensemble des IDs des dossiers en cours de téléchargement
  final Set<String> _downloadingFolders = <String>{};

  // Variable pour indiquer si un traitement est en cours
  bool _isProcessing = false;

  // Abonnements Firestore
  StreamSubscription<QuerySnapshot>? _foldersSubscription;
  StreamSubscription<QuerySnapshot>? _documentsSubscription;
  StreamSubscription<QuerySnapshot>? _contactsSubscription;
  StreamSubscription<QuerySnapshot>? _availableContactsSubscription;

  // Formulaire d'ajout de contact
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Contrôleurs de texte pour le formulaire
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _externalInfoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchFolders();
    _fetchAvailableContacts();
    _loadFonts();
  }

  @override
  void dispose() {
    _foldersSubscription?.cancel();
    _documentsSubscription?.cancel();
    _contactsSubscription?.cancel();
    _availableContactsSubscription?.cancel();

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

  // Charger les polices Roboto
  Future<void> _loadFonts() async {
    try {
      final robotoRegularData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final robotoBoldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');

      robotoRegular = pw.Font.ttf(robotoRegularData.buffer.asByteData());
      robotoBold = pw.Font.ttf(robotoBoldData.buffer.asByteData());

      if (mounted) {
        setState(() {
          _fontsLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Erreur lors du chargement des polices: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du chargement des polices')),
        );
      }
    }
  }

  // Récupère les dossiers depuis Firestore
  void _fetchFolders() {
    final user = _auth.currentUser;
    if (user == null) return;

    _foldersSubscription = _firestore
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

  // Récupère les documents d'un dossier spécifique
  void _fetchDocuments(String folderId) {
    _documentsSubscription?.cancel();

    _documentsSubscription = _firestore
        .collection('documents')
        .where('folderId', isEqualTo: folderId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _documents = snapshot.docs.map((doc) => DocumentModel.fromFirestore(doc)).toList();
        });
      }
    }, onError: (error) {
      debugPrint('Erreur lors de la récupération des documents: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la récupération des documents')),
        );
      }
    });
  }

  // Récupère les contacts d'un dossier spécifique
  void _fetchContacts(String folderId) {
    _contactsSubscription?.cancel();

    _contactsSubscription = _firestore
        .collection('contacts')
        .where('folderId', isEqualTo: folderId)
        .where('userId', isEqualTo: _auth.currentUser?.uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _contacts = snapshot.docs.map((doc) => Contact.fromFirestore(doc)).toList();
        });
      }
    }, onError: (error) {
      debugPrint('Erreur lors de la récupération des contacts: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la récupération des contacts')),
        );
      }
    });
  }

  // Récupère les contacts disponibles pour l'association lors de la création de dossier
  void _fetchAvailableContacts() {
    final user = _auth.currentUser;
    if (user == null) return;

    _availableContactsSubscription = _firestore
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
    final user = _auth.currentUser;
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
      User? currentUser = _auth.currentUser;
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
        folderId: _selectedFolderId ?? '', // Utilisation de _selectedFolderId
        timestamp: DateTime.now(),
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
          _selectedFolder = null; // Optionnel: réinitialiser le dossier sélectionné
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Contact supprimé avec succès')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la suppression du contact')),
        );
      }
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
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

  // Widget pour afficher la liste des contacts existants dans un dossier spécifique
  Widget _buildContactList(List<Contact> contacts) {
    if (contacts.isEmpty) {
      return Text(
        'Aucun contact dans ce dossier.',
        style: GoogleFonts.roboto(
          fontSize: 14,
          color: Colors.grey[600],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
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
  }

  // Méthode pour créer un document via l'IA
  Future<void> _generateDocument(String title, String content) async {
    final enrichedContent = content;
    await _createDocxDocument(title, enrichedContent);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Document généré avec succès')),
      );
    }
  }

  // Méthode pour créer un document DOCX
  Future<void> _createDocxDocument(String title, String content) async {
    if (!_fontsLoaded) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Les polices ne sont pas encore chargées. Veuillez réessayer.')),
        );
      }
      return;
    }

    try {
      // Utilisation de l'API ConvertAPI pour créer un DOCX
      final convertApiUrl = 'https://v2.convertapi.com/convert/txt/to/docx?Secret=secret_jPYJFfijH2cj3g8h';
      final response = await http.post(
        Uri.parse(convertApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'Files': [
            {
              'File': 'data:text/plain;base64,${base64Encode(utf8.encode(content))}',
              'Name': 'document.txt',
            },
          ],
          'Parameters': {
            'File': 'document.txt',
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final docxUrl = data['Files']?[0]?['Url'];
        if (docxUrl != null) {
          // Télécharger le DOCX depuis l'URL
          final docxResponse = await http.get(Uri.parse(docxUrl));
          if (docxResponse.statusCode == 200) {
            final docxBytes = docxResponse.bodyBytes;

            // Uploader sur Firebase Storage
            if (_selectedFolder == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Aucun dossier sélectionné.')),
              );
              return;
            }

            final storageRef = FirebaseStorage.instance
                .ref()
                .child('documents/${_selectedFolder!.id}/$title.docx');
            await storageRef.putData(docxBytes);
            final downloadURL = await storageRef.getDownloadURL();

            // Enregistrer dans Firestore avec l'URL et le dossier
            await _firestore.collection('documents').add({
              'title': title,
              'type': 'docx', // Type mis à jour
              'url': downloadURL,
              'folderId': _selectedFolder!.id,
              'timestamp': FieldValue.serverTimestamp(),
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('DOCX téléchargé et uploadé avec succès')),
              );
            }
          }
        }
      } else {
        throw Exception('Erreur lors de la création du DOCX.');
      }
    } catch (e) {
      debugPrint('Erreur lors de la création du document DOCX: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la création du document DOCX')),
        );
      }
    }
  }

  // Méthode pour télécharger un fichier
  Future<void> _downloadFile(String url, String fileName, String type) async {
    try {
      // Ouvrir le lien directement pour le téléchargement
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", '$fileName.$type')
        ..click();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fichier téléchargé avec succès')),
        );
      }
    } catch (e) {
      debugPrint('Erreur lors du téléchargement du fichier: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du téléchargement du fichier')),
        );
      }
    }
  }

  // Fonction pour télécharger le dossier complet avec universal_html
  Future<void> _downloadFolder(Folder folder) async {
    setState(() {
      _downloadingFolders.add(folder.id);
    });

    try {
      // Récupérer tous les documents du dossier
      QuerySnapshot snapshot = await _firestore
          .collection('documents')
          .where('folderId', isEqualTo: folder.id)
          .get();

      // Récupérer tous les contacts du dossier
      QuerySnapshot contactSnapshot = await _firestore
          .collection('contacts')
          .where('folderId', isEqualTo: folder.id)
          .get();

      if (snapshot.docs.isEmpty && contactSnapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Le dossier est vide. Aucun fichier à télécharger.')),
          );
        }
        return;
      }

      // Créer une archive ZIP
      Archive archive = Archive();

      // Ajouter les documents à l'archive
      for (var doc in snapshot.docs) {
        String url = doc['url'] ?? '';
        String title = doc['title'] ?? 'Sans titre';
        String type = doc['type'] ?? 'pdf';

        if (url.isEmpty) continue;

        // Télécharger le fichier
        http.Response response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          List<int> bytes = response.bodyBytes;

          // Déterminer le nom du fichier avec extension
          String fileName = '$title.${type.toLowerCase()}';

          // Ajouter le fichier à l'archive
          archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
        } else {
          debugPrint('Erreur lors du téléchargement du fichier: $url');
        }
      }

      // Ajouter les contacts à l'archive sous forme de fichiers JSON
      for (var contactDoc in contactSnapshot.docs) {
        String folderId = contactDoc['folderId'] ?? '';
        if (folderId.isEmpty) continue;

        Contact contact = Contact.fromFirestore(contactDoc);

        Map<String, dynamic> contactMap = {
          'firstName': contact.firstName,
          'lastName': contact.lastName,
          'email': contact.email,
          'phone': contact.phone,
          'address': contact.address,
          'company': contact.company,
          'externalInfo': contact.externalInfo,
          'folderId': contact.folderId,
          'timestamp': contact.timestamp.toIso8601String(),
        };

        String contactJson = jsonEncode(contactMap);
        String fileName = '${contact.firstName}_${contact.lastName}.json';

        archive.addFile(ArchiveFile(fileName, contactJson.length, utf8.encode(contactJson)));
      }

      // Encoder l'archive en bytes ZIP
      List<int> zipData = ZipEncoder().encode(archive)!;
      Uint8List zipBytes = Uint8List.fromList(zipData);

      // Créer un blob à partir des bytes ZIP
      final blob = html.Blob([zipBytes], 'application/zip');

      // Créer un URL pour le blob
      final urlObject = html.Url.createObjectUrlFromBlob(blob);

      // Créer un élément <a> pour déclencher le téléchargement
      final anchor = html.AnchorElement(href: urlObject)
        ..setAttribute("download", '${folder.name}.zip')
        ..click();

      // Libérer l'URL du blob
      html.Url.revokeObjectUrl(urlObject);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dossier "${folder.name}" téléchargé avec succès.')),
        );
      }
    } catch (e) {
      debugPrint('Erreur lors du téléchargement du dossier: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du téléchargement du dossier.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingFolders.remove(folder.id);
        });
      }
    }
  }

  // Méthode pour importer un document
  Future<void> _importDocument() async {
    if (_selectedFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Veuillez sélectionner un dossier')),
      );
      return;
    }

    try {
      // Ouvrir le sélecteur de fichiers
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'docx'], // Ajout de 'docx'
      );

      if (result != null) {
        // Obtenir le nom du fichier sélectionné
        String fileName = result.files.single.name;

        // Lire le fichier en tant que bytes
        Uint8List? fileBytes = result.files.single.bytes;

        if (fileBytes == null && !kIsWeb) {
          // Sur mobile, lire les bytes à partir du chemin
          String? path = result.files.single.path;
          if (path != null) {
            File file = File(path);
            fileBytes = await file.readAsBytes();
          }
        }

        if (fileBytes == null || fileBytes.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur lors de la lecture du fichier.')),
            );
          }
          return;
        }

        // Déterminer le type du fichier
        String fileType = fileName.split('.').last.toLowerCase();
        if (fileType != 'pdf' && fileType != 'txt' && fileType != 'docx') {
          fileType = 'other';
        }

        if (fileType == 'docx') {
          // Traitement spécifique pour DOCX
          await _processDocxImport(fileBytes, fileName);
        } else {
          // Traitement pour les autres types de fichiers (PDF, TXT)
          try {
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('documents/${_selectedFolder!.id}/$fileName');
            await storageRef.putData(fileBytes);
            final fileUrl = await storageRef.getDownloadURL();

            // Enregistrer les métadonnées dans Firestore
            await _firestore.collection('documents').add({
              'title': fileName,
              'type': fileType,
              'url': fileUrl,
              'folderId': _selectedFolder!.id,
              'timestamp': FieldValue.serverTimestamp(),
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Document importé avec succès')),
              );
            }
          } catch (e) {
            debugPrint('Erreur lors de l\'importation du document: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Erreur lors de l\'importation du document')),
              );
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Aucun fichier sélectionné.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Erreur lors de l\'importation du document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'importation du document')),
        );
      }
    }
  }

  // Méthode pour traiter l'importation de DOCX
  Future<void> _processDocxImport(Uint8List docxBytes, String fileName) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // Décompresser le fichier DOCX
      final archive = ZipDecoder().decodeBytes(docxBytes);
      final documentFile = archive.files.firstWhere(
        (file) => file.name == 'word/document.xml',
        orElse: () => throw Exception('document.xml non trouvé dans le DOCX.'),
      );
      String documentXml = String.fromCharCodes(documentFile.content as List<int>);

      // Nettoyer le contenu XML pour extraire uniquement les variables entre {{...}}
      final regex = RegExp(r'{{(.*?)}}');
      final matches = regex.allMatches(documentXml).toList();

      if (matches.isEmpty) {
        throw Exception('Aucune variable valide trouvée dans le document.');
      }

      // Extraire et nettoyer les variables
      final variables = matches
          .map((match) => match.group(1)!)
          .map((variable) => variable.replaceAll(RegExp(r'<[^>]*>'), '').trim()) // Supprimer les balises XML
          .toSet()
          .toList();

      debugPrint("Variables nettoyées : $variables");

      // Récupérer les valeurs des variables depuis Firestore
      Map<String, String> fieldValues = {};
      for (var variable in variables) {
        final docSnapshot = await _firestore.collection('variables').doc(variable).get();

        if (docSnapshot.exists && docSnapshot.data()!.containsKey('value')) {
          fieldValues[variable] = docSnapshot['value'] ?? '';
        } else {
          fieldValues[variable] = 'Valeur manquante'; // Valeur par défaut si la variable n'existe pas
        }
      }

      debugPrint("Valeurs des variables : $fieldValues");

      // Remplacer les variables dans le contenu XML
      fieldValues.forEach((key, value) {
        documentXml = documentXml.replaceAll('{{$key}}', value);
      });

      // Vérifier les remplacements restants
      final remainingMatches = regex.allMatches(documentXml).toList();
      if (remainingMatches.isNotEmpty) {
        debugPrint('Certaines variables n\'ont pas pu être remplacées : $remainingMatches');
      }

      // Mettre à jour le fichier document.xml avec les nouvelles données
      final updatedDocumentFile = ArchiveFile(
        'word/document.xml',
        documentXml.length,
        utf8.encode(documentXml),
      );

      // Recréer l'archive DOCX avec le contenu mis à jour
      final updatedArchive = Archive();
      for (var file in archive.files) {
        if (file.name != 'word/document.xml') {
          updatedArchive.addFile(file);
        }
      }
      updatedArchive.addFile(updatedDocumentFile);

      // Encoder l'archive mise à jour
      final updatedDocxBytes = ZipEncoder().encode(updatedArchive)!;

      // Télécharger le fichier mis à jour sur Firebase Storage
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('documents/${_selectedFolder!.id}/modified_$fileName.docx');
      await storageRef.putData(Uint8List.fromList(updatedDocxBytes));
      final downloadURL = await storageRef.getDownloadURL();

      // Enregistrer les métadonnées dans Firestore
      await _firestore.collection('documents').add({
        'title': 'Modified $fileName',
        'type': 'docx',
        'url': downloadURL,
        'folderId': _selectedFolder!.id,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('DOCX modifié et uploadé avec succès')),
        );
      }

      // Optionnel : Rafraîchir la liste des documents
      _fetchDocuments(_selectedFolder!.id);
    } catch (e) {
      debugPrint('Erreur lors du traitement du DOCX: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du traitement du DOCX: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // Afficher un dialogue pour créer un nouveau document
  void _showCreateDocumentDialog() {
    if (_selectedFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Veuillez sélectionner un dossier avant de créer un document.')),
      );
      return;
    }

    String documentTitle = '';
    String documentContent = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Créer un Nouveau Document'),
        content: Column(
          mainAxisSize: MainAxisSize.min, // Limite la taille de la Column
          children: [
            TextField(
              decoration: InputDecoration(hintText: 'Titre du document'),
              onChanged: (value) {
                documentTitle = value;
              },
            ),
            SizedBox(height: 20),
            TextField(
              decoration: InputDecoration(hintText: 'Contenu du document'),
              maxLines: 5,
              onChanged: (value) {
                documentContent = value;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              if (documentTitle.trim().isNotEmpty && documentContent.trim().isNotEmpty) {
                _generateDocument(documentTitle.trim(), documentContent.trim());
                Navigator.of(context).pop();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo[800],
            ),
            child: Text('Créer'),
          ),
        ],
      ),
    );
  }

  // Afficher un dialogue pour importer un document
  void _showImportDocumentDialog() {
    if (_selectedFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Veuillez sélectionner un dossier avant d\'importer un document.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Importer un Document'),
        content: Text('Sélectionnez un fichier à importer'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              _importDocument();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
            ),
            child: Text('Importer'),
          ),
        ],
      ),
    );
  }

  // Nouvelle Méthode pour Prendre Exemple sur un DOCX Existant
  Future<void> _showExampleFromDocxDialog() async {
    // Ouvrir le sélecteur de fichiers pour les DOCX
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
    );

    if (result != null) {
      Uint8List? fileBytes = result.files.single.bytes;
      if (fileBytes == null && result.files.single.path != null) {
        // Sur mobile, lire les bytes à partir du chemin
        File file = File(result.files.single.path!);
        fileBytes = await file.readAsBytes();
      }

      if (fileBytes != null && fileBytes.isNotEmpty) {
        try {
          // Passer les bytes DOCX à l'éditeur DOCX
          final modifiedDocxBytes = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DocxEditorPage(
                docxBytes: fileBytes!,
              ),
            ),
          );

          // Si des modifications ont été apportées
          if (modifiedDocxBytes != null && modifiedDocxBytes is Uint8List) {
            // Uploader le DOCX modifié sur Firebase Storage
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('documents/${_selectedFolder!.id}/example_modified.docx');
            await storageRef.putData(modifiedDocxBytes);
            final newDownloadURL = await storageRef.getDownloadURL();

            // Enregistrer dans Firestore avec l'URL et le dossier
            await _firestore.collection('documents').add({
              'title': 'Example Modified',
              'type': 'docx',
              'url': newDownloadURL,
              'folderId': _selectedFolder!.id,
              'timestamp': FieldValue.serverTimestamp(),
            });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('DOCX modifié et uploadé avec succès')),
              );
            }

            // Optionnel : Rafraîchir la liste des documents
            _fetchDocuments(_selectedFolder!.id);
          }
        } catch (e) {
          debugPrint('Erreur lors de l\'édition du DOCX: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur lors de l\'édition du DOCX')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de lire le fichier DOCX sélectionné.')),
        );
      }
    }
  }

  // Méthode pour éditer un document DOCX
  Future<void> _editDocx(DocumentModel document) async {
    try {
      // Télécharger le fichier DOCX à éditer
      final response = await http.get(Uri.parse(document.url));
      if (response.statusCode == 200) {
        final docxBytes = response.bodyBytes;

        // Naviguer vers l'éditeur de DOCX et attendre le résultat
        final modifiedDocxBytes = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DocxEditorPage(
              docxBytes: docxBytes,
            ),
          ),
        );

        // Si des modifications ont été apportées
        if (modifiedDocxBytes != null && modifiedDocxBytes is Uint8List) {
          // Uploader le DOCX modifié sur Firebase Storage
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('documents/${_selectedFolder!.id}/${document.title}.docx');
          await storageRef.putData(modifiedDocxBytes);
          final newDownloadURL = await storageRef.getDownloadURL();

          // Mettre à jour l'URL dans Firestore
          await _firestore.collection('documents').doc(document.id).update({
            'url': newDownloadURL,
            'timestamp': FieldValue.serverTimestamp(),
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('DOCX modifié et mis à jour avec succès')),
            );
          }

          // Optionnel : Rafraîchir la liste des documents
          _fetchDocuments(_selectedFolder!.id);
        }
      } else {
        throw Exception('Impossible de télécharger le DOCX');
      }
    } catch (e) {
      debugPrint('Erreur lors de l\'ouverture du DOCX: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'ouverture du DOCX')),
      );
    }
  }

  // Widget principal de la page
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gestion des Documents'),
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
          child: Column(
            children: [
              // Formulaire d'ajout de document
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ajouter un Nouveau Document',
                        style: GoogleFonts.roboto(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo[800],
                        ),
                      ),
                      SizedBox(height: 20),
                      // Bouton pour créer un document via l'IA
                      ElevatedButton(
                        onPressed: _showCreateDocumentDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo[800],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Text(
                          'Créer Document',
                          style: GoogleFonts.roboto(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      // Bouton pour importer un document
                      ElevatedButton(
                        onPressed: _showImportDocumentDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Text(
                          'Importer Document',
                          style: GoogleFonts.roboto(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      // Nouveau Bouton pour Prendre Exemple sur un DOCX
                      ElevatedButton(
                        onPressed: _showExampleFromDocxDialog, // Méthode mise à jour
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[600],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Text(
                          'Prendre Exemple sur un DOCX',
                          style: GoogleFonts.roboto(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 30),
              // Liste des Dossiers Existants
              Text(
                'Dossiers Existants',
                style: GoogleFonts.roboto(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo[800],
                ),
              ),
              SizedBox(height: 10),
              // Liste des Dossiers et Contenu Sélectionné
              Expanded(
                child: Row(
                  children: [
                    // Liste des Dossiers
                    Expanded(
                      flex: 1,
                      child: _buildFolderList(),
                    ),
                    SizedBox(width: 20),
                    // Contenu du Dossier Sélectionné
                    Expanded(
                      flex: 2,
                      child: _selectedFolder != null
                          ? _buildSelectedFolderContent()
                          : Center(
                              child: Text(
                                'Sélectionnez un dossier pour voir son contenu.',
                                style: GoogleFonts.roboto(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
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

  // Widget pour afficher la liste des dossiers existants
  Widget _buildFolderList() {
    if (_folders.isEmpty) {
      return Center(
        child: Text(
          'Aucun dossier trouvé.',
          style: GoogleFonts.roboto(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: ListTile(
            title: Text(
              folder.name,
              style: GoogleFonts.roboto(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            subtitle: Text('Créé le: ${DateFormat.yMMMMd().add_jm().format(folder.timestamp)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.download),
                  color: Colors.blue,
                  onPressed: () {
                    _downloadFolder(folder);
                  },
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Confirmer la suppression'),
                        content: Text('Êtes-vous sûr de vouloir supprimer ce dossier?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _deleteFolder(folder.id);
                            },
                            child: Text('Supprimer'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            selected: _selectedFolder?.id == folder.id,
            selectedTileColor: Colors.indigo[50],
            onTap: () {
              setState(() {
                _selectedFolder = folder;
                _selectedFolderId = folder.id;
              });
              debugPrint('Dossier sélectionné: ${folder.name} (ID: ${folder.id})');
              _fetchDocuments(folder.id);
              _fetchContacts(folder.id);
            },
          ),
        );
      },
    );
  }

  // Méthode pour supprimer un dossier
  Future<void> _deleteFolder(String folderId) async {
    try {
      // Supprimer le dossier
      await _firestore.collection('folders').doc(folderId).delete();

      // Mettre à jour les contacts associés en supprimant leur folderId
      WriteBatch batch = _firestore.batch();
      QuerySnapshot contactsSnapshot = await _firestore
          .collection('contacts')
          .where('folderId', isEqualTo: folderId)
          .get();

      for (var doc in contactsSnapshot.docs) {
        batch.update(doc.reference, {'folderId': FieldValue.delete()});
      }

      await batch.commit();

      // Supprimer les documents associés
      WriteBatch deleteBatch = _firestore.batch();
      QuerySnapshot documentsSnapshot = await _firestore
          .collection('documents')
          .where('folderId', isEqualTo: folderId)
          .get();

      for (var doc in documentsSnapshot.docs) {
        deleteBatch.delete(doc.reference);
      }

      await deleteBatch.commit();

      // Si le dossier supprimé est actuellement sélectionné, réinitialiser la sélection
      if (_selectedFolder?.id == folderId) {
        setState(() {
          _selectedFolder = null;
          _selectedFolderId = null;
          _documents = [];
          _contacts = [];
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dossier et contenus supprimés avec succès')),
      );
    } catch (e) {
      debugPrint('Erreur lors de la suppression du dossier: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression du dossier')),
      );
    }
  }

  // Méthode pour télécharger le contenu du dossier sélectionné
  Widget _buildSelectedFolderContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dossier: ${_selectedFolder!.name}',
          style: GoogleFonts.roboto(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.indigo[800],
          ),
        ),
        SizedBox(height: 10),
        // Liste des Documents
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Documents',
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo[700],
                ),
              ),
              SizedBox(height: 5),
              Expanded(
                child: _documents.isNotEmpty
                    ? ListView.builder(
                        shrinkWrap: true,
                        itemCount: _documents.length,
                        itemBuilder: (context, index) {
                          final document = _documents[index];
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(vertical: 6.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.0),
                            ),
                            child: ListTile(
                              leading: Icon(
                                _getDocumentIcon(document.type),
                                color: _getDocumentColor(document.type),
                              ),
                              title: Text(
                                document.title,
                                style: GoogleFonts.roboto(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              subtitle: Text('Type: ${document.type.toUpperCase()}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Bouton d'édition pour les DOCX
                                  if (document.type.toLowerCase() == 'docx')
                                    IconButton(
                                      icon: Icon(Icons.edit, color: Colors.orange),
                                      onPressed: () {
                                        _editDocx(document); // Utilisation de la méthode d'édition DOCX
                                      },
                                      tooltip: 'Éditer le DOCX',
                                    ),
                                  IconButton(
                                    icon: Icon(Icons.download, color: Colors.green),
                                    onPressed: () {
                                      _downloadFile(
                                        document.url,
                                        document.title,
                                        document.type,
                                      );
                                    },
                                    tooltip: 'Télécharger',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : Text(
                        'Aucun document dans ce dossier.',
                        style: GoogleFonts.roboto(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
              ),
            ],
          ),
        ),
        SizedBox(height: 10),
        // Liste des Contacts
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Contacts',
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo[700],
                ),
              ),
              SizedBox(height: 5),
              Expanded(
                child: _buildContactList(_contacts),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Méthode pour obtenir l'icône en fonction du type de document
  IconData _getDocumentIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'docx':
        return Icons.description;
      case 'txt':
        return Icons.note;
      default:
        return Icons.insert_drive_file;
    }
  }

  // Méthode pour obtenir la couleur en fonction du type de document
  Color _getDocumentColor(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'docx':
        return Colors.blue;
      case 'txt':
        return Colors.grey;
      default:
        return Colors.black;
    }
  }
}

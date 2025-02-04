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
import '../models/document.dart';
import '../widgets/document_form_dialog.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf_pdf;

class DocumentPage extends StatefulWidget {
  final String workspaceId; // Paramètre requis

  const DocumentPage({
    Key? key,
    required this.workspaceId,
  }) : super(key: key);

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage> {
  final AIService _aiService = AIService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late String workspaceId; // Stocke workspaceId
  late String userId; // Stocke userId

  // Liste des dossiers
  List<Folder> _folders = [];

  // Liste des documents du dossier sélectionné
  List<DocumentModel> _documents = [];

  // Liste des contacts du dossier sélectionné
  List<Contact> _contacts = [];

  // Liste des contacts disponibles (pour associer lors de la création d’un dossier)
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

  // Variable indiquant si un traitement est en cours
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
    workspaceId = widget.workspaceId; // Initialisation de workspaceId
    userId = _auth.currentUser?.uid ?? ''; // Initialisation de userId

    // Logs pour débogage
    print('Initialisation de DocumentPage');
    print('Workspace ID: $workspaceId');
    print('User ID: $userId');

    _fetchFolders();
    _fetchAvailableContacts();
    _loadFonts();
    _listenToActions(); // Écoute des actions de l'IA
  }

  @override
  void dispose() {
    _foldersSubscription?.cancel();
    _documentsSubscription?.cancel();
    _contactsSubscription?.cancel();
    _availableContactsSubscription?.cancel();

    // Dispose des contrôleurs
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
      print('Polices Roboto chargées avec succès');
    } catch (e) {
      print('Erreur lors du chargement des polices: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors du chargement des polices')),
        );
      }
    }
  }

  // Récupère les dossiers depuis Firestore (dans workspaces/{workspaceId}/folders)
  void _fetchFolders() {
    print('Fetching folders for workspaceId: $workspaceId and userId: $userId');
    _foldersSubscription = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('folders')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      print('Fetched ${snapshot.docs.length} folders');
      if (mounted) {
        setState(() {
          _folders = snapshot.docs.map((doc) => Folder.fromFirestore(doc)).toList();
        });
      }
    }, onError: (error) {
      print('Error fetching folders: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la récupération des dossiers')),
        );
      }
    });
  }

  // Récupère les documents d'un dossier spécifique (dans workspaces/{workspaceId}/documents)
  void _fetchDocuments(String folderId) {
    print('Fetching documents for folderId: $folderId');
    _documentsSubscription?.cancel();

    _documentsSubscription = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('documents')
        .where('folderId', isEqualTo: folderId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      print('Fetched ${snapshot.docs.length} documents for folderId: $folderId');
      if (mounted) {
        setState(() {
          _documents = snapshot.docs.map((doc) => DocumentModel.fromFirestore(doc)).toList();
        });
      }
    }, onError: (error) {
      print('Error fetching documents: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la récupération des documents')),
        );
      }
    });
  }

  // Récupère les contacts d'un dossier spécifique (dans workspaces/{workspaceId}/contacts)
  void _fetchContacts(String folderId) {
    print('Fetching contacts for folderId: $folderId');
    _contactsSubscription?.cancel();

    _contactsSubscription = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('contacts')
        .where('folderId', isEqualTo: folderId)
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      print('Fetched ${snapshot.docs.length} contacts for folderId: $folderId');
      if (mounted) {
        setState(() {
          _contacts = snapshot.docs.map((doc) => Contact.fromFirestore(doc)).toList();
        });
      }
    }, onError: (error) {
      print('Error fetching contacts: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la récupération des contacts')),
        );
      }
    });
  }

  // Récupère les contacts disponibles (dans workspaces/{workspaceId}/contacts)
  void _fetchAvailableContacts() {
    print('Fetching available contacts for userId: $userId');
    _availableContactsSubscription = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('contacts')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      print('Fetched ${snapshot.docs.length} available contacts');
      if (mounted) {
        setState(() {
          _availableContacts = snapshot.docs.map((doc) => Contact.fromFirestore(doc)).toList();
        });
      }
    }, onError: (error) {
      print('Error fetching available contacts: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la récupération des contacts disponibles')),
        );
      }
    });
  }

  // Créer un nouveau dossier (dans workspaces/{workspaceId}/folders)
  Future<void> _createFolder(String name, List<String> contactIds) async {
    try {
      DocumentReference folderRef = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('folders')
          .add({
        'name': name,
        'userId': userId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      String newFolderId = folderRef.id;
      print('Folder "$name" created with ID: $newFolderId');

      if (contactIds.isNotEmpty) {
        WriteBatch batch = _firestore.batch();

        for (String contactId in contactIds) {
          DocumentReference contactRef = _firestore
              .collection('workspaces')
              .doc(workspaceId)
              .collection('contacts')
              .doc(contactId);
          batch.update(contactRef, {'folderId': newFolderId});
          print('Assigned contactId: $contactId to folderId: $newFolderId');
        }

        await batch.commit();
        print('Batch update for contacts completed');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dossier créé avec succès')),
        );
      }
    } catch (e) {
      print('Error creating folder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la création du dossier')),
        );
      }
    }
  }

  // Soumettre le formulaire et ajouter un contact (dans workspaces/{workspaceId}/contacts)
  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      String firstName = _firstNameController.text.trim();
      String lastName = _lastNameController.text.trim();
      String email = _emailController.text.trim();
      String phone = _phoneController.text.trim();
      String address = _addressController.text.trim();
      String company = _companyController.text.trim();
      String externalInfo = _externalInfoController.text.trim();

      Contact newContact = Contact(
        id: '',
        userId: userId,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        address: address,
        company: company,
        externalInfo: externalInfo,
        folderId: _selectedFolderId ?? '',
        timestamp: DateTime.now(),
      );

      try {
        await _firestore
            .collection('workspaces')
            .doc(workspaceId)
            .collection('contacts')
            .add(newContact.toMap());

        print('Contact ajouté: ${newContact.toMap()}');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact ajouté avec succès')),
        );

        _formKey.currentState!.reset();
        setState(() {
          _selectedFolderId = null;
          _selectedFolder = null;
        });
      } catch (e) {
        print('Error adding contact: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de l\'ajout du contact')),
        );
      }
    }
  }

  // Afficher un dialogue pour créer un nouveau dossier
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
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Nom du dossier',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    folderName = value;
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'Associer des Contacts (Optionnel)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
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

  // Supprimer un contact (dans workspaces/{workspaceId}/contacts)
  Future<void> _deleteContact(String contactId) async {
    try {
      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('contacts')
          .doc(contactId)
          .delete();

      print('Contact supprimé: $contactId');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact supprimé avec succès')),
        );
      }
    } catch (e) {
      print('Error deleting contact: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la suppression du contact')),
        );
      }
    }
  }

  // Afficher les détails d'un contact
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
                if (contact.email.isNotEmpty) Text('Email: ${contact.email}'),
                const SizedBox(height: 8),
                if (contact.phone.isNotEmpty) Text('Téléphone: ${contact.phone}'),
                const SizedBox(height: 8),
                if (contact.address.isNotEmpty) Text('Adresse: ${contact.address}'),
                const SizedBox(height: 8),
                if (contact.company.isNotEmpty) Text('Entreprise: ${contact.company}'),
                const SizedBox(height: 8),
                if (contact.externalInfo.isNotEmpty)
                  Text('Informations Externes: ${contact.externalInfo}'),
                const SizedBox(height: 8),
                if (contact.folderId.isNotEmpty)
                  FutureBuilder<DocumentSnapshot>(
                    future: _firestore
                        .collection('workspaces')
                        .doc(workspaceId)
                        .collection('folders')
                        .doc(contact.folderId)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Text('Dossier: Chargement...');
                      }
                      if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                        return const Text('Dossier: Inconnu');
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
              child: const Text('Fermer'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  // Liste des contacts
  Widget _buildContactList(List<Contact> contacts) {
    if (contacts.isEmpty) {
      return Text(
        'Aucun contact dans ce dossier.',
        style: GoogleFonts.roboto(fontSize: 14, color: Colors.grey[600]),
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
                contact.firstName.isNotEmpty ? contact.firstName[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              '${contact.firstName} ${contact.lastName}',
              style: GoogleFonts.roboto(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contact.email.isNotEmpty) Text('Email: ${contact.email}'),
                if (contact.phone.isNotEmpty) Text('Téléphone: ${contact.phone}'),
                if (contact.company.isNotEmpty) Text('Entreprise: ${contact.company}'),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Confirmer la suppression'),
                        content: const Text('Êtes-vous sûr de vouloir supprimer ce contact?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _deleteContact(contact.id);
                            },
                            child: const Text('Supprimer'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.blue),
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

  // Générer un document via l'IA -> crée un DOCX
  Future<void> _generateDocument(String title, String content) async {
    final enrichedContent = content;
    await _createDocxDocument(title, enrichedContent);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document généré avec succès')),
      );
    }
  }

  // Créer un document DOCX (dans workspaces/{workspaceId}/documents)
  Future<void> _createDocxDocument(String title, String content) async {
    if (!_fontsLoaded) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Les polices ne sont pas encore chargées. Veuillez réessayer.')),
        );
      }
      return;
    }

    if (_selectedFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dossier non sélectionné.')),
      );
      return;
    }

    try {
      // Utilisation de l'API ConvertAPI pour créer un DOCX à partir d'un TXT
      const convertApiUrl = 'https://v2.convertapi.com/convert/txt/to/docx?Secret=secret_jPYJFfijH2cj3g8h';

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
          final docxResponse = await http.get(Uri.parse(docxUrl));
          if (docxResponse.statusCode == 200) {
            final docxBytes = docxResponse.bodyBytes;

            // Uploader sur Firebase Storage
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('documents/${_selectedFolder!.id}/$title.docx');
            await storageRef.putData(docxBytes);
            final downloadURL = await storageRef.getDownloadURL();

            // Enregistrer dans Firestore
            await _firestore
                .collection('workspaces')
                .doc(workspaceId)
                .collection('documents')
                .add({
              'title': title,
              'type': 'docx',
              'url': downloadURL,
              'folderId': _selectedFolder!.id,
              'timestamp': FieldValue.serverTimestamp(),
            });

            print('Document "$title.docx" créé et uploadé avec succès');

            // Rafraîchir la liste des documents
            _fetchDocuments(_selectedFolder!.id);
          } else {
            throw Exception('Erreur lors du téléchargement du DOCX.');
          }
        } else {
          throw Exception('URL du DOCX non trouvée dans la réponse de l\'API.');
        }
      } else {
        throw Exception('Erreur lors de la création du DOCX: ${response.statusCode}');
      }
    } catch (e) {
      print('Error creating DOCX document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la création du document DOCX')),
        );
      }
    }
  }

  // Télécharger un fichier
  Future<void> _downloadFile(String url, String fileName, String type) async {
    try {
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", '$fileName.$type')
        ..click();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fichier téléchargé avec succès')),
        );
      }
    } catch (e) {
      print('Error downloading file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors du téléchargement du fichier')),
        );
      }
    }
  }

  // Télécharger un dossier entier sous forme de ZIP
  Future<void> _downloadFolder(Folder folder) async {
    setState(() {
      _downloadingFolders.add(folder.id);
    });

    try {
      // Récupérer documents
      QuerySnapshot snapshot = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('documents')
          .where('folderId', isEqualTo: folder.id)
          .get();

      // Récupérer contacts
      QuerySnapshot contactSnapshot = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('contacts')
          .where('folderId', isEqualTo: folder.id)
          .get();

      if (snapshot.docs.isEmpty && contactSnapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Le dossier est vide. Aucun fichier à télécharger.')),
          );
        }
        return;
      }

      Archive archive = Archive();

      // Ajouter les documents
      for (var doc in snapshot.docs) {
        String url = doc['url'] ?? '';
        String title = doc['title'] ?? 'Sans titre';
        String type = doc['type'] ?? 'pdf';
        if (url.isEmpty) continue;

        http.Response response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          List<int> bytes = response.bodyBytes;
          String fileName = '$title.${type.toLowerCase()}';
          archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
          print('Ajout du fichier "$fileName" au ZIP');
        }
      }

      // Ajouter les contacts sous forme de JSON
      for (var contactDoc in contactSnapshot.docs) {
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
        print('Ajout du contact "$fileName" au ZIP');
      }

      List<int> zipData = ZipEncoder().encode(archive)!;
      Uint8List zipBytes = Uint8List.fromList(zipData);

      final blob = html.Blob([zipBytes], 'application/zip');
      final urlObject = html.Url.createObjectUrlFromBlob(blob);

      final anchor = html.AnchorElement(href: urlObject)
        ..setAttribute("download", '${folder.name}.zip')
        ..click();

      html.Url.revokeObjectUrl(urlObject);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dossier "${folder.name}" téléchargé avec succès.')),
        );
      }
      print('Dossier "${folder.name}" téléchargé avec succès');
    } catch (e) {
      print('Error downloading folder: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors du téléchargement du dossier.')),
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

  // Importer un document
  Future<void> _importDocument() async {
    if (_selectedFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un dossier')),
      );
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'docx'],
      );

      if (result != null) {
        String fileName = result.files.single.name;
        Uint8List? fileBytes = result.files.single.bytes;

        if (fileBytes == null && !kIsWeb) {
          String? path = result.files.single.path;
          if (path != null) {
            File file = File(path);
            fileBytes = await file.readAsBytes();
          }
        }

        if (fileBytes == null || fileBytes.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erreur lors de la lecture du fichier.')),
            );
          }
          return;
        }

        String fileType = fileName.split('.').last.toLowerCase();
        if (fileType != 'pdf' && fileType != 'txt' && fileType != 'docx') {
          fileType = 'other';
        }

        // Si docx
        if (fileType == 'docx') {
          await _processDocxImport(fileBytes, fileName);
        } else {
          try {
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('documents/${_selectedFolder!.id}/$fileName');
            await storageRef.putData(fileBytes);
            final fileUrl = await storageRef.getDownloadURL();

            await _firestore
                .collection('workspaces')
                .doc(workspaceId)
                .collection('documents')
                .add({
              'title': fileName,
              'type': fileType,
              'url': fileUrl,
              'folderId': _selectedFolder!.id,
              'timestamp': FieldValue.serverTimestamp(),
            });

            print('Document "$fileName" importé avec succès');

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Document importé avec succès')),
              );
            }
          } catch (e) {
            print('Error importing document: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Erreur lors de l\'importation du document')),
              );
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aucun fichier sélectionné.')),
          );
        }
      }
    } catch (e) {
      print('Error importing document: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de l\'importation du document')),
        );
      }
    }
  }

  // Traiter l'importation d'un DOCX
  Future<void> _processDocxImport(Uint8List docxBytes, String fileName) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final archive = ZipDecoder().decodeBytes(docxBytes);
      final documentFile = archive.files.firstWhere(
        (file) => file.name == 'word/document.xml',
        orElse: () => throw Exception('document.xml non trouvé dans le DOCX.'),
      );
      String documentXml = String.fromCharCodes(documentFile.content as List<int>);

      final regex = RegExp(r'{{(.*?)}}');
      final matches = regex.allMatches(documentXml).toList();

      if (matches.isEmpty) {
        throw Exception('Aucune variable valide trouvée dans le document.');
      }

      final variables = matches
          .map((match) => match.group(1)!)
          .map((variable) => variable.replaceAll(RegExp(r'<[^>]*>'), '').trim())
          .toSet()
          .toList();

      Map<String, String> fieldValues = {};
      for (var variable in variables) {
        final docSnapshot = await _firestore
            .collection('workspaces')
            .doc(workspaceId)
            .collection('variables')
            .doc(variable)
            .get();

        if (docSnapshot.exists && docSnapshot.data()!.containsKey('value')) {
          fieldValues[variable] = docSnapshot['value'] ?? '';
        } else {
          fieldValues[variable] = 'Valeur manquante';
        }
      }

      fieldValues.forEach((key, value) {
        documentXml = documentXml.replaceAll('{{$key}}', value);
      });

      final remainingMatches = regex.allMatches(documentXml).toList();
      if (remainingMatches.isNotEmpty) {
        debugPrint('Certaines variables n\'ont pas pu être remplacées: $remainingMatches');
      }

      final updatedDocumentFile = ArchiveFile(
        'word/document.xml',
        documentXml.length,
        utf8.encode(documentXml),
      );

      final updatedArchive = Archive();
      for (var file in archive.files) {
        if (file.name != 'word/document.xml') {
          updatedArchive.addFile(file);
        }
      }
      updatedArchive.addFile(updatedDocumentFile);

      final updatedDocxBytes = ZipEncoder().encode(updatedArchive)!;

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('documents/${_selectedFolder!.id}/modified_$fileName.docx');
      await storageRef.putData(Uint8List.fromList(updatedDocxBytes));
      final downloadURL = await storageRef.getDownloadURL();

      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('documents')
          .add({
        'title': 'Modified $fileName',
        'type': 'docx',
        'url': downloadURL,
        'folderId': _selectedFolder!.id,
        'timestamp': FieldValue.serverTimestamp(),
      });

      print('DOCX modifié et uploadé avec succès');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DOCX modifié et uploadé avec succès')),
        );
      }
      _fetchDocuments(_selectedFolder!.id);
    } catch (e) {
      print('Error processing DOCX import: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du traitement du DOCX: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  // Dialogue pour créer un nouveau document
  void _showCreateDocumentDialog() {
    if (_selectedFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un dossier avant de créer un document.')),
      );
      return;
    }

    String documentTitle = '';
    String documentContent = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Créer un Nouveau Document'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Titre du document',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                documentTitle = value;
              },
            ),
            const SizedBox(height: 20),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Contenu du document',
                border: OutlineInputBorder(),
              ),
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
            child: const Text('Annuler'),
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
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  // Dialogue pour importer un document
  void _showImportDocumentDialog() {
    if (_selectedFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un dossier avant d\'importer un document.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importer un Document'),
        content: const Text('Sélectionnez un fichier à importer'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              _importDocument();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Importer'),
          ),
        ],
      ),
    );
  }

  // Exemple depuis un DOCX via DocxEditorPage
  Future<void> _showExampleFromDocxDialog() async {
    // Ouvre le sélecteur de fichiers pour les DOCX
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
    );

    if (result != null) {
      Uint8List? fileBytes = result.files.single.bytes;
      if (fileBytes == null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        fileBytes = await file.readAsBytes();
      }

      if (fileBytes != null && fileBytes.isNotEmpty) {
        try {
          final Uint8List nonNullFileBytes = fileBytes;
          final modifiedDocxBytes = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DocxEditorPage(docxBytes: nonNullFileBytes),
            ),
          );

          if (modifiedDocxBytes != null && modifiedDocxBytes is Uint8List) {
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('documents/${_selectedFolder!.id}/example_modified.docx');
            await storageRef.putData(modifiedDocxBytes);
            final newDownloadURL = await storageRef.getDownloadURL();

            await _firestore
                .collection('workspaces')
                .doc(workspaceId)
                .collection('documents')
                .add({
              'title': 'Example Modified',
              'type': 'docx',
              'url': newDownloadURL,
              'folderId': _selectedFolder!.id,
              'timestamp': FieldValue.serverTimestamp(),
            });

            print('DOCX modifié et uploadé avec succès');

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('DOCX modifié et uploadé avec succès')),
              );
            }
            _fetchDocuments(_selectedFolder!.id);
          }
        } catch (e) {
          print('Error editing DOCX: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur lors de l\'édition du DOCX: $e')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de lire le fichier DOCX sélectionné.')),
        );
      }
    }
  }

  // Édition d'un DOCX déjà dans Firestore
  Future<void> _editDocx(DocumentModel document) async {
    try {
      final response = await http.get(Uri.parse(document.url));
      if (response.statusCode == 200) {
        final docxBytes = response.bodyBytes;

        final modifiedDocxBytes = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DocxEditorPage(docxBytes: docxBytes),
          ),
        );

        if (modifiedDocxBytes != null && modifiedDocxBytes is Uint8List) {
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('documents/${_selectedFolder!.id}/${document.title}.docx');
          await storageRef.putData(modifiedDocxBytes);
          final newDownloadURL = await storageRef.getDownloadURL();

          await _firestore
              .collection('workspaces')
              .doc(workspaceId)
              .collection('documents')
              .doc(document.id)
              .update({
            'url': newDownloadURL,
            'timestamp': FieldValue.serverTimestamp(),
          });

          print('DOCX modifié et mis à jour avec succès');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('DOCX modifié et mis à jour avec succès')),
            );
          }
          _fetchDocuments(_selectedFolder!.id);
        }
      } else {
        throw Exception('Impossible de télécharger le DOCX');
      }
    } catch (e) {
      print('Error editing DOCX: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de l\'ouverture du DOCX')),
      );
    }
  }

  // Écoute les actions de l'IA depuis Firestore
  void _listenToActions() {
    _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('actions')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      for (var docChange in snapshot.docChanges) {
        if (docChange.type == DocumentChangeType.added) {
          final actionData = docChange.doc.data();
          if (actionData != null) {
            _handleAction(actionData);
          }
        }
      }
    }, onError: (error) {
      print('Error listening to actions: $error');
    });
  }

  // Gère les actions reçues de l'IA
  void _handleAction(Map<String, dynamic> actionData) async {
    final action = actionData['action'];
    final data = actionData['data'];

    print('Action détectée: $action');

    switch (action) {
      case 'create_folder_with_document':
        final folderName = data['folderName'];
        final document = data['document'];
        final documentTitle = document['title'];
        final documentContent = document['content'];

        await _createFolder(folderName, []).then((_) {
          if (_folders.isNotEmpty) {
            final latestFolder = _folders.first;
            _createDocxDocument(documentTitle, documentContent);
          }
        });
        break;

      // D'autres actions peuvent être ajoutées ici

      default:
        print('Action inconnue: $action');
    }
  }

  // UI PRINCIPALE
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Documents'),
        backgroundColor: Colors.indigo[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder),
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
              // Carte pour ajouter/importer des documents
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
                      const SizedBox(height: 20),
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
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _showImportDocumentDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
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
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _showExampleFromDocxDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
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
              const SizedBox(height: 30),
              Text(
                'Dossiers Existants',
                style: GoogleFonts.roboto(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo[800],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  children: [
                    // Liste des dossiers
                    Expanded(
                      flex: 1,
                      child: _buildFolderList(),
                    ),
                    const SizedBox(width: 20),
                    // Contenu du dossier sélectionné
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
        child: const Icon(Icons.create_new_folder),
      ),
    );
  }

  // Liste des Dossiers
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
            subtitle: Text(
              'Créé le: ${DateFormat.yMMMMd().add_jm().format(folder.timestamp)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.download),
                  color: Colors.blue,
                  onPressed: () {
                    _downloadFolder(folder);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Confirmer la suppression'),
                        content: const Text('Êtes-vous sûr de vouloir supprimer ce dossier?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Annuler'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _deleteFolder(folder.id);
                            },
                            child: const Text('Supprimer'),
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
              _fetchDocuments(folder.id);
              _fetchContacts(folder.id);
            },
          ),
        );
      },
    );
  }

  // Supprime un dossier
  Future<void> _deleteFolder(String folderId) async {
    try {
      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('folders')
          .doc(folderId)
          .delete();

      print('Dossier supprimé: $folderId');

      // Supprime le folderId chez les contacts
      WriteBatch batch = _firestore.batch();
      QuerySnapshot contactsSnapshot = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('contacts')
          .where('folderId', isEqualTo: folderId)
          .get();

      for (var doc in contactsSnapshot.docs) {
        batch.update(doc.reference, {'folderId': FieldValue.delete()});
        print('Désassigné le contactId: ${doc.id} du folderId: $folderId');
      }
      await batch.commit();
      print('Batch update pour les contacts terminé');

      // Supprime les documents associés
      WriteBatch deleteBatch = _firestore.batch();
      QuerySnapshot documentsSnapshot = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('documents')
          .where('folderId', isEqualTo: folderId)
          .get();

      for (var doc in documentsSnapshot.docs) {
        deleteBatch.delete(doc.reference);
        print('Supprimé le documentId: ${doc.id} du folderId: $folderId');
      }
      await deleteBatch.commit();
      print('Batch delete pour les documents terminé');

      if (_selectedFolder?.id == folderId) {
        setState(() {
          _selectedFolder = null;
          _selectedFolderId = null;
          _documents = [];
          _contacts = [];
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dossier et contenus supprimés avec succès')),
      );
    } catch (e) {
      print('Error deleting folder: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la suppression du dossier')),
      );
    }
  }

  // Contenu du dossier sélectionné (documents + contacts)
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
        const SizedBox(height: 10),
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
              const SizedBox(height: 5),
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
                                  if (document.type.toLowerCase() == 'docx')
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.orange),
                                      onPressed: () {
                                        _editDocx(document);
                                      },
                                      tooltip: 'Éditer le DOCX',
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.download, color: Colors.green),
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
                        style: GoogleFonts.roboto(fontSize: 14, color: Colors.grey[600]),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
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
              const SizedBox(height: 5),
              Expanded(
                child: _buildContactList(_contacts),
              ),
            ],
          ),
        ),
      ],
    );
  }

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

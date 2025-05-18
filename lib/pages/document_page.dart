import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;
import 'package:firebase_web_app/pages/docx_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../services/ai_service.dart';
import '../models/folder.dart';
import '../models/contact.dart';
import '../models/document.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:xml/xml.dart';
import 'package:firebase_web_app/theme_provider.dart';

// Extension pour capitalisation
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}

class DocumentPage extends StatefulWidget {
  final String workspaceId;

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

  late String workspaceId;
  late String userId;

  List<Folder> _folders = [];
  List<DocumentModel> _documents = [];
  List<Contact> _contacts = [];
  List<Contact> _availableContacts = [];
  List<DocumentModel> _exampleDocuments = [];

  Folder? _selectedFolder;
  String? _selectedFolderId;

  late pw.Font robotoRegular;
  late pw.Font robotoBold;
  bool _fontsLoaded = false;

  final Set<String> _downloadingFolders = <String>{};

  bool _isProcessing = false;

  StreamSubscription<QuerySnapshot>? _foldersSubscription;
  StreamSubscription<QuerySnapshot>? _documentsSubscription;
  StreamSubscription<QuerySnapshot>? _contactsSubscription;
  StreamSubscription<QuerySnapshot>? _availableContactsSubscription;
  StreamSubscription<QuerySnapshot>? _exampleDocumentsSubscription;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _externalInfoController = TextEditingController();

  final String _chatGptApiKey = "votre_clé_api";

  Map<String, String> _globalMapping = {
    "date": "27/12/2024",
    "nom du contact": "Check&Consultzdd",
    "numéro": "12.23.001z",
    "adresse": "123 Rue Exemplez",
    "email": "contact@example.com",
  };

  @override
  void initState() {
    super.initState();
    debugPrint("Initialisation de DocumentPage pour workspaceId: ${widget.workspaceId}");
    workspaceId = widget.workspaceId;
    userId = _auth.currentUser?.uid ?? '';
    debugPrint("Utilisateur connecté: $userId");

    _loadGlobalMapping();
    _fetchFolders();
    _fetchAvailableContacts();
    _fetchExampleDocuments();
    _loadFonts();
    _listenToActions();
  }

  @override
  void dispose() {
    _foldersSubscription?.cancel();
    _documentsSubscription?.cancel();
    _contactsSubscription?.cancel();
    _availableContactsSubscription?.cancel();
    _exampleDocumentsSubscription?.cancel();

    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _companyController.dispose();
    _externalInfoController.dispose();

    super.dispose();
  }

  Future<void> _loadGlobalMapping() async {
    try {
      DocumentSnapshot snapshot = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('settings')
          .doc('globalMapping')
          .get();
      if (snapshot.exists) {
        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
        setState(() {
          _globalMapping = {
            "date": data["date"] ?? "27/12/2024",
            "nom du contact": data["nom du contact"] ?? "Check&Consultzdd",
            "numéro": data["numéro"] ?? "12.23.001z",
            "adresse": data["adresse"] ?? "123 Rue Exemplez",
            "email": data["email"] ?? "contact@example.com",
          };
          debugPrint("Mapping global chargé : $_globalMapping");
        });
      }
    } catch (e) {
      debugPrint("Erreur _loadGlobalMapping: $e");
    }
  }

  Future<void> _saveGlobalMapping() async {
    try {
      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('settings')
          .doc('globalMapping')
          .set(_globalMapping);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mapping global sauvegardé avec succès')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la sauvegarde du mapping global')));
    }
  }

  Future<void> _loadFonts() async {
    try {
      final robotoRegularData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final robotoBoldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      robotoRegular = pw.Font.ttf(robotoRegularData.buffer.asByteData());
      robotoBold = pw.Font.ttf(robotoBoldData.buffer.asByteData());
      setState(() {
        _fontsLoaded = true;
        debugPrint("Polices Roboto chargées avec succès");
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors du chargement des polices')));
      debugPrint("Erreur _loadFonts: $e");
    }
  }

  void _fetchFolders() {
    debugPrint("Récupération des dossiers pour userId: $userId");
    _foldersSubscription = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('folders')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _folders = snapshot.docs.map((doc) => Folder.fromFirestore(doc)).toList();
        debugPrint("Dossiers récupérés: ${_folders.length}");
        if (_selectedFolderId != null) {
          _selectedFolder = _folders.firstWhere(
            (f) => f.id == _selectedFolderId,
            orElse: () => _selectedFolder ?? _folders.first,
          );
          debugPrint("Dossier sélectionné mis à jour: ${_selectedFolder?.name}");
        }
      });
    }, onError: (e) {
      debugPrint("Erreur lors de la récupération des dossiers: $e");
    });
  }

  void _fetchDocuments(String folderId) {
    debugPrint("Récupération des documents pour folderId: $folderId");
    _documentsSubscription?.cancel();
    _documentsSubscription = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('documents')
        .where('folderId', isEqualTo: folderId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _documents = snapshot.docs.map((doc) => DocumentModel.fromFirestore(doc)).toList();
        debugPrint("Documents rechargés pour le dossier $folderId: ${_documents.length}");
      });
    }, onError: (e) {
      debugPrint("Erreur lors de la récupération des documents: $e");
    });
  }

  void _fetchExampleDocuments() {
    debugPrint("Récupération des documents exemples");
    _exampleDocumentsSubscription = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('documents')
        .where('folderId', isEqualTo: "example")
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _exampleDocuments = snapshot.docs.map((doc) => DocumentModel.fromFirestore(doc)).toList();
        debugPrint("Documents exemples récupérés: ${_exampleDocuments.length}");
      });
    }, onError: (e) {
      debugPrint("Erreur lors de la récupération des documents exemples: $e");
    });
  }

  void _fetchAvailableContacts() {
    debugPrint("Récupération des contacts disponibles");
    _availableContactsSubscription = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('contacts')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _availableContacts = snapshot.docs.map((doc) => Contact.fromFirestore(doc)).toList();
        debugPrint("Contacts disponibles récupérés: ${_availableContacts.length}");
      });
    }, onError: (e) {
      debugPrint("Erreur lors de la récupération des contacts: $e");
    });
  }

  void _fetchContacts(String folderId) {
    debugPrint("Récupération des contacts pour folderId: $folderId");
    _contactsSubscription?.cancel();
    _contactsSubscription = _firestore
        .collection('workspaces')
        .doc(workspaceId)
        .collection('contacts')
        .where('folderId', isEqualTo: folderId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      setState(() {
        _contacts = snapshot.docs.map((doc) => Contact.fromFirestore(doc)).toList();
        debugPrint("Contacts rechargés pour le dossier $folderId: ${_contacts.length}");
      });
    }, onError: (e) {
      debugPrint("Erreur lors de la récupération des contacts: $e");
    });
  }

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
        'isClosed': false,
      });
      String newFolderId = folderRef.id;
      if (contactIds.isNotEmpty) {
        WriteBatch batch = _firestore.batch();
        for (String contactId in contactIds) {
          DocumentReference contactRef = _firestore
              .collection('workspaces')
              .doc(workspaceId)
              .collection('contacts')
              .doc(contactId);
          batch.update(contactRef, {'folderId': newFolderId});
        }
        await batch.commit();
      }
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dossier créé avec succès')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la création du dossier')));
      debugPrint("Erreur _createFolder: $e");
    }
  }

  Future<void> _deleteFolder(String folderId) async {
    try {
      debugPrint("Suppression du dossier: $folderId");
      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('folders')
          .doc(folderId)
          .delete();
      WriteBatch batch = _firestore.batch();
      QuerySnapshot contactsSnapshot = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('contacts')
          .where('folderId', isEqualTo: folderId)
          .get();
      for (var doc in contactsSnapshot.docs) {
        batch.update(doc.reference, {'folderId': FieldValue.delete()});
      }
      await batch.commit();
      WriteBatch deleteBatch = _firestore.batch();
      QuerySnapshot documentsSnapshot = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('documents')
          .where('folderId', isEqualTo: folderId)
          .get();
      for (var doc in documentsSnapshot.docs) {
        deleteBatch.delete(doc.reference);
      }
      await deleteBatch.commit();
      if (_selectedFolder?.id == folderId) {
        setState(() {
          _selectedFolder = null;
          _selectedFolderId = null;
          _documents = [];
          _contacts = [];
          debugPrint("Dossier sélectionné supprimé, état réinitialisé");
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dossier et contenus supprimés avec succès')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la suppression du dossier')));
      debugPrint("Erreur _deleteFolder: $e");
    }
  }

 Future<void> _duplicateDocument(DocumentModel doc, String targetFolderId) async {
  debugPrint("Utilisateur actuel : ${FirebaseAuth.instance.currentUser?.uid ?? 'Non authentifié'}");
  try {
    debugPrint("Duplication de '${doc.title}' (type: ${doc.type}) vers dossier $targetFolderId");
    Uint8List? fileBytes;

    if (kIsWeb) {
      final response = await http.get(Uri.parse(doc.url));
      if (response.statusCode == 200) {
        fileBytes = response.bodyBytes;
      } else {
        throw Exception("Erreur HTTP ${response.statusCode} lors de la récupération du fichier.");
      }
    } else {
      final storageRef = FirebaseStorage.instance.refFromURL(doc.url);
      fileBytes = await storageRef.getData();
    }

    if (fileBytes == null) {
      throw Exception("Les données du fichier n'ont pas pu être récupérées (null).");
    }
    debugPrint("Fichier téléchargé, taille : ${fileBytes.length} octets");

    if (doc.type.toLowerCase() == 'docx' && doc.linkMapping != null && doc.linkMapping!.isNotEmpty) {
      Map<String, String> folderMapping = _selectedFolder?.folderMapping ?? _globalMapping;
      debugPrint("Application du mapping pour duplication : $folderMapping");
      fileBytes = _updateDocxPlaceholders(fileBytes, folderMapping, doc.linkMapping!);
    }

    final newFileName = "copy_${doc.title}";
    final newStorageRef = FirebaseStorage.instance
        .ref()
        .child('documents/$targetFolderId/$newFileName');
    await newStorageRef.putData(fileBytes);
    final newFileUrl = await newStorageRef.getDownloadURL();
    debugPrint("Nouveau fichier uploadé : $newFileUrl");

    await _firestore.collection('workspaces').doc(workspaceId).collection('documents').add({
      'title': doc.title,
      'type': doc.type,
      'url': newFileUrl,
      'folderId': targetFolderId,
      'linkMapping': doc.linkMapping ?? [],
      'timestamp': FieldValue.serverTimestamp(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Document "${doc.title}" dupliqué dans le dossier cible.')));
  } catch (e) {
    debugPrint("Erreur duplication : $e");
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de la duplication du document: $e")));
  }
}

  Uint8List _updateDocxPlaceholders(
      Uint8List docxBytes, Map<String, String> folderMapping, List<String> linkSelections) {
    debugPrint("=== _updateDocxPlaceholders (DocumentPage) ===");
    debugPrint("folderMapping utilisé : $folderMapping");
    debugPrint("linkSelections : $linkSelections");
    Archive archive = ZipDecoder().decodeBytes(docxBytes);
    Archive newArchive = Archive();
    for (var file in archive.files) {
      if (file.name == "word/document.xml") {
        String xmlStr = utf8.decode(file.content as List<int>);
        XmlDocument xmlDoc = XmlDocument.parse(xmlStr);
        var paragraphs = xmlDoc.findAllElements('w:p').toList();
        debugPrint("Nombre de paragraphes trouvés : ${paragraphs.length}");
        for (var paragraph in paragraphs) {
          var indexAttr = paragraph.getAttribute('data-docx-index');
          if (indexAttr != null) {
            int index = int.tryParse(indexAttr) ?? -1;
            if (index >= 0 && index < linkSelections.length) {
              String selectedLink = linkSelections[index].toLowerCase();
              debugPrint("Traitement paragraphe #$index avec lien : '$selectedLink'");
              if (selectedLink != "aucun") {
                String? mappingValue = folderMapping[selectedLink];
                if (mappingValue != null && mappingValue.isNotEmpty) {
                  var textNodes = paragraph.findElements('w:t').toList();
                  if (textNodes.isNotEmpty) {
                    debugPrint("Mise à jour paragraphe #$index avec '$mappingValue'");
                    textNodes.first.children
                      ..clear()
                      ..add(XmlText(mappingValue));
                  } else {
                    debugPrint("Aucun <w:t> trouvé dans paragraphe #$index");
                  }
                } else {
                  debugPrint("Valeur vide ou absente pour '$selectedLink' dans folderMapping");
                }
              }
            } else {
              debugPrint("Index $index hors limites (taille linkSelections: ${linkSelections.length})");
            }
          }
        }
        String newXmlStr = xmlDoc.toXmlString();
        List<int> newContent = utf8.encode(newXmlStr);
        newArchive.addFile(ArchiveFile(file.name, newContent.length, newContent));
      } else {
        newArchive.addFile(file);
      }
    }
    Uint8List result = Uint8List.fromList(ZipEncoder().encode(newArchive)!);
    debugPrint("DOCX mis à jour, taille : ${result.length} octets");
    return result;
  }

  Future<void> _deleteDocument(DocumentModel document) async {
    try {
      final storageRef = FirebaseStorage.instance.refFromURL(document.url);
      await storageRef.delete();
      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('documents')
          .doc(document.id)
          .delete();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document supprimé avec succès')));
      if (_selectedFolder != null) {
        _fetchDocuments(_selectedFolder!.id);
      } else {
        _fetchExampleDocuments();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la suppression du document: $e')));
      debugPrint("Erreur _deleteDocument: $e");
    }
  }

  Future<void> _generateDocument(String title, String content) async {
    await _createDocxDocument(title, content);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document généré avec succès')));
  }

  Future<void> _createDocxDocument(String title, String content) async {
    if (!_fontsLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Les polices ne sont pas encore chargées. Veuillez réessayer.')));
      return;
    }
    try {
      debugPrint("Création d'un DOCX via ConvertApi");
      const convertApiUrl =
          'https://v2.convertapi.com/convert/txt/to/docx?Secret=secret_jPYJFfijH2cj3g8h';
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
          'Parameters': {'File': 'document.txt'},
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final docxUrl = data['Files']?[0]?['Url'];
        if (docxUrl != null) {
          final docxResponse = await http.get(Uri.parse(docxUrl));
          if (docxResponse.statusCode == 200) {
            final docxBytes = docxResponse.bodyBytes;
            String folderId = _selectedFolder?.id ?? "example";
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('documents/$folderId/$title.docx');
            await storageRef.putData(docxBytes);
            final downloadURL = await storageRef.getDownloadURL();
            await _firestore
                .collection('workspaces')
                .doc(workspaceId)
                .collection('documents')
                .add({
              'title': title,
              'type': 'docx',
              'url': downloadURL,
              'folderId': folderId,
              'linkMapping': [],
              'timestamp': FieldValue.serverTimestamp(),
            });
            if (_selectedFolder != null) {
              _fetchDocuments(_selectedFolder!.id);
            }
            debugPrint("Document DOCX créé et uploadé: $downloadURL");
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la création du document DOCX')));
      debugPrint("Erreur _createDocxDocument: $e");
    }
  }

  Future<void> _downloadFile(String url, String fileName, String type) async {
    try {
      final downloadUrl = "$url?ts=${DateTime.now().millisecondsSinceEpoch}";
      debugPrint("Téléchargement de $fileName => $downloadUrl");
      final anchor = html.AnchorElement(href: downloadUrl)
        ..setAttribute("download", '$fileName.$type')
        ..click();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fichier téléchargé avec succès')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors du téléchargement du fichier')));
      debugPrint("Erreur _downloadFile: $e");
    }
  }

  Future<void> _downloadFolder(Folder folder) async {
    setState(() {
      _downloadingFolders.add(folder.id);
    });
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('documents')
          .where('folderId', isEqualTo: folder.id)
          .get();
      QuerySnapshot contactSnapshot = await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('contacts')
          .where('folderId', isEqualTo: folder.id)
          .get();
      if (snapshot.docs.isEmpty && contactSnapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Le dossier est vide. Aucun fichier à télécharger.')));
        return;
      }
      Archive archive = Archive();
      for (var doc in snapshot.docs) {
        String url = doc['url'] ?? '';
        String title = doc['title'] ?? 'Sans titre';
        String type = doc['type'] ?? 'pdf';
        if (url.isEmpty) continue;
        http.Response response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          List<int> bytes = response.bodyBytes;
          String fName = '$title.${type.toLowerCase()}';
          archive.addFile(ArchiveFile(fName, bytes.length, bytes));
        }
      }
      for (var contactDoc in contactSnapshot.docs) {
        final contact = Contact.fromFirestore(contactDoc);
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
        String fName = '${contact.firstName}_${contact.lastName}.json';
        archive.addFile(ArchiveFile(fName, contactJson.length, utf8.encode(contactJson)));
      }
      List<int> zipData = ZipEncoder().encode(archive)!;
      Uint8List zipBytes = Uint8List.fromList(zipData);
      final blob = html.Blob([zipBytes], 'application/zip');
      final urlObject = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: urlObject)
        ..setAttribute("download", '${folder.name}.zip')
        ..click();
      html.Url.revokeObjectUrl(urlObject);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dossier "${folder.name}" téléchargé avec succès.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors du téléchargement du dossier.')));
      debugPrint("Erreur _downloadFolder: $e");
    } finally {
      setState(() {
        _downloadingFolders.remove(folder.id);
      });
    }
  }

  Future<void> _importDocument() async {
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
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erreur lors de la lecture du fichier.')));
          return;
        }
        String fileType = fileName.split('.').last.toLowerCase();
        if (fileType != 'pdf' && fileType != 'txt' && fileType != 'docx') {
          fileType = 'other';
        }
        String folderId = _selectedFolder?.id ?? "example";
        if (fileType == 'docx') {
          Map<String, String> mappingToUse = _selectedFolder?.folderMapping ?? _globalMapping;
          debugPrint("Importation DOCX avec mapping: $mappingToUse");
          final resultMap = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DocxEditorPage(
                docxBytes: fileBytes!,
                chatGptApiKey: _chatGptApiKey,
                returnModifiedBytes: true,
                customMapping: mappingToUse,
                documentId: "new_document",
                workspaceId: workspaceId,
              ),
            ),
          );
          if (resultMap != null &&
              resultMap is Map &&
              resultMap["docxBytes"] != null &&
              resultMap["docxBytes"] is Uint8List &&
              resultMap["linkMapping"] != null &&
              resultMap["linkMapping"] is List<String>) {
            final modifiedBytes = resultMap["docxBytes"] as Uint8List;
            final linkMapping = resultMap["linkMapping"] as List<String>;
            final originalStorageRef = FirebaseStorage.instance
                .ref()
                .child('documents/$folderId/original_$fileName');
            await originalStorageRef.putData(fileBytes);
            final originalUrl = await originalStorageRef.getDownloadURL();

            final modifiedStorageRef = FirebaseStorage.instance
                .ref()
                .child('documents/$folderId/$fileName');
            await modifiedStorageRef.putData(modifiedBytes);
            final fileUrl = await modifiedStorageRef.getDownloadURL();

            await _firestore
                .collection('workspaces')
                .doc(workspaceId)
                .collection('documents')
                .add({
              'title': fileName,
              'type': fileType,
              'url': fileUrl,
              'originalUrl': originalUrl,
              'folderId': folderId,
              'linkMapping': linkMapping,
              'timestamp': FieldValue.serverTimestamp(),
            });
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Document importé et modifié avec succès')));
            debugPrint("Document DOCX importé: $fileUrl");
          }
        } else {
          try {
            final storageRef = FirebaseStorage.instance
                .ref()
                .child('documents/$folderId/$fileName');
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
              'folderId': folderId,
              'timestamp': FieldValue.serverTimestamp(),
            });
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Document importé avec succès')));
            debugPrint("Document non-DOCX importé: $fileUrl");
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Erreur lors de l\'importation du document')));
            debugPrint("Erreur _importDocument (non-DOCX): $e");
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aucun fichier sélectionné.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'importation du document: $e')));
      debugPrint("Erreur _importDocument: $e");
    }
  }

  Future<void> _showExampleFromDocxDialog() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
    );
    if (result != null) {
      Uint8List fileBytes = result.files.single.bytes ??
          (result.files.single.path != null
              ? await File(result.files.single.path!).readAsBytes()
              : Uint8List(0));
      if (fileBytes.isEmpty) return;
      try {
        Map<String, String> mappingToUse = _selectedFolder?.folderMapping ?? _globalMapping;
        debugPrint("Exemple DOCX avec mapping: $mappingToUse");
        final resultMap = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DocxEditorPage(
              docxBytes: fileBytes,
              chatGptApiKey: _chatGptApiKey,
              returnModifiedBytes: true,
              customMapping: mappingToUse,
              documentId: "new_document",
              workspaceId: workspaceId,
            ),
          ),
        );
        if (resultMap != null &&
            resultMap is Map &&
            resultMap["docxBytes"] != null &&
            resultMap["docxBytes"] is Uint8List &&
            resultMap["linkMapping"] != null &&
            resultMap["linkMapping"] is List<String>) {
          String folderId = _selectedFolder?.id ?? "example";
          final modifiedBytes = resultMap["docxBytes"] as Uint8List;
          final linkMapping = resultMap["linkMapping"] as List<String>;
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('documents/$folderId/example_modified.docx');
          await storageRef.putData(modifiedBytes);
          final newDownloadURL = await storageRef.getDownloadURL();
          await _firestore
              .collection('workspaces')
              .doc(workspaceId)
              .collection('documents')
              .add({
            'title': 'Example Modified',
            'type': 'docx',
            'url': newDownloadURL,
            'folderId': folderId,
            'linkMapping': linkMapping,
            'timestamp': FieldValue.serverTimestamp(),
          });
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('DOCX exemple modifié et sauvegardé avec succès')));
          if (_selectedFolder != null) {
            _fetchDocuments(_selectedFolder!.id);
          }
          debugPrint("Exemple DOCX modifié: $newDownloadURL");
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur lors de l\'édition du DOCX: $e')));
        debugPrint("Erreur _showExampleFromDocxDialog: $e");
      }
    }
  }

  Future<void> _editDocx(DocumentModel document) async {
    try {
      final urlToLoad = document.url.isNotEmpty ? document.url : (document.originalUrl ?? "");
      debugPrint("Édition du DOCX, chargement URL : $urlToLoad");
      final response = await http.get(Uri.parse(urlToLoad));
      if (response.statusCode == 200) {
        final docxBytes = response.bodyBytes;
        List<String>? savedMapping = document.linkMapping != null ? List<String>.from(document.linkMapping!) : null;
        Map<String, String> mappingToUse = _selectedFolder?.folderMapping ?? _globalMapping;
        debugPrint("Mapping transmis à DocxEditorPage : $mappingToUse");
        debugPrint("linkMapping sauvegardé : $savedMapping");
        final resultMap = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DocxEditorPage(
              docxBytes: docxBytes,
              chatGptApiKey: _chatGptApiKey,
              returnModifiedBytes: true,
              customMapping: mappingToUse,
              savedLinkMapping: savedMapping,
              documentId: document.id,
              workspaceId: workspaceId,
            ),
          ),
        );
        if (resultMap != null &&
            resultMap["docxBytes"] is Uint8List &&
            resultMap["linkMapping"] is List<String>) {
          final modifiedBytes = resultMap["docxBytes"] as Uint8List;
          final linkMapping = resultMap["linkMapping"] as List<String>;
          final storageRef = FirebaseStorage.instance
              .ref()
              .child('documents/${document.folderId}/${document.title}.docx');
          await storageRef.putData(modifiedBytes);
          final newDownloadURL = await storageRef.getDownloadURL();
          debugPrint("DOCX modifié uploadé : $newDownloadURL");
          await _firestore
              .collection('workspaces')
              .doc(workspaceId)
              .collection('documents')
              .doc(document.id)
              .update({
            'url': newDownloadURL,
            'linkMapping': linkMapping,
            'timestamp': FieldValue.serverTimestamp(),
          });
          if (_selectedFolder != null) _fetchDocuments(_selectedFolder!.id);
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('DOCX modifié et mis à jour avec succès')));
        }
      } else {
        throw Exception("Erreur lors du chargement du DOCX : ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Erreur édition DOCX : $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l\'édition du DOCX: $e')));
    }
  }

  void _listenToActions() {
    debugPrint("Écoute des actions pour userId: $userId");
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
    }, onError: (e) {
      debugPrint("Erreur lors de l'écoute des actions: $e");
    });
  }

  void _handleAction(Map<String, dynamic> actionData) async {
    final action = actionData['action'];
    final data = actionData['data'];
    debugPrint("Action reçue: $action, données: $data");
    switch (action) {
      case 'create_folder_and_add_contact':
        final folderName = data['folderName'];
        final document = data['document'];
        final documentTitle = document['title'];
        final documentContent = document['content'];
        await _createFolder(folderName, []).then((_) {
          if (_folders.isNotEmpty) {
            _createDocxDocument(documentTitle, documentContent);
          }
        });
        break;
      default:
        debugPrint("Action non reconnue: $action");
        break;
    }
  }

  Future<void> _showMappingGlobalDialog() async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            "Modifier Mapping global",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: TextEditingController(text: _globalMapping["date"]),
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: "Date",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).dividerColor?.withOpacity(0.2),
                  ),
                  onChanged: (value) {
                    _globalMapping["date"] = value.trim();
                  },
                ),
                SizedBox(height: 12),
                TextField(
                  controller: TextEditingController(text: _globalMapping["nom du contact"]),
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: "Nom du contact",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).dividerColor?.withOpacity(0.2),
                  ),
                  onChanged: (value) {
                    _globalMapping["nom du contact"] = value.trim();
                  },
                ),
                SizedBox(height: 12),
                TextField(
                  controller: TextEditingController(text: _globalMapping["numéro"]),
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: "Numéro",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).dividerColor?.withOpacity(0.2),
                  ),
                  onChanged: (value) {
                    _globalMapping["numéro"] = value.trim();
                  },
                ),
                SizedBox(height: 12),
                TextField(
                  controller: TextEditingController(text: _globalMapping["adresse"]),
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: "Adresse",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).dividerColor?.withOpacity(0.2),
                  ),
                  onChanged: (value) {
                    _globalMapping["adresse"] = value.trim();
                  },
                ),
                SizedBox(height: 12),
                TextField(
                  controller: TextEditingController(text: _globalMapping["email"]),
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: "Email",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).dividerColor?.withOpacity(0.2),
                  ),
                  onChanged: (value) {
                    _globalMapping["email"] = value.trim();
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Annuler", style: Theme.of(context).textTheme.bodyMedium),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _saveGlobalMapping();
              },
              child: Text(
                "Enregistrer",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFolderMappingDialog() async {
    if (_selectedFolder == null) {
      debugPrint("Aucun dossier sélectionné pour modifier le mapping.");
      return;
    }

    Map<String, String> folderMapping = Map.from(_selectedFolder!.folderMapping ?? {
      "prix unitaire ht": "",
      "% tva": "",
      "total tva": "",
      "total ttc": "",
    });
    debugPrint("Mapping initial du dossier '${_selectedFolder!.name}' : $folderMapping");

    TextEditingController unitPriceController = TextEditingController(text: folderMapping["prix unitaire ht"] ?? "");
    TextEditingController tvaController = TextEditingController(text: folderMapping["% tva"] ?? "");
    TextEditingController totalTVAController = TextEditingController(text: folderMapping["total tva"] ?? "");
    TextEditingController totalTTCController = TextEditingController(text: folderMapping["total ttc"] ?? "");

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            "Mapping du dossier '${_selectedFolder!.name}'",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: unitPriceController,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: "Prix unitaire HT",
                    hintText: "Entrez le prix unitaire hors taxes",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).dividerColor?.withOpacity(0.2),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tvaController,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: "% TVA",
                    hintText: "Entrez le pourcentage de TVA (ex. 20)",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).dividerColor?.withOpacity(0.2),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: totalTVAController,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: "Total TVA",
                    hintText: "Entrez le montant total de la TVA",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).dividerColor?.withOpacity(0.2),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: totalTTCController,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    labelText: "Total TTC",
                    hintText: "Entrez le montant total toutes taxes comprises",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).dividerColor?.withOpacity(0.2),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                debugPrint("Modification du mapping annulée.");
                Navigator.pop(context);
              },
              child: Text("Annuler", style: Theme.of(context).textTheme.bodyMedium),
            ),
            ElevatedButton(
              onPressed: () async {
                Map<String, String> newMapping = {
                  "prix unitaire ht": unitPriceController.text.trim(),
                  "% tva": tvaController.text.trim(),
                  "total tva": totalTVAController.text.trim(),
                  "total ttc": totalTTCController.text.trim(),
                };
                debugPrint("Nouveau mapping à sauvegarder : $newMapping");
                try {
                  await _firestore
                      .collection('workspaces')
                      .doc(workspaceId)
                      .collection('folders')
                      .doc(_selectedFolder!.id)
                      .update({'folderMapping': newMapping});
                  debugPrint("Mapping sauvegardé dans Firestore pour le dossier ${_selectedFolder!.id}");
                  setState(() {
                    _selectedFolder = Folder(
                      id: _selectedFolder!.id,
                      name: _selectedFolder!.name,
                      timestamp: _selectedFolder!.timestamp,
                      folderMapping: newMapping,
                    );
                  });
                  debugPrint("État local mis à jour : ${_selectedFolder!.folderMapping}");
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mapping du dossier sauvegardé avec succès')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur lors de la sauvegarde : $e')));
                  debugPrint("Erreur _showFolderMappingDialog: $e");
                }
                Navigator.pop(context);
              },
              child: Text(
                "Enregistrer",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    unitPriceController.dispose();
    tvaController.dispose();
    totalTVAController.dispose();
    totalTTCController.dispose();
  }

  Widget _buildContactList(List<Contact> contacts) {
    if (contacts.isEmpty) {
      return Text(
        'Aucun contact dans ce dossier.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final contact = contacts[index];
        return Card(
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          color: Theme.of(context).cardColor, // Couleur de la carte selon le thème
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor, // Couleur principale du thème
              child: Text(
                contact.firstName.isNotEmpty ? contact.firstName[0].toUpperCase() : '?',
                style: TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              '${contact.firstName} ${contact.lastName}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contact.email.isNotEmpty)
                  Text('Email: ${contact.email}', style: Theme.of(context).textTheme.bodyMedium),
                if (contact.phone.isNotEmpty)
                  Text('Téléphone: ${contact.phone}', style: Theme.of(context).textTheme.bodyMedium),
                if (contact.company.isNotEmpty)
                  Text('Entreprise: ${contact.company}', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete),
                  color: Colors.redAccent, // Couleur statique pour la suppression
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: Theme.of(context).cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: Text(
                          'Confirmer la suppression',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        content: Text(
                          'Êtes-vous sûr de vouloir supprimer ce contact?',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text('Annuler', style: Theme.of(context).textTheme.bodyMedium),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _deleteContact(contact.id);
                            },
                            child: Text(
                              'Supprimer',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  color: Theme.of(context).iconTheme.color, // Icône selon le thème
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

  Future<void> _deleteContact(String contactId) async {
    try {
      await _firestore
          .collection('workspaces')
          .doc(workspaceId)
          .collection('contacts')
          .doc(contactId)
          .delete();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact supprimé avec succès')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la suppression du contact')));
      debugPrint("Erreur _deleteContact: $e");
    }
  }

  void _showContactDetails(Contact contact) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor, // Couleur de fond selon le thème
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '${contact.firstName} ${contact.lastName}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (contact.email.isNotEmpty)
                  Text('Email: ${contact.email}', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                if (contact.phone.isNotEmpty)
                  Text('Téléphone: ${contact.phone}', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                if (contact.address.isNotEmpty)
                  Text('Adresse: ${contact.address}', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                if (contact.company.isNotEmpty)
                  Text('Entreprise: ${contact.company}', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                if (contact.externalInfo.isNotEmpty)
                  Text('Informations Externes: ${contact.externalInfo}', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                if (contact.folderId.isNotEmpty)
                  FutureBuilder<DocumentSnapshot>(
                    future: _firestore.collection('workspaces').doc(workspaceId).collection('folders').doc(contact.folderId).get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Text('Dossier: Chargement...', style: Theme.of(context).textTheme.bodyMedium);
                      }
                      if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                        return Text('Dossier: Inconnu', style: Theme.of(context).textTheme.bodyMedium);
                      }
                      final folder = Folder.fromFirestore(snapshot.data!);
                      return Text('Dossier: ${folder.name}', style: Theme.of(context).textTheme.bodyMedium);
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text('Fermer', style: Theme.of(context).textTheme.bodyMedium),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFolderList() {
    if (_folders.isEmpty) {
      return Center(
        child: Text(
          'Aucun dossier trouvé.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return DragTarget<DocumentModel>(
          onAccept: (docModel) async {
            await _duplicateDocument(docModel, folder.id);
          },
          builder: (context, candidateData, rejectedData) {
            return Card(
              elevation: 3,
              margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
              color: Theme.of(context).cardColor, // Couleur de la carte selon le thème
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                title: Text(
                  folder.name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Créé le: ${DateFormat.yMMMMd().add_jm().format(folder.timestamp)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download),
                      color: Theme.of(context).iconTheme.color, // Icône selon le thème
                      onPressed: () {
                        _downloadFolder(folder);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      color: Colors.redAccent, // Couleur statique pour la suppression
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: Theme.of(context).cardColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: Text(
                              'Confirmer la suppression',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            content: Text(
                              'Êtes-vous sûr de vouloir supprimer ce dossier?',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: Text('Annuler', style: Theme.of(context).textTheme.bodyMedium),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _deleteFolder(folder.id);
                                },
                                child: Text(
                                  'Supprimer',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.redAccent),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                selected: _selectedFolder?.id == folder.id,
                selectedTileColor: Theme.of(context).dividerColor?.withOpacity(0.2), // Couleur sélectionnée selon le thème
                onTap: () {
                  setState(() {
                    _selectedFolder = folder;
                    _selectedFolderId = folder.id;
                    debugPrint("Dossier sélectionné: ${_selectedFolder!.name}");
                  });
                  _fetchDocuments(folder.id);
                  _fetchContacts(folder.id);
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExampleDocuments() {
    if (_exampleDocuments.isEmpty) {
      return Center(
        child: Text(
          'Aucun document exemple.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _exampleDocuments.length,
      itemBuilder: (context, index) {
        final document = _exampleDocuments[index];
        return Draggable<DocumentModel>(
          data: document,
          feedback: Material(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              child: Card(
                color: Theme.of(context).primaryColor.withOpacity(0.2), // Feedback selon le thème
                child: ListTile(
                  title: Text(
                    document.title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.5,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              child: Card(
                color: Theme.of(context).cardColor, // Couleur de la carte selon le thème
                child: ListTile(
                  title: Text(
                    document.title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
          child: Card(
            elevation: 3,
            margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
            color: Theme.of(context).cardColor, // Couleur de la carte selon le thème
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
              leading: Icon(
                _getDocumentIcon(document.type),
                color: _getDocumentColor(document.type),
                size: 28,
              ),
              title: Text(
                document.title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Exemple - Type: ${document.type.toUpperCase()}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (document.type.toLowerCase() == 'docx')
                    IconButton(
                      icon: const Icon(Icons.edit),
                      color: Theme.of(context).iconTheme.color, // Icône selon le thème
                      onPressed: () {
                        _editDocx(document);
                      },
                      tooltip: 'Éditer le DOCX',
                    ),
                  IconButton(
                    icon: const Icon(Icons.download),
                    color: Theme.of(context).iconTheme.color, // Icône selon le thème
                    onPressed: () {
                      _downloadFile(document.url, document.title, document.type);
                    },
                    tooltip: 'Télécharger',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    color: Colors.redAccent, // Couleur statique pour la suppression
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: Theme.of(context).cardColor,
                          title: Text("Confirmer la suppression", style: Theme.of(context).textTheme.titleLarge),
                          content: Text("Êtes-vous sûr de vouloir supprimer ce document ?", style: Theme.of(context).textTheme.bodyMedium),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text("Annuler", style: Theme.of(context).textTheme.bodyMedium),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _deleteDocument(document);
                              },
                              child: Text(
                                "Supprimer",
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.redAccent),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    tooltip: "Supprimer le document",
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectedFolderContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dossier: ${_selectedFolder!.name}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Documents',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 5),
              Expanded(
                flex: 2,
                child: _documents.isNotEmpty
                    ? ListView.builder(
                        shrinkWrap: true,
                        itemCount: _documents.length,
                        itemBuilder: (context, index) {
                          final document = _documents[index];
                          return Card(
                            elevation: 3,
                            margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
                            color: Theme.of(context).cardColor, // Couleur de la carte selon le thème
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                              leading: Icon(
                                _getDocumentIcon(document.type),
                                color: _getDocumentColor(document.type),
                                size: 28,
                              ),
                              title: Text(
                                document.title,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Type: ${document.type.toUpperCase()}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (document.type.toLowerCase() == 'docx')
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      color: Theme.of(context).iconTheme.color, // Icône selon le thème
                                      onPressed: () {
                                        _editDocx(document);
                                      },
                                      tooltip: 'Éditer le DOCX',
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.download),
                                    color: Theme.of(context).iconTheme.color, // Icône selon le thème
                                    onPressed: () {
                                      _downloadFile(document.url, document.title, document.type);
                                    },
                                    tooltip: 'Télécharger',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    color: Colors.redAccent, // Couleur statique pour la suppression
                                    onPressed: () {
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          backgroundColor: Theme.of(context).cardColor,
                                          title: Text("Confirmer la suppression", style: Theme.of(context).textTheme.titleLarge),
                                          content: Text(
                                            "Êtes-vous sûr de vouloir supprimer ce document ?",
                                            style: Theme.of(context).textTheme.bodyMedium,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(context).pop(),
                                              child: Text("Annuler", style: Theme.of(context).textTheme.bodyMedium),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                Navigator.of(context).pop();
                                                _deleteDocument(document);
                                              },
                                              child: Text(
                                                "Supprimer",
                                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.redAccent),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                    tooltip: "Supprimer le document",
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : Text(
                        'Aucun document dans ce dossier.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                      ),
              ),
              const SizedBox(height: 20),
              Text(
                'Contacts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 5),
              Expanded(
                flex: 1,
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
        return Theme.of(context).iconTheme.color ?? Colors.grey; // Icône selon le thème
      case 'docx':
        return Colors.blueGrey; // Peut être adapté au thème si souhaité
      case 'txt':
        return Theme.of(context).iconTheme.color ?? Colors.grey; // Icône selon le thème
      default:
        return Theme.of(context).iconTheme.color ?? Colors.black; // Icône selon le thème
    }
  }

  void _showCreateDocumentDialog() {
    if (_selectedFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Veuillez sélectionner un dossier avant de créer un document.')));
      return;
    }
    String documentTitle = '';
    String documentContent = '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor, // Couleur de fond selon le thème
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Créer un Nouveau Document',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Titre du document',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Theme.of(context).dividerColor?.withOpacity(0.2),
                ),
                onChanged: (value) {
                  documentTitle = value;
                },
              ),
              const SizedBox(height: 20),
              TextField(
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Contenu du document',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Theme.of(context).dividerColor?.withOpacity(0.2),
                ),
                maxLines: 5,
                onChanged: (value) {
                  documentContent = value;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Annuler', style: Theme.of(context).textTheme.bodyMedium),
          ),
          ElevatedButton(
            onPressed: () {
              if (documentTitle.trim().isNotEmpty && documentContent.trim().isNotEmpty) {
                _generateDocument(documentTitle.trim(), documentContent.trim());
                Navigator.of(context).pop();
              }
            },
            child: Text(
              'Créer',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showImportDocumentDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor, // Couleur de fond selon le thème
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Importer un Document',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Text(
          'Sélectionnez un fichier à importer',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Annuler', style: Theme.of(context).textTheme.bodyMedium),
          ),
          ElevatedButton(
            onPressed: () {
              _importDocument();
              Navigator.of(context).pop();
            },
            child: Text(
              'Importer',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog() {
    String folderName = '';
    List<String> selectedContactIds = [];
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor, // Couleur de fond selon le thème
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Créer un Dossier',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Nom du dossier',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).dividerColor?.withOpacity(0.2),
                  ),
                  onChanged: (value) {
                    folderName = value;
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Associer des Contacts (Optionnel)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _availableContacts.isNotEmpty
                      ? ListView.builder(
                          itemCount: _availableContacts.length,
                          itemBuilder: (context, index) {
                            final contact = _availableContacts[index];
                            return CheckboxListTile(
                              activeColor: Theme.of(context).primaryColor, // Couleur principale du thème
                              title: Text(
                                '${contact.firstName} ${contact.lastName}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
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
                      : Text(
                          'Aucun contact disponible.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Annuler', style: Theme.of(context).textTheme.bodyMedium),
            ),
            ElevatedButton(
              onPressed: () {
                if (folderName.trim().isNotEmpty) {
                  _createFolder(folderName.trim(), selectedContactIds);
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Veuillez entrer un nom de dossier')));
                }
              },
              child: Text(
                'Créer',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Gestion des Documents',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
        ),
        backgroundColor: Theme.of(context).primaryColor, // Couleur principale du thème
        iconTheme: Theme.of(context).iconTheme, // Icônes selon le thème
        elevation: 0,
        actions: [
          if (_selectedFolder != null)
            IconButton(
              icon: const Icon(Icons.settings_applications),
              tooltip: 'Modifier mapping dossier',
              onPressed: _showFolderMappingDialog,
            ),
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            tooltip: 'Créer un dossier',
            onPressed: _showCreateFolderDialog,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'create') {
                _showCreateDocumentDialog();
              } else if (value == 'import') {
                _showImportDocumentDialog();
              } else if (value == 'example') {
                _showExampleFromDocxDialog();
              } else if (value == 'mapping') {
                _showMappingGlobalDialog();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'create',
                child: Text('Créer Document', style: Theme.of(context).textTheme.bodyMedium),
              ),
              PopupMenuItem<String>(
                value: 'import',
                child: Text('Importer Document', style: Theme.of(context).textTheme.bodyMedium),
              ),
              PopupMenuItem<String>(
                value: 'example',
                child: Text('Exemple DOCX', style: Theme.of(context).textTheme.bodyMedium),
              ),
              PopupMenuItem<String>(
                value: 'mapping',
                child: Text('Modifier Mapping global', style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor, // Fond selon le thème
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Documents Exemples',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    ElevatedButton(
                      onPressed: _showImportDocumentDialog,
                      child: Text(
                        'Importer',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(flex: 1, child: _buildExampleDocuments()),
                const SizedBox(height: 20),
                Text('Dossiers Existants',
                    style: GoogleFonts.roboto(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[900])),
                const SizedBox(height: 10),
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(flex: 1, child: _buildFolderList()),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 2,
                        child: _selectedFolder != null
                            ? _buildSelectedFolderContent()
                            : Center(child: Text('Sélectionnez un dossier pour voir son contenu.',
                                style: GoogleFonts.roboto(fontSize: 16, color: Colors.grey[600]))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateFolderDialog,
        tooltip: 'Créer un dossier',
        backgroundColor: Colors.grey[900],
        child: const Icon(Icons.create_new_folder),
      ),
    );
  }
}
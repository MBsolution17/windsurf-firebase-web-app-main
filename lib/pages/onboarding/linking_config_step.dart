import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../controllers/onboarding_controller.dart';
import 'package:firebase_web_app/pages/docx_editor_page.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'dart:math'; // Pour min/max functions

class LinkingConfigStep extends StatefulWidget {
  const LinkingConfigStep({Key? key}) : super(key: key);

  @override
  _LinkingConfigStepState createState() => _LinkingConfigStepState();
}

class _LinkingConfigStepState extends State<LinkingConfigStep> {
  // Méthode pour détecter si le thème actuel est sombre
  bool _isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  // Variables pour la gestion des étapes
  int _currentStep = 1; // 1 = Création des types, 2 = DocxEditorPage
  
  // Variables pour la configuration des types de liens (étape 1)
  final TextEditingController _optionController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  
  // Variables pour le document (étape 2)
  Uint8List? _selectedDocxBytes;
  String? _selectedDocName;
  bool _isProcessing = false;
  
  // Variable pour stocker le HTML préconverti du document
  String? _preconvertedHtml;
  
  // Variable pour garder une trace des documents déjà convertis
  Map<String, String> _documentSignatureCache = {};

  // Nouvelles variables pour l'historique des documents
  List<DocumentSnapshot> _savedDocuments = [];
  bool _isLoadingDocuments = true;
  
  @override
  void initState() {
    super.initState();
    _loadSavedDocuments();
    // Précharger les signatures des documents dans le cache
    _preloadDocumentSignatures();
  }
  
  // Nouvelle méthode pour précharger les signatures des documents
  Future<void> _preloadDocumentSignatures() async {
    try {
      final onboardingController = Provider.of<OnboardingController>(context, listen: false);
      final workspaceId = onboardingController.workspaceId;
      
      QuerySnapshot docsSnapshot = await FirebaseFirestore.instance
          .collection('workspaces')
          .doc(workspaceId)
          .collection('template_documents')
          .get();
      
      for (var doc in docsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final String base64Data = data['data'] ?? '';
        final String convertedHtml = data['convertedHtml'] ?? '';
        
        if (base64Data.isNotEmpty && convertedHtml.isNotEmpty) {
          try {
            final uri = Uri.parse(base64Data);
            final Uint8List bytes = uri.data!.contentAsBytes();
            
            // Créer une signature simple avec les premiers et derniers octets
            if (bytes.length > 1000) {
              String signature = base64Encode(Uint8List.fromList([
                ...bytes.sublist(0, 500),
                ...bytes.sublist(bytes.length - 500)
              ]));
              
              _documentSignatureCache[signature] = convertedHtml;
              debugPrint("Signature préchargée pour document: ${data['name']}");
            }
          } catch (e) {
            debugPrint("Erreur lors du préchargement de la signature: $e");
          }
        }
      }
      
      debugPrint("Préchargement terminé. ${_documentSignatureCache.length} signatures en cache.");
    } catch (e) {
      debugPrint("Erreur lors du préchargement des signatures: $e");
    }
  }
  
  // Méthode pour charger les documents sauvegardés
  Future<void> _loadSavedDocuments() async {
    setState(() {
      _isLoadingDocuments = true;
    });
    
    try {
      final onboardingController = Provider.of<OnboardingController>(context, listen: false);
      final workspaceId = onboardingController.workspaceId;
      
      // Récupérer les documents sauvegardés pour ce workspace
      QuerySnapshot docsSnapshot = await FirebaseFirestore.instance
          .collection('workspaces')
          .doc(workspaceId)
          .collection('template_documents')
          .orderBy('createdAt', descending: true)
          .get();
      
      setState(() {
        _savedDocuments = docsSnapshot.docs;
        _isLoadingDocuments = false;
      });
      
      debugPrint("Documents chargés: ${_savedDocuments.length}");
    } catch (e) {
      debugPrint("Erreur lors du chargement des documents: $e");
      setState(() {
        _isLoadingDocuments = false;
      });
    }
  }
  
  // Méthode pour convertir le DOCX en HTML via ConvertAPI
  Future<String> _convertDocxToHtml(Uint8List docxBytes) async {
    // Vérifier d'abord si un document similaire existe déjà dans le cache
    String? cachedHtml = _findSimilarDocumentHtml(docxBytes);
    if (cachedHtml != null) {
      debugPrint("Document similaire trouvé dans le cache, réutilisation du HTML");
      return cachedHtml;
    }
    
    // Si aucun document similaire, procéder à la conversion
    debugPrint("Aucun document similaire trouvé, conversion via ConvertAPI");
    const convertApiSecret = "secret_enu727JZ2re3tMCP";
    final url = "https://v2.convertapi.com/convert/docx/to/html?Secret=$convertApiSecret";
    debugPrint("Préparation de la requête multipart pour ConvertAPI...");
    var request = http.MultipartRequest("POST", Uri.parse(url));
    request.fields["Parameters"] = jsonEncode({});
    request.files.add(http.MultipartFile.fromBytes(
      "File",
      docxBytes,
      filename: "document.docx",
      contentType: MediaType(
        'application',
        'vnd.openxmlformats-officedocument.wordprocessingml.document',
      ),
    ));
    
    debugPrint("Envoi de la requête multipart à ConvertAPI...");
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    debugPrint("Code HTTP de ConvertAPI: ${response.statusCode}");
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final fileData = data["Files"]?[0]?["FileData"];
      debugPrint("FileData reçu: ${fileData != null ? "Non null" : "null"}");
      if (fileData == null) {
        throw Exception("Erreur de conversion : FileData introuvable.");
      }
      final decodedBytes = base64Decode(fileData);
      final htmlContent = utf8.decode(decodedBytes);
      
      // Ajouter au cache
      _addToSignatureCache(docxBytes, htmlContent);
      
      return htmlContent;
    } else {
      throw Exception("Erreur lors de la conversion DOCX → HTML: ${response.body}");
    }
  }
  
  // Nouvelle méthode pour ajouter un document au cache de signatures
  void _addToSignatureCache(Uint8List docxBytes, String htmlContent) {
    try {
      // Créer une signature pour ce document
      if (docxBytes.length > 1000) {
        String signature = base64Encode(Uint8List.fromList([
          ...docxBytes.sublist(0, 500),
          ...docxBytes.sublist(docxBytes.length - 500)
        ]));
        
        _documentSignatureCache[signature] = htmlContent;
        debugPrint("Document ajouté au cache de signatures");
      }
    } catch (e) {
      debugPrint("Erreur lors de l'ajout au cache: $e");
    }
  }
  
  // Nouvelle méthode pour trouver un document similaire dans le cache
  String? _findSimilarDocumentHtml(Uint8List docxBytes) {
    try {
      if (docxBytes.length > 1000 && _documentSignatureCache.isNotEmpty) {
        // Créer une signature pour ce document
        String signature = base64Encode(Uint8List.fromList([
          ...docxBytes.sublist(0, 500),
          ...docxBytes.sublist(docxBytes.length - 500)
        ]));
        
        // Vérifier si cette signature exacte existe
        if (_documentSignatureCache.containsKey(signature)) {
          debugPrint("Signature exacte trouvée dans le cache");
          return _documentSignatureCache[signature];
        }
        
        // Sinon parcourir les signatures existantes pour trouver une similitude
        for (var cachedSignature in _documentSignatureCache.keys) {
          // Comparer les premiers 100 caractères de la signature
          if (cachedSignature.length > 100 && signature.length > 100) {
            if (cachedSignature.substring(0, 100) == signature.substring(0, 100)) {
              debugPrint("Document similaire trouvé via signature partielle");
              return _documentSignatureCache[cachedSignature];
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Erreur lors de la recherche de document similaire: $e");
    }
    return null;
  }
  
  // Nouvelle méthode pour sauvegarder un document template avec son HTML converti
  Future<void> _saveDocumentTemplate(Uint8List docxBytes, String fileName) async {
    setState(() {
      _isProcessing = true;
    });
    
    final onboardingController = Provider.of<OnboardingController>(context, listen: false);
    final workspaceId = onboardingController.workspaceId;
    
    try {
      // Vérifier si on a déjà un document similaire
      String? existingHtml = _findSimilarDocumentHtml(docxBytes);
      String htmlContent;
      
      if (existingHtml != null) {
        debugPrint("Utilisation du HTML d'un document similaire");
        htmlContent = existingHtml;
      } else {
        // Convertir le document DOCX en HTML (utiliser des crédits une seule fois)
        debugPrint("Conversion via ConvertAPI");
        htmlContent = await _convertDocxToHtml(docxBytes);
      }
      
      _preconvertedHtml = htmlContent; // Stocke temporairement le HTML pour l'utiliser immédiatement
      
      // Référence pour stocker le document dans Firestore
      DocumentReference docRef = FirebaseFirestore.instance
          .collection('workspaces')
          .doc(workspaceId)
          .collection('template_documents')
          .doc();
      
      // Stocker le document et le HTML converti
      String base64Docx = Uri.dataFromBytes(docxBytes, mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document').toString();
      
      // Enregistrer les métadonnées du document et le HTML converti
      await docRef.set({
        'name': fileName,
        'data': base64Docx,
        'convertedHtml': htmlContent, // Stocker le HTML converti
        'createdAt': FieldValue.serverTimestamp(),
        'conversionDate': FieldValue.serverTimestamp(), // Date de la conversion
      });
      
      debugPrint("Document template et HTML sauvegardés avec succès");
      
      // Recharger la liste des documents
      await _loadSavedDocuments();
      
    } catch (e) {
      debugPrint("Erreur lors de la sauvegarde du template: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erreur lors de la sauvegarde du document: $e", 
            style: TextStyle(color: Theme.of(context).colorScheme.onError)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      
      // En cas d'erreur, réinitialiser le HTML préconverti
      _preconvertedHtml = null;
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
  
  // Méthode modifiée pour ouvrir un document existant avec son HTML préconverti
  Future<void> _openSavedDocument(DocumentSnapshot doc) async {
    setState(() {
      _isProcessing = true;
    });
    
    try {
      // Récupérer les données du document
      final data = doc.data() as Map<String, dynamic>;
      final String docName = data['name'] ?? 'Document sans nom';
      final String base64Data = data['data'] ?? '';
      final String convertedHtml = data['convertedHtml'] ?? '';
      
      if (base64Data.isNotEmpty) {
        // Convertir les données base64 en Uint8List
        final uri = Uri.parse(base64Data);
        final Uint8List docxBytes = uri.data!.contentAsBytes();
        
        // S'assurer que le HTML converti existe vraiment
        if (convertedHtml.isEmpty) {
          debugPrint("ATTENTION: HTML préconverti manquant, tentative de le retrouver dans le cache");
          String? cachedHtml = _findSimilarDocumentHtml(docxBytes);
          
          if (cachedHtml != null) {
            debugPrint("HTML trouvé dans le cache pour un document similaire");
            _preconvertedHtml = cachedHtml;
            
            // Mise à jour du document avec le HTML retrouvé
            await doc.reference.update({
              'convertedHtml': cachedHtml,
              'conversionDate': FieldValue.serverTimestamp(),
            });
          } else {
            debugPrint("Aucun HTML en cache, une conversion sera nécessaire");
            _preconvertedHtml = null;
          }
        } else {
          _preconvertedHtml = convertedHtml;
          debugPrint("HTML préconverti trouvé, longueur: ${convertedHtml.length}");
        }
        
        setState(() {
          _selectedDocxBytes = docxBytes;
          _selectedDocName = docName;
          _currentStep = 2; // Passer à l'étape DocxEditor
        });
        
        debugPrint("Document chargé${_preconvertedHtml != null ? ' avec HTML préconverti' : ' sans HTML préconverti'}");
      } else {
        throw Exception("Document vide ou corrompu");
      }
    } catch (e) {
      debugPrint("Erreur lors de l'ouverture du document: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erreur lors de l'ouverture du document: $e", 
            style: TextStyle(color: Theme.of(context).colorScheme.onError)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
  
  @override
  void dispose() {
    _optionController.dispose();
    _valueController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer<OnboardingController>(
      builder: (context, controller, _) {
        // Récupération des données existantes
        final mappingOptions = List<String>.from(controller.onboardingData['linking_config']?['mappingOptions'] ?? [
          'Aucun',
          'Date',
          'Nom du contact',
          'Numéro',
          'Adresse',
          'Email',
          'Prix unitaire HT',
          '% TVA',
          'Total TVA',
          'Total TTC',
        ]);
        
        final dbMapping = Map<String, String>.from(controller.onboardingData['linking_config']?['dbMapping'] ?? {
          'date': '',
          'nom du contact': '',
          'numéro': '',
          'adresse': '',
          'email': '',
          'prix unitaire ht': '',
          '% tva': '',
          'total tva': '',
          'total ttc': '',
        });

        // Différentes structures d'appBar et de corps selon l'étape courante
        final appBar = _currentStep == 1 
            ? AppBar(
                title: const Text('Configuration des types de liens'),
                elevation: 0,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.save),
                    tooltip: "Sauvegarder les types",
                    onPressed: () async {
                      await controller.saveLinkingConfigToFirestore(controller.workspaceId);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Types de liens sauvegardés', 
                            style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                  ),
                ],
              )
            : null; // Pas d'AppBar en étape 2 pour maximiser l'espace
        
        // Corps principal de l'interface
        Widget body;
        
        // En étape 1 : Interface de configuration des types
        if (_currentStep == 1) {
          body = Column(
            children: [
              // Indicateur d'étape
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildStepIndicator(mappingOptions),
              ),
              
              // Contenu de l'étape 1
              Expanded(
                child: _buildStep1(mappingOptions, dbMapping, controller),
              ),
              
              // Bouton pour passer à l'étape 2
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: mappingOptions.where((opt) => opt != 'Aucun').isEmpty
                        ? null // Désactivé si aucun type configuré
                        : () {
                            setState(() {
                              _currentStep = 2;
                            });
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    child: const Text('Configurer le document'),
                  ),
                ),
              ),
            ],
          );
        } 
        // En étape 2 : Document selector ou DocxEditorPage
        else {
          body = _selectedDocxBytes == null
              ? Stack(
                  children: [
                    // Sélecteur de document (modifié pour inclure l'historique)
                    _buildDocumentSelector(),
                    
                    // Indicateur d'étape (en haut)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: _buildStepIndicator(mappingOptions),
                    ),
                    
                    // Bouton de retour (en haut à gauche)
                    Positioned(
                      top: 70,
                      left: 16,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _currentStep = 1;
                          });
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Retour aux types de liens'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          foregroundColor: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                )
              : _buildDocxEditorPageWrapper(controller, dbMapping);
        }
        
        return Scaffold(
          appBar: appBar,
          body: SafeArea(child: body),
        );
      },
    );
  }
  
  // Widget modifié pour DocxEditorPage qui passe aussi le HTML préconverti
  Widget _buildDocxEditorPageWrapper(OnboardingController controller, Map<String, String> dbMapping) {
    return Stack(
      children: [
        // DocxEditorPage en plein écran avec le HTML préconverti si disponible
        Positioned.fill(
          child: DocxEditorPage(
            docxBytes: _selectedDocxBytes!,
            chatGptApiKey: 'votre_cle_api',
            workspaceId: controller.workspaceId,
            documentId: 'new_document',
            customMapping: Map<String, String>.from(dbMapping),
            returnModifiedBytes: true,
            preconvertedHtml: _preconvertedHtml, // Passer le HTML préconverti
            forceTextUpdate: true, // Forcer la mise à jour des textes
          ),
        ),
        
        // Bouton flottant de retour à l'étape 1
        Positioned(
          top: 16,
          left: 16,
          child: FloatingActionButton.extended(
            onPressed: () {
              setState(() {
                _currentStep = 1;
              });
            },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Retour aux types'),
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
      ],
    );
  }
  
  // Widget pour l'indicateur d'étape
  Widget _buildStepIndicator(List<String> mappingOptions) {
    final hasTypes = mappingOptions.where((option) => option != 'Aucun').isNotEmpty;
    
    return Row(
      children: [
        // Étape 1
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _currentStep = 1;
              });
            },
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: _currentStep == 1
                        ? Theme.of(context).primaryColor
                        : _isDarkMode(context) 
                            ? Theme.of(context).colorScheme.surface.withOpacity(0.3)
                            : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '1',
                      style: TextStyle(
                        color: _currentStep == 1 
                          ? Theme.of(context).colorScheme.onPrimary 
                          : Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Types de liens',
                  style: TextStyle(
                    fontWeight: _currentStep == 1
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (hasTypes)
                  Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 16,
                  ),
              ],
            ),
          ),
        ),
        
        // Ligne de connexion
        Container(
          height: 2,
          color: _isDarkMode(context) ? Colors.grey.shade700 : Colors.grey.shade300,
          width: 60,
        ),
        
        // Étape 2
        Expanded(
          child: GestureDetector(
            onTap: hasTypes ? () {
              setState(() {
                _currentStep = 2;
              });
            } : null,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: _currentStep == 2
                        ? Theme.of(context).primaryColor
                        : _isDarkMode(context) 
                            ? Theme.of(context).colorScheme.surface.withOpacity(0.3)
                            : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '2',
                      style: TextStyle(
                        color: _currentStep == 2 
                          ? Theme.of(context).colorScheme.onPrimary 
                          : Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configuration document',
                  style: TextStyle(
                    fontWeight: _currentStep == 2
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (_selectedDocxBytes != null)
                  Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 16,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  // Construction de l'étape 1 : Création des types de liens
  Widget _buildStep1(
    List<String> mappingOptions,
    Map<String, String> dbMapping,
    OnboardingController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Étape 1: Configuration des types de liens',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Définissez les types de champs personnalisés que vous souhaitez lier à vos documents.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 24),
          
          // Liste des types existants
          Expanded(
            child: mappingOptions.where((option) => option != 'Aucun').isEmpty
                ? Center(
                    child: Text(
                      'Aucun type de lien configuré\nAjoutez un nouveau type ci-dessous',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                    ),
                  )
                : ListView.builder(
                    itemCount: mappingOptions.where((opt) => opt != 'Aucun').length,
                    itemBuilder: (context, index) {
                      final option = mappingOptions.where((opt) => opt != 'Aucun').elementAt(index);
                      final value = dbMapping[option.toLowerCase()] ?? '';
                      return Card(
                        color: Theme.of(context).cardColor,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(option),
                          subtitle: value.isNotEmpty
                              ? Text('Valeur par défaut : $value')
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Bouton d'édition
                              IconButton(
                                icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
                                onPressed: () => _showEditDialog(context, option, value, controller),
                              ),
                              // Bouton de suppression
                              IconButton(
                                icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                                onPressed: option == 'Aucun'
                                    ? null  // Désactivé pour "Aucun"
                                    : () => _showDeleteConfirmation(context, option, controller),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          
          // Ajout d'un nouveau type
          const Divider(),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _optionController,
                  decoration: InputDecoration(
                    labelText: 'Ajouter un type de lien',
                    hintText: 'Ex: Référence client, Numéro de commande...',
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)),
                    hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
                onPressed: () {
                  final value = _optionController.text.trim();
                  if (value.isNotEmpty && !mappingOptions.contains(value)) {
                    controller.addLinkingOption(value);
                    _optionController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Type de lien "$value" ajouté',
                          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                        ),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  // Widget pour la sélection d'un document
  Widget _buildDocumentSelector() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 120), // Pour tenir compte des éléments en haut
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Section 1: Documents récemment utilisés
          if (_savedDocuments.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Documents récemment utilisés',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Liste des documents
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: _isDarkMode(context) 
                        ? Colors.grey.shade700 
                        : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _isLoadingDocuments
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _savedDocuments.length,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              color: _isDarkMode(context) 
                                ? Colors.grey.shade800 
                                : Colors.grey.shade300,
                            ),
                            itemBuilder: (context, index) {
                              final doc = _savedDocuments[index];
                              final data = doc.data() as Map<String, dynamic>;
                              final name = data['name'] ?? 'Document sans nom';
                              final hasHtml = data['convertedHtml'] != null && data['convertedHtml'].toString().isNotEmpty;
                              Timestamp? createdAt = data['createdAt'];
                              String dateStr = createdAt != null
                                  ? '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}'
                                  : 'Date inconnue';
                                  
                              return ListTile(
                                leading: Icon(
                                  Icons.description, 
                                  size: 32, 
                                  color: Theme.of(context).colorScheme.primary
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                                ),
                                subtitle: Text(
                                  'Importé le $dateStr${hasHtml ? ' - Préconverti ✓' : ''}',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.open_in_new,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  onPressed: () => _openSavedDocument(doc),
                                ),
                                onTap: () => _openSavedDocument(doc),
                                tileColor: index % 2 == 0 
                                  ? _isDarkMode(context) 
                                      ? Theme.of(context).colorScheme.surface.withOpacity(0.3) 
                                      : Colors.grey[50]
                                  : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            Divider(
              thickness: 1,
              color: _isDarkMode(context) ? Colors.grey.shade800 : Colors.grey.shade300,
            ),
          ],
  
          // Section 2: Importer un nouveau document
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.upload_file,
                  size: 80,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
                const SizedBox(height: 24),
                Text(
                  'Importer un document pour configurer les liens',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Sélectionnez un document DOCX que vous souhaitez utiliser comme modèle',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _pickDocument,
                  icon: _isProcessing 
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.onPrimary
                            ),
                          ),
                        )
                      : const Icon(Icons.file_upload),
                  label: Text(_isProcessing ? 'Traitement...' : 'Choisir un document'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Méthode pour sélectionner un document
  Future<void> _pickDocument() async {
    setState(() {
      _isProcessing = true;
    });
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
        withData: true, // Important pour le web
      );
      
      if (result != null && result.files.single.bytes != null) {
        final bytes = result.files.single.bytes!;
        final filename = result.files.single.name;
        
        // Sauvegarder le document comme template avec conversion HTML
        await _saveDocumentTemplate(bytes, filename);
        
        setState(() {
          _selectedDocxBytes = bytes;
          _selectedDocName = filename;
        });
      }
    } catch (e) {
      print("Erreur lors de la sélection du document: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erreur lors de la sélection du document: $e',
            style: TextStyle(color: Theme.of(context).colorScheme.onError),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
  
  // Dialogue d'édition d'un type existant
  void _showEditDialog(
    BuildContext context,
    String option,
    String value,
    OnboardingController controller,
  ) {
    _valueController.text = value;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).dialogBackgroundColor,
        title: Text(
          'Modifier "$option"',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: TextField(
          controller: _valueController,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            labelText: 'Valeur par défaut',
            border: OutlineInputBorder(),
            labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annuler',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              controller.updateLinkingDefault(option, _valueController.text);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Valeur mise à jour',
                    style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
  
  // Confirmation de suppression
  void _showDeleteConfirmation(
    BuildContext context,
    String option,
    OnboardingController controller,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).dialogBackgroundColor,
        title: Text(
          'Supprimer "$option" ?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Text(
          'Êtes-vous sûr de vouloir supprimer ce type de lien ? Cette action est irréversible.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annuler',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              controller.removeLinkingOption(option);
              Navigator.pop(context);
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Type de lien "$option" supprimé',
                    style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}
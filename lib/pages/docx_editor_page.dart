import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'dart:math'; // Pour min/max functions

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Extension pour capitalisation (utilisée pour mappingOptions)
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}

/// Représente un paragraphe extrait du DOCX.
class ParagraphInfo {
  final XmlElement paragraph;
  final List<XmlElement> textNodes;
  final List<int> originalLengths;
  final String originalText;

  ParagraphInfo({
    required this.paragraph,
    required this.textNodes,
    required this.originalLengths,
    required this.originalText,
  });
}

/// Représente un champ éditable associé à un paragraphe.
class ParagraphField {
  final TextEditingController controller;
  final bool isReserved;

  ParagraphField({
    required this.controller,
    required this.isReserved,
  });
}

class DocxEditorPage extends StatefulWidget {
  final Uint8List docxBytes;
  final String chatGptApiKey;
  final bool returnModifiedBytes;
  final Map<String, String>? customMapping;
  final List<String>? savedLinkMapping;
  final String documentId;
  final String workspaceId;
  final String? preconvertedHtml; // Paramètre pour le HTML préconverti
  final bool forceTextUpdate; // Nouvelle propriété pour forcer la mise à jour des textes

  const DocxEditorPage({
    Key? key,
    required this.docxBytes,
    required this.chatGptApiKey,
    this.returnModifiedBytes = false,
    this.customMapping,
    this.savedLinkMapping,
    required this.documentId,
    required this.workspaceId,
    this.preconvertedHtml,
    this.forceTextUpdate = false, // Faux par défaut
  }) : super(key: key);

  @override
  _DocxEditorPageState createState() => _DocxEditorPageState();
}

class _DocxEditorPageState extends State<DocxEditorPage> {
  bool _isProcessing = false;
  List<ParagraphInfo> _paragraphsInfo = [];
  List<ParagraphField> _paragraphFields = [];
  final List<String> reservedKeywords = ["date:", "client:", "téléphone:", "email:"];

  // Variables pour le cache
  String? _cachedHtml;
  Uint8List? _lastConvertedBytes;
  String _convertApiCacheKey = '';
  bool _documentStructureChanged = true; // Force la première conversion
  int _conversionCount = 0; // Compteur de conversions pour le débogage

  List<String> mappingOptions = [
    "Aucun",
    "Date",
    "Nom du contact",
    "Numéro",
    "Adresse",
    "Email",
    "Prix unitaire HT",
    "% TVA",
    "Total TVA",
    "Total TTC",
  ];

  Map<String, String> _dbMapping = {
    "date": "",
    "nom du contact": "",
    "numéro": "",
    "adresse": "",
    "email": "",
    "prix unitaire ht": "",
    "% tva": "",
    "total tva": "",
    "total ttc": "",
  };

  Future<void> _loadLinkingConfig() async {
    final doc = await FirebaseFirestore.instance.collection('workspaces').doc(widget.workspaceId).get();
    if (doc.exists && doc.data() != null && doc.data()!.containsKey('linking_config')) {
      final config = doc.data()!['linking_config'];
      if (config['mappingOptions'] != null) {
        mappingOptions = List<String>.from(config['mappingOptions']);
      }
      if (config['dbMapping'] != null) {
        _dbMapping = Map<String, String>.from(config['dbMapping']);
      }
    }
  }

  List<String> _selectedLinkings = [];
  Map<String, String> _rels = {};
  Map<String, String> _imagesData = {};
  XmlDocument? _xmlDoc;
  String _headerText = "";
  String _footerText = "";
  String? _currentIFrameId;

  final ValueNotifier<int?> _activeMappingIndexNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<String?> _activeMappingTextNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String> _activeMappingDropdownNotifier = ValueNotifier<String>("Aucun");

  Future<Widget>? _previewWidgetFuture;

  @override
  void initState() {
    super.initState();
    debugPrint("InitState: Initialisation de DocxEditorPage");
    
    // Si un HTML préconverti est fourni et qu'on ne force pas la mise à jour des textes
    if (widget.preconvertedHtml != null && widget.preconvertedHtml!.isNotEmpty && !widget.forceTextUpdate) {
      debugPrint("HTML préconverti détecté, utilisation directe sans conversion");
      _cachedHtml = widget.preconvertedHtml;
      _documentStructureChanged = false;
    }
    
    _loadLinkingConfig().then((_) {
      setState(() {});
    });
    _dbMapping = widget.customMapping != null && widget.customMapping!.isNotEmpty
        ? Map<String, String>.from(widget.customMapping!)
        : _dbMapping;

    debugPrint("Mapping utilisé dans DocxEditorPage : $_dbMapping");

    // Ajouter dynamiquement les clés du customMapping à mappingOptions
    if (widget.customMapping != null) {
      mappingOptions.addAll(
        widget.customMapping!.keys
            .map((key) => key.split(' ').map((word) => word.capitalize()).join(' '))
            .where((option) => !mappingOptions.contains(option)),
      );
    }
    debugPrint("Options de mapping mises à jour : $mappingOptions");

    _loadOriginalDocx();
    _previewWidgetFuture = _buildHtmlPreviewWidget();

    html.window.onMessage.listen((event) {
      if (event.data != null && event.data is Map) {
        final Map message = event.data;
        if (message['action'] == 'associate') {
          int index = message['index'];
          if (index < _selectedLinkings.length) {
            String text = message['text'];
            debugPrint("Association reçue : paragraphe #$index, texte: $text");
            _activeMappingIndexNotifier.value = index;
            _activeMappingTextNotifier.value = text;
            _activeMappingDropdownNotifier.value = _selectedLinkings[index];
          }
        }
      }
    });
  }

  Future<void> _loadOriginalDocx() async {
    if (widget.documentId != "new_document") {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('workspaces')
            .doc(widget.workspaceId)
            .collection('documents')
            .doc(widget.documentId)
            .get();
        if (doc.exists && doc.data() != null) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          String? url = data['originalUrl'] ?? data['url'];
          if (url != null) {
            final response = await http.get(Uri.parse(url));
            if (response.statusCode == 200) {
              Uint8List originalBytes = response.bodyBytes;
              await _extractParagraphs(originalBytes);
              setState(() {
                // Ne pas forcer la conversion si on a déjà un HTML préconverti et qu'on ne force pas la mise à jour
                if (widget.preconvertedHtml == null || widget.forceTextUpdate) {
                  _documentStructureChanged = true;
                }
                _previewWidgetFuture = _buildHtmlPreviewWidget();
              });
              return;
            } else {
              debugPrint("Erreur de téléchargement, statusCode: ${response.statusCode}");
            }
          }
        }
      } catch (e) {
        debugPrint("Erreur lors du chargement du fichier original: $e");
      }
    }
    await _extractParagraphs(widget.docxBytes);
    setState(() {
      // Ne pas forcer la conversion si on a déjà un HTML préconverti et qu'on ne force pas la mise à jour
      if (widget.preconvertedHtml == null || widget.forceTextUpdate) {
        _documentStructureChanged = true;
      }
      _previewWidgetFuture = _buildHtmlPreviewWidget();
    });
  }

  Future<void> _updateLinkMappingInDatabase() async {
    if (widget.documentId == "new_document") {
      debugPrint("Nouveau document, aucun mapping à mettre à jour en DB.");
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('workspaces')
          .doc(widget.workspaceId)
          .collection('documents')
          .doc(widget.documentId)
          .update({
        'linkMapping': _selectedLinkings,
      });
      debugPrint("Mapping mis à jour dans workspaces/${widget.workspaceId}/documents/${widget.documentId}");
    } catch (e) {
      debugPrint("Erreur lors de la mise à jour du mapping en DB: $e");
    }
  }

  // Invalidation du cache HTML - utilisée seulement quand nécessaire
  void _invalidateHtmlCache() {
    _cachedHtml = null;
    _lastConvertedBytes = null;
    _convertApiCacheKey = '';
    _documentStructureChanged = true;
    debugPrint("Cache HTML invalidé");
  }

  // Vérifie si la structure du document a changé de manière significative
  bool _hasDocumentStructureChanged(Uint8List newBytes) {
    if (_lastConvertedBytes == null) return true;
    
    try {
      // Vérifier si la taille a considérablement changé
      int sizeDiff = (newBytes.length - _lastConvertedBytes!.length).abs();
      double sizeDiffPercent = sizeDiff / _lastConvertedBytes!.length * 100;
      
      if (sizeDiffPercent > 5) {  // Si la taille a changé de plus de 5%
        debugPrint("Cache: Taille du document significativement modifiée ($sizeDiffPercent%)");
        return true;
      }
      
      // Générer et comparer les signatures des documents
      // Prendre des échantillons au début, au milieu et à la fin du document
      Uint8List newSignature = Uint8List.fromList([
        ...newBytes.sublist(0, min(500, newBytes.length)),
        ...newBytes.sublist(max(0, newBytes.length ~/ 2 - 250), 
                           min(newBytes.length, newBytes.length ~/ 2 + 250)),
        ...newBytes.sublist(max(0, newBytes.length - 500))
      ]);
      
      Uint8List oldSignature = Uint8List.fromList([
        ..._lastConvertedBytes!.sublist(0, min(500, _lastConvertedBytes!.length)),
        ..._lastConvertedBytes!.sublist(max(0, _lastConvertedBytes!.length ~/ 2 - 250), 
                                       min(_lastConvertedBytes!.length, _lastConvertedBytes!.length ~/ 2 + 250)),
        ..._lastConvertedBytes!.sublist(max(0, _lastConvertedBytes!.length - 500))
      ]);
      
      // Créer des clés de cache à partir des signatures
      String newCacheKey = base64Encode(newSignature);
      String oldCacheKey = base64Encode(oldSignature);
      
      // Si les clés diffèrent, la structure du document a probablement changé
      if (newCacheKey != oldCacheKey) {
        debugPrint("Cache: Signature du document modifiée");
        _convertApiCacheKey = newCacheKey;
        return true;
      }
      
      debugPrint("Cache: Document structurellement identique");
      return false;
    } catch (e) {
      debugPrint("Erreur lors de la comparaison des documents: $e");
      return true; // En cas d'erreur, supposer que le document a changé
    }
  }

  String _fixMojibake(String input) {
    final replacements = <String, String>{
      "Ã©": "é",
      "Ã¨": "è",
      "Ãª": "ê",
      "Ã": "à",
      "Ã´": "ô",
      "Ã®": "î",
      "Ãï": "ï",
      "Ã§": "ç",
      "â": "'",
      "â": "–",
      "â": "—",
      "â": """,
      "â": """,
      "â¬": "€",
      "â¢": "•",
      "Â·": "·",
      "Â": "",
      "Ã ": "à",
      "Ã¹": "ù",
      "Ã»": "û",
      "Ã·": "÷",
      "à": "à",
      "Ã": "À",
      "Â": "'",
    };
    String result = input;
    replacements.forEach((bad, good) {
      result = result.replaceAll(bad, good);
    });
    return result;
  }

  String _groupTextNodes(List<XmlElement> textNodes) {
    return textNodes.map((n) => _fixMojibake(n.text)).join('');
  }

  void _reconstructParagraphs(XmlDocument document) {
    for (var paragraph in document.findAllElements('w:p')) {
      var textNodes = paragraph.findElements('w:t').toList();
      if (textNodes.length > 1) {
        String mergedText = textNodes.map((n) => n.text).join('');
        for (var node in textNodes) {
          node.parent?.children.remove(node);
        }
        var newTextNode = XmlElement(
          XmlName('w:t'),
          textNodes.first.attributes,
          [XmlText(mergedText)],
        );
        paragraph.children.add(newTextNode);
      }
    }
  }

  String _cleanHtmlOutput(String htmlContent) {
    String cleaned = htmlContent;
    cleaned = cleaned.replaceAll(RegExp(r'<span[^>]*>\s*</span>'), '');
    return cleaned;
  }

  bool _validateConversion() {
    for (var pInfo in _paragraphsInfo) {
      String currentText = pInfo.textNodes.map((n) => n.text).join('');
      if (currentText.isEmpty) return false;
    }
    return true;
  }

  Future<void> _extractParagraphs(Uint8List docxBytes) async {
    setState(() => _isProcessing = true);
    try {
      debugPrint("Début de l'extraction...");
      final archive = ZipDecoder().decodeBytes(docxBytes);
      debugPrint("Nombre de fichiers dans le DOCX: ${archive.files.length}");

      _extractImagesAndRelationships(archive);

      // Extraction des en-têtes et pieds de page
      _headerText = "";
      _footerText = "";
      for (var file in archive.files) {
        if (file.name.startsWith("word/header")) {
          String headerXmlStr = utf8.decode(file.content as List<int>);
          XmlDocument headerDoc = XmlDocument.parse(headerXmlStr);
          String headerExtracted = headerDoc.findAllElements("w:t").map((n) => n.text).join(" ");
          _headerText += _fixMojibake(headerExtracted) + "<br>";
        }
        if (file.name.startsWith("word/footer")) {
          String footerXmlStr = utf8.decode(file.content as List<int>);
          XmlDocument footerDoc = XmlDocument.parse(footerXmlStr);
          String footerExtracted = footerDoc.findAllElements("w:t").map((n) => n.text).join(" ");
          _footerText += _fixMojibake(footerExtracted) + "<br>";
        }
      }
      debugPrint("En-tête extrait: $_headerText");
      debugPrint("Pied de page extrait: $_footerText");

      final documentFile = archive.files.firstWhere(
        (f) => f.name == "word/document.xml",
        orElse: () => throw Exception("Fichier word/document.xml introuvable."),
      );
      debugPrint("Fichier document.xml trouvé, taille: ${documentFile.size}");

      final documentXmlStr = utf8.decode(documentFile.content as List<int>);
      final lines = documentXmlStr.split('\n');
      bool foundDeclaration = false;
      final buffer = StringBuffer();
      for (var line in lines) {
        if (line.trim().startsWith('<?xml')) {
          if (!foundDeclaration) {
            buffer.writeln(line);
            foundDeclaration = true;
          }
        } else {
          buffer.writeln(line);
        }
      }
      final cleanXmlStr = buffer.toString();
      _xmlDoc = XmlDocument.parse(cleanXmlStr);

      final paragraphs = _xmlDoc!.findAllElements('w:p');
      debugPrint("Nombre de paragraphes extraits: ${paragraphs.length}");
      if (paragraphs.isEmpty) {
        debugPrint("Aucun paragraphe n'a été extrait du document.");
        return;
      }
      _paragraphsInfo.clear();
      _paragraphFields.clear();

      _selectedLinkings = List<String>.filled(paragraphs.length, "Aucun", growable: false);

      int docxIndex = 0;
      for (var p in paragraphs) {
        final textNodes = p.findAllElements('w:t').toList();
        if (textNodes.isEmpty) continue;
        p.setAttribute('data-docx-index', '$docxIndex');
        String paragraphText = _groupTextNodes(textNodes);
        final lengths = textNodes.map((node) => node.text.length).toList();
        _paragraphsInfo.add(ParagraphInfo(
          paragraph: p,
          textNodes: textNodes,
          originalLengths: lengths,
          originalText: paragraphText,
        ));

        TextEditingController controller = TextEditingController(text: paragraphText);
        if (widget.savedLinkMapping != null && docxIndex < widget.savedLinkMapping!.length) {
          String savedMappingOption = widget.savedLinkMapping![docxIndex];
          _selectedLinkings[docxIndex] = savedMappingOption;
          if (savedMappingOption != "Aucun") {
            String newValue = _dbMapping[savedMappingOption.toLowerCase()] ?? "";
            if (paragraphText.contains(":")) {
              List<String> parts = paragraphText.split(":");
              controller.text = "${parts[0].trim()}: $newValue";
            } else {
              controller.text = newValue;
            }
          }
        }
        String normalized = paragraphText.trim().toLowerCase().replaceAll(" ", "");
        bool isReserved = reservedKeywords.contains(normalized);
        _paragraphFields.add(ParagraphField(
          controller: controller,
          isReserved: isReserved,
        ));
        docxIndex++;
      }
      debugPrint("Extraction terminée. Nombre de champs extraits: ${_paragraphFields.length}");
      
      // Gestion optimisée du cache
      if (widget.preconvertedHtml == null || widget.forceTextUpdate) {
        // Pas de HTML préconverti ou force mise à jour, invalider le cache
        _invalidateHtmlCache();
      } else if (_lastConvertedBytes == null) {
        // HTML préconverti mais pas de bytes de comparaison, mettre à jour pour futures comparaisons
        _lastConvertedBytes = docxBytes;
        
        // Générer une clé de cache pour les comparaisons futures
        _convertApiCacheKey = base64Encode(Uint8List.fromList([
          ...docxBytes.sublist(0, min(500, docxBytes.length)),
          ...docxBytes.sublist(max(0, docxBytes.length ~/ 2 - 250), 
                             min(docxBytes.length, docxBytes.length ~/ 2 + 250)),
          ...docxBytes.sublist(max(0, docxBytes.length - 500))
        ]));
        
        // Ne pas forcer de reconversion
        _documentStructureChanged = false;
      } else {
        // On a déjà un HTML préconverti et des bytes de comparaison, vérifier si le document a changé
        _documentStructureChanged = _hasDocumentStructureChanged(docxBytes);
      }
      
    } catch (e) {
      debugPrint("Erreur lors de l'extraction: $e");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur lors de l'extraction du DOCX.")),
        );
      });
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _extractImagesAndRelationships(Archive archive) {
    debugPrint("Extraction des relations et images...");
    _rels = {};
    _imagesData = {};
    try {
      var relsFile = archive.files.firstWhere(
        (f) => f.name == "word/_rels/document.xml.rels",
        orElse: () => throw Exception("Fichier document.xml.rels introuvable."),
      );
      String relsStr = utf8.decode(relsFile.content as List<int>);
      XmlDocument relsDoc = XmlDocument.parse(relsStr);
      for (var rel in relsDoc.findAllElements('Relationship')) {
        String? id = rel.getAttribute('Id');
        String? type = rel.getAttribute('Type');
        String? target = rel.getAttribute('Target');
        if (id != null && target != null && type != null && type.contains("image")) {
          _rels[id] = target;
          debugPrint("Relation ajoutée: $id -> $target");
        }
      }
    } catch (e) {
      debugPrint("Erreur lors de l'extraction des relations: $e");
    }
    for (var file in archive.files) {
      if (file.name.startsWith("word/media/")) {
        String imagePath = file.name.substring("word/".length);
        String mimeType = "image/png";
        if (imagePath.toLowerCase().endsWith(".jpg") || imagePath.toLowerCase().endsWith(".jpeg")) {
          mimeType = "image/jpeg";
        } else if (imagePath.toLowerCase().endsWith(".gif")) {
          mimeType = "image/gif";
        }
        List<int> bytes = file.content as List<int>;
        String dataUrl = "data:$mimeType;base64,${base64Encode(bytes)}";
        _imagesData[imagePath] = dataUrl;
        debugPrint("Image extraite: $imagePath, taille: ${bytes.length}");
      }
    }
    debugPrint("Extraction terminée. Relations: ${_rels.length}, Images: ${_imagesData.length}");
  }

  Future<Uint8List> _generateModifiedDocxBytes() async {
    _applyManualChanges();

    if (_paragraphsInfo.isEmpty) {
      debugPrint("Aucun paragraphe n'a été extrait du document. Retourne le document original sans modification.");
      return widget.docxBytes;
    }

    for (int i = 0; i < _paragraphsInfo.length; i++) {
      final pInfo = _paragraphsInfo[i];
      bool markerExists = pInfo.textNodes.any((node) => node.text.contains("[[INDEX_$i]]"));
      if (!markerExists) {
        final vanishRun = XmlElement(
          XmlName('w:r'),
          [],
          [
            XmlElement(
              XmlName('w:rPr'),
              [],
              [XmlElement(XmlName('w:vanish'), [], [])],
            ),
            XmlElement(
              XmlName('w:t'),
              [],
              [XmlText("[[INDEX_$i]]")],
            ),
          ],
        );
        pInfo.paragraph.children.add(vanishRun);
      }
    }
    if (_xmlDoc != null) {
      _reconstructParagraphs(_xmlDoc!);
    }
    if (!_validateConversion()) {
      throw Exception("Validation échouée : certaines balises <w:t> sont manquantes.");
    }

    final docXml = _xmlDoc!;
    final newDocumentXmlStr = docXml.toXmlString();
    debugPrint("Nouveau document XML généré.");
    final newDocumentXmlBytes = utf8.encode(newDocumentXmlStr);
    final updatedFile = ArchiveFile("word/document.xml", newDocumentXmlBytes.length, newDocumentXmlBytes);

    final oldArchive = ZipDecoder().decodeBytes(widget.docxBytes);
    final newArchive = Archive();
    for (var f in oldArchive.files) {
      if (f.name != "word/document.xml") {
        newArchive.addFile(f);
      }
    }
    newArchive.addFile(updatedFile);
    final newArchiveData = ZipEncoder().encode(newArchive);
    if (newArchiveData == null) {
      throw Exception("Erreur lors du ré-encodage du DOCX.");
    }
    
    // Vérifier si la structure du document a changé
    Uint8List result = Uint8List.fromList(newArchiveData);
    
    // Mise à jour du statut de modification pour la prochaine génération HTML
    _documentStructureChanged = _hasDocumentStructureChanged(result);
    
    return result;
  }

  Uint8List _updateDocxPlaceholders(
      Uint8List docxBytes, Map<String, String> folderMapping, List<String> linkSelections) {
    debugPrint("=== _updateDocxPlaceholders (DocxEditorPage) ===");
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
                    debugPrint("Aucun <w:t> trouvé pour paragraphe #$index");
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

  Future<String> _convertDocxToHtml(Uint8List docxBytes) async {
    // Incrémenter le compteur de conversions
    _conversionCount++;
    debugPrint("CONVERSION #$_conversionCount VERS CONVERTAPI - Éviter les appels redondants!");
    
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
      
      // Mettre à jour les variables de cache pour éviter les futures conversions
      _lastConvertedBytes = docxBytes;
      
      return htmlContent;
    } else {
      throw Exception("Erreur lors de la conversion DOCX → HTML: ${response.body}");
    }
  }

  void _applyManualChanges() {
    for (int i = 0; i < _paragraphsInfo.length; i++) {
      if (i >= _paragraphFields.length) break;
      final pInfo = _paragraphsInfo[i];
      String newText = _paragraphFields[i].controller.text;
      if (newText.trim().isEmpty && _selectedLinkings[i] != "Aucun") {
        String defaultText = _dbMapping[_selectedLinkings[i].toLowerCase()] ?? _selectedLinkings[i];
        newText = defaultText;
      } else if (newText.trim().isEmpty) {
        newText = " ";
      }
      if (newText == pInfo.originalText) continue;
      final textNodes = pInfo.textNodes;
      if (textNodes.isEmpty) continue;
      int nodeCount = textNodes.length;
      int totalLength = newText.length;
      int baseLength = (totalLength / nodeCount).floor();
      int remainder = totalLength - baseLength * nodeCount;
      int currentIndex = 0;
      for (int j = 0; j < nodeCount; j++) {
        int segmentLength = baseLength + (j < remainder ? 1 : 0);
        if (currentIndex + segmentLength > newText.length) {
          segmentLength = newText.length - currentIndex;
        }
        String segmentText = newText.substring(currentIndex, currentIndex + segmentLength);
        textNodes[j].children
          ..clear()
          ..add(XmlText(segmentText));
        currentIndex += segmentLength;
      }
    }
  }

  Future<void> _previewInWord() async {
    setState(() => _isProcessing = true);
    try {
      Uint8List modifiedBytes = await _generateModifiedDocxBytes();
      final base64Docx = base64Encode(modifiedBytes);
      final dataUrl =
          "data:application/vnd.openxmlformats-officedocument.wordprocessingml.document;base64,$base64Docx";
      html.AnchorElement(href: dataUrl)
        ..setAttribute("download", "modified_document.docx")
        ..click();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de la prévisualisation en Word: $e")),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveMappingOnly({bool skipHtmlConversion = false}) async {
    setState(() => _isProcessing = true);
    try {
      Uint8List modifiedBytes = await _generateModifiedDocxBytes();
      debugPrint("Sauvegarde avec mapping : $_dbMapping, linkSelections : $_selectedLinkings");
      modifiedBytes = _updateDocxPlaceholders(modifiedBytes, _dbMapping, _selectedLinkings);
      await _updateLinkMappingInDatabase();
      
      // Conserver le HTML en cache sauf si explicitement demandé
      if (skipHtmlConversion) {
        _invalidateHtmlCache();
      }
      
      Navigator.pop(context, {
        "docxBytes": modifiedBytes,
        "linkMapping": _selectedLinkings,
        "convertedHtml": _cachedHtml, // Renvoyer le HTML en cache
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mapping sauvegardé avec succès')));
    } catch (e) {
      debugPrint("Erreur sauvegarde mapping : $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lors de l'enregistrement: $e")));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _chooseMapping() async {
    debugPrint("Ouverture du dialogue de mapping global...");
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text("Lier chaque container à une info", style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _paragraphFields.length,
                        itemBuilder: (context, index) {
                          String preview = _paragraphFields[index].controller.text;
                          if (preview.length > 40) {
                            preview = preview.substring(0, 40) + "...";
                          }
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text("Container ${index + 1}: $preview",
                                        style: const TextStyle(fontWeight: FontWeight.w500)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButton<String>(
                                      isExpanded: true,
                                      value: _selectedLinkings[index],
                                      items: mappingOptions.map((option) {
                                        return DropdownMenuItem<String>(
                                          value: option,
                                          child: Text(option),
                                        );
                                      }).toList(),
                                      onChanged: (newVal) {
                                        setStateDialog(() {
                                          _selectedLinkings[index] = newVal!;
                                        });
                                      },
                                      underline: const SizedBox(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            debugPrint("Mapping global annulé");
                            Navigator.pop(context);
                          },
                          child: const Text("Annuler"),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            debugPrint("Application du mapping global...");
                            for (int i = 0; i < _paragraphFields.length; i++) {
                              if (_selectedLinkings[i] != "Aucun") {
                                String selectedOption = _selectedLinkings[i];
                                String newValue = _dbMapping[selectedOption.toLowerCase()] ?? "";
                                String currentText = _paragraphFields[i].controller.text;
                                if (currentText.contains(":")) {
                                  List<String> parts = currentText.split(":");
                                  String label = parts[0].trim();
                                  _paragraphFields[i].controller.text = "$label: $newValue";
                                } else {
                                  _paragraphFields[i].controller.text = newValue;
                                }
                              }
                            }
                            Navigator.pop(context);
                            await _updateLinkMappingInDatabase();
                            setState(() {
                              _previewWidgetFuture = _buildHtmlPreviewWidget();
                            });
                          },
                          child: const Text("Appliquer"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    debugPrint("Mapping global terminé");
    setState(() {});
  }

  // Version optimisée avec mise en cache et utilisation du HTML préconverti
  Future<Widget> _buildHtmlPreviewWidget() async {
    // Appliquer les modifications manuelles même avec HTML préconverti
    if (widget.forceTextUpdate && _paragraphsInfo.isNotEmpty) {
      _applyManualChanges();
    }
    
    // Déterminer si nous avons besoin de générer des bytes modifiés
    bool needsModifiedBytes = _cachedHtml == null || _documentStructureChanged || widget.forceTextUpdate;
    
    Uint8List? modifiedBytes;
    if (needsModifiedBytes) {
      modifiedBytes = await _generateModifiedDocxBytes();
    }
    
    String rawHtml;
    
    // 1. Utiliser le HTML préconverti au premier chargement s'il est disponible (sauf si forceTextUpdate)
    if (_cachedHtml == null && widget.preconvertedHtml != null && !widget.forceTextUpdate) {
      debugPrint("Utilisation du HTML préconverti depuis Firestore");
      rawHtml = widget.preconvertedHtml!;
      _cachedHtml = rawHtml;
      _documentStructureChanged = false;
      
      // Créer une clé de cache pour les comparaisons futures
      if (modifiedBytes != null) {
        _lastConvertedBytes = modifiedBytes;
        _convertApiCacheKey = base64Encode(Uint8List.fromList([
          ...modifiedBytes.sublist(0, min(500, modifiedBytes.length)),
          ...modifiedBytes.sublist(max(0, modifiedBytes.length ~/ 2 - 250), 
                              min(modifiedBytes.length, modifiedBytes.length ~/ 2 + 250)),
          ...modifiedBytes.sublist(max(0, modifiedBytes.length - 500))
        ]));
      }
    } 
    // 2. Utiliser le HTML en cache si disponible et document inchangé
    else if (_cachedHtml != null && !_documentStructureChanged && !widget.forceTextUpdate) {
      debugPrint("Utilisation du HTML en cache (cache hit)");
      rawHtml = _cachedHtml!;
    } 
    // 3. Convertir via ConvertAPI uniquement si nécessaire
    else {
      debugPrint("Conversion DOCX→HTML nécessaire (cache miss ou forceTextUpdate)");
      if (modifiedBytes == null) {
        modifiedBytes = await _generateModifiedDocxBytes();
      }
      rawHtml = await _convertDocxToHtml(modifiedBytes);
      
      // Mettre à jour le cache
      _cachedHtml = rawHtml;
      _lastConvertedBytes = modifiedBytes;
      _documentStructureChanged = false;
      debugPrint("HTML converti mis en cache");
    }

    RegExp bodyExp = RegExp(r'<body[^>]*>([\s\S]*?)<\/body>', caseSensitive: false);
    String mainContent = "";
    if (bodyExp.hasMatch(rawHtml)) {
      mainContent = bodyExp.firstMatch(rawHtml)!.group(1) ?? "";
    } else {
      mainContent = rawHtml;
    }

    mainContent = _cleanHtmlOutput(mainContent);
    _imagesData.forEach((path, dataUrl) {
      mainContent = mainContent.replaceAll('src="$path"', 'src="$dataUrl"');
    });

    int? selectedIndex = _activeMappingIndexNotifier.value;

    final styleAndScriptBlock = '''
    <style>
      * { box-sizing: border-box; }
      html, body { margin: 0; padding: 0; }
      body {
        background: #fff;
        font-family: "Calibri", sans-serif;
        font-size: 11pt;
        color: #000;
      }
      .docxPage {
        width: 612pt;
        height: 792pt;
        margin: 0 auto;
        position: relative;
        border: 1px solid #ccc;
        overflow: hidden;
      }
      .docxHeader, .docxFooter {
        position: absolute;
        left: 0;
        right: 0;
        text-align: center;
        font-size: 10pt;
        padding: 4pt;
        background: #f7f7f7;
      }
      .docxHeader { top: 0; border-bottom: 1px solid #ccc; }
      .docxFooter { bottom: 0; border-top: 1px solid #ccc; }
      .docxContent { margin: 60pt 20pt; }
      .clickable-paragraph {
        cursor: pointer;
        transition: background-color 0.2s;
      }
      .clickable-paragraph:hover {
        background-color: #e0f7fa;
      }
    </style>
    <script>
      document.addEventListener("DOMContentLoaded", function() {
        var markers = document.querySelectorAll("span.docx-marker[data-docx-index]");
        markers.forEach(function(marker) {
          var index = marker.getAttribute("data-docx-index");
          var parentP = marker.closest("p");
          if (parentP && parentP.textContent.trim().length > 0) {
            parentP.classList.add("clickable-paragraph");
            parentP.addEventListener("click", function() {
              console.log("Paragraphe cliqué #" + index + ": " + parentP.textContent.trim());
              window.parent.postMessage({
                action: 'associate',
                index: parseInt(index),
                text: parentP.textContent.trim()
              }, '*');
            });
          }
        });
      });
    </script>
    <script>
      document.addEventListener("DOMContentLoaded", function() {
        var selectedIndex = ${selectedIndex != null ? selectedIndex : 'null'};
        if (selectedIndex !== null) {
          var marker = document.querySelector("span.docx-marker[data-docx-index='" + selectedIndex + "']");
          if (marker) {
            var p = marker.closest("p");
            if (p) { 
              p.style.backgroundColor = "#cceeff";
            }
          }
        }
      });
    </script>
    ''';

    String finalHtml = '''
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        $styleAndScriptBlock
      </head>
      <body>
        <div class="docxPage">
          <div class="docxHeader">
            $_headerText
          </div>
          <div class="docxContent">
            $mainContent
          </div>
          <div class="docxFooter">
            $_footerText
          </div>
        </div>
      </body>
    </html>
    ''';

    finalHtml = finalHtml.replaceAllMapped(
      RegExp(r'\[\[INDEX_(\d+)\]\]'),
      (match) => '<span class="docx-marker" data-docx-index="${match[1]}" style="display:none;"></span>',
    );

    final encodedHtml = base64Encode(utf8.encode(finalHtml));
    final String viewId = 'iframeElement-${DateTime.now().millisecondsSinceEpoch}';
    _currentIFrameId = viewId;
    debugPrint("Création de la vue pour l'iframe, viewId: $viewId");
    ui.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
      final html.IFrameElement iframe = html.IFrameElement()
        ..src = 'data:text/html;base64,$encodedHtml'
        ..id = viewId.toString()
        ..style.border = 'none'
        ..style.zIndex = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true;
      return iframe;
    });

    return HtmlElementView(viewType: viewId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Aperçu HTML DOCX"),
            if (_conversionCount > 0)
              Text(
                "Conversions: $_conversionCount", 
                style: TextStyle(fontSize: 12, color: Colors.grey[300]),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: "Choisir lien global",
            onPressed: _isProcessing ? null : _chooseMapping,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: "Enregistrer",
            onPressed: _isProcessing ? null : _saveMappingOnly,
          ),
        ],
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : _paragraphFields.isEmpty
              ? const Center(child: Text("Chargement des paragraphes…"))
              : FutureBuilder<Widget>(
                  future: _previewWidgetFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Center(child: Text("Erreur: ${snapshot.error}"));
                    } else {
                      return Row(
                        children: [
                          Container(
                            width: 300,
                            color: Colors.grey[100],
                            child: _buildModificationsList(),
                          ),
                          Expanded(child: snapshot.data!),
                          ValueListenableBuilder<int?>(
                            valueListenable: _activeMappingIndexNotifier,
                            builder: (context, activeIndex, _) {
                              return activeIndex != null
                                  ? Container(
                                      width: 300,
                                      color: Colors.white,
                                      child: _buildMappingPanel(),
                                    )
                                  : const SizedBox();
                            },
                          ),
                        ],
                      );
                    }
                  },
                ),
    );
  }

  Widget _buildModificationsList() {
    List<Widget> modifications = [];
    for (int i = 0; i < _selectedLinkings.length; i++) {
      String mapping = _selectedLinkings[i];
      if (mapping != "Aucun") {
        String? value = _dbMapping[mapping.toLowerCase()];
        modifications.add(
          ListTile(
            title: Text("Container ${i + 1}"),
            subtitle: Text("$mapping liée à ${value ?? ''}"),
          ),
        );
      }
    }
    return modifications.isEmpty
        ? const Center(child: Text("Aucune action modifiée"))
        : ListView(children: modifications);
  }

  Widget _buildMappingPanel() {
    return ValueListenableBuilder<int?>(
      valueListenable: _activeMappingIndexNotifier,
      builder: (context, activeIndex, _) {
        if (activeIndex == null) return const SizedBox();
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Lier ce paragraphe",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: mappingOptions.map((option) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: ValueListenableBuilder<String>(
                      valueListenable: _activeMappingDropdownNotifier,
                      builder: (context, currentOption, _) {
                        return ChoiceChip(
                          label: Text(option),
                          selected: currentOption == option,
                          onSelected: (bool selected) {
                            if (selected) {
                              _activeMappingDropdownNotifier.value = option;
                            }
                          },
                          backgroundColor: Colors.grey[300],
                          selectedColor: Colors.grey[600],
                          labelStyle: TextStyle(
                            color: currentOption == option ? Colors.white : Colors.black,
                          ),
                        );
                      },
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      _activeMappingIndexNotifier.value = null;
                      _activeMappingTextNotifier.value = null;
                    },
                    child: const Text("Annuler"),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      int? idx = _activeMappingIndexNotifier.value;
                      if (idx != null && idx < _selectedLinkings.length) {
                        _selectedLinkings[idx] = _activeMappingDropdownNotifier.value;
                        if (_activeMappingDropdownNotifier.value != "Aucun") {
                          String newValue = _dbMapping[_activeMappingDropdownNotifier.value.toLowerCase()] ?? "";
                          String currentText = _paragraphFields[idx].controller.text;
                          if (currentText.contains(":")) {
                            List<String> parts = currentText.split(":");
                            String label = parts[0].trim();
                            _paragraphFields[idx].controller.text = "$label: $newValue";
                          } else {
                            _paragraphFields[idx].controller.text = newValue;
                          }
                        }
                        await _updateLinkMappingInDatabase();
                        setState(() {
                          _previewWidgetFuture = _buildHtmlPreviewWidget();
                        });
                      } else {
                        debugPrint("Mapping panel: index $idx hors limites.");
                      }
                      _activeMappingIndexNotifier.value = null;
                      _activeMappingTextNotifier.value = null;
                    },
                    child: const Text("Appliquer"),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
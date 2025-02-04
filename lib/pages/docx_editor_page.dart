// lib/pages/docx_editor_page.dart
//  static const String _apiKey =    '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'; // Remplacez par votre clé API réelle et sécurisé
  //
import 'dart:typed_data';
import 'dart:convert'; // For jsonEncode if needed
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:universal_html/html.dart' as html;
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:xml/xml.dart';

import '../services/ai_service.dart'; // Path to your AIService

class DocxEditorPage extends StatefulWidget {
  final Uint8List docxBytes;

  const DocxEditorPage({super.key, required this.docxBytes});

  @override
  _DocxEditorPageState createState() => _DocxEditorPageState();
}

class _DocxEditorPageState extends State<DocxEditorPage> {
  bool _isProcessing = false;
  Map<String, String> _fieldValues = {};
  List<String> _annotations = [];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Instantiate your AIService
  final AIService _aiService = AIService();

  @override
  void initState() {
    super.initState();
    if (widget.docxBytes.isNotEmpty) {
      _extractAnnotations(widget.docxBytes);
    }
  }

  //----------------------------------------------------------------------------
  // 1) MANUAL EXTRACTION OF ANNOTATIONS, EVEN IF WORD HAS SPLIT THE TEXT
  //----------------------------------------------------------------------------
  Future<void> _extractAnnotations(Uint8List docxBytes) async {
    setState(() => _isProcessing = true);

    try {
      // 1. Decompress the DOCX file as archive
      final archive = ZipDecoder().decodeBytes(docxBytes);

      // 2. Find the 'word/document.xml' file
      final documentFile = archive.files.firstWhere(
        (file) => file.name == 'word/document.xml',
        orElse: () => throw Exception('document.xml not found in DOCX.'),
      );

      // 3. Read its content in UTF8
      final documentXmlBytes = documentFile.content as List<int>;
      final documentXmlStr = utf8.decode(documentXmlBytes);

      // 4. Parse as XML structure
      final xmlDoc = XmlDocument.parse(documentXmlStr);

      // 5. Traverse all <w:p> = paragraphs
      final paragraphs = xmlDoc.findAllElements('w:p');

      final Set<String> foundVariables = {};

      for (var paragraph in paragraphs) {
        // Retrieve all text in this paragraph
        String paragraphText = _getFullTextOfParagraph(paragraph);

        // Find {{...}} via regex
        final regex = RegExp(r'{{(.*?)}}');
        final matches = regex.allMatches(paragraphText);

        for (var match in matches) {
          final variableName = match.group(1) ?? '';
          // Exclude # or / if necessary
          if (variableName.isNotEmpty &&
              !variableName.startsWith('#') &&
              !variableName.startsWith('/')) {
            foundVariables.add(variableName.trim());
          }
        }
      }

      setState(() {
        _annotations = foundVariables.toList();
        _fieldValues = {for (var v in _annotations) v: ""};
      });

      debugPrint("Extracted annotations: $_annotations");
    } catch (e) {
      debugPrint("Error during annotation extraction: $e");
      _showErrorSnackbar('Error during annotation extraction.');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  /// This function concatenates ALL text of the paragraph
  /// (all <w:r>, <w:t>), ignoring tags like <w:proofErr> etc.
  String _getFullTextOfParagraph(XmlElement paragraph) {
    String buffer = '';
    // Traverse all <w:r> (runs)
    final runs = paragraph.findAllElements('w:r');
    for (var run in runs) {
      // In each run, all <w:t> = texts
      final texts = run.findAllElements('w:t');
      for (var t in texts) {
        buffer += t.text;
      }
    }
    return buffer;
  }

  //----------------------------------------------------------------------------
  // 2) MANUAL DOCX GENERATION BY FILLING THE FIELDS
  //----------------------------------------------------------------------------
  Future<void> _generateDocxManually() async {
    setState(() => _isProcessing = true);

    try {
      // 1. Decompress the DOCX
      final archive = ZipDecoder().decodeBytes(widget.docxBytes);

      // 2. Find 'word/document.xml'
      final documentFile = archive.files.firstWhere(
        (file) => file.name == 'word/document.xml',
        orElse: () => throw Exception('document.xml not found in DOCX.'),
      );

      final documentXmlStr = utf8.decode(documentFile.content as List<int>);
      final xmlDoc = XmlDocument.parse(documentXmlStr);

      // 3. Traverse each paragraph
      for (var paragraph in xmlDoc.findAllElements('w:p')) {
        // Recompose the full text
        String paragraphText = _getFullTextOfParagraph(paragraph);

        // Replace all variables {{key}}
        for (var entry in _fieldValues.entries) {
          final key = entry.key;
          final value = entry.value.isNotEmpty
              ? entry.value
              : _getDefaultValueForVariable(key);
          final pattern = '{{$key}}';
          paragraphText = paragraphText.replaceAll(pattern, value);
        }

        // Optionally handle dynamic lists like invoice_items here

        // 4. Remove existing runs, create a new single run
        final runs = paragraph.findAllElements('w:r').toList();
        for (var r in runs) {
          r.parent?.children.remove(r);
        }

        final newRun = XmlElement(XmlName('w:r'), [], [
          XmlElement(XmlName('w:t'), [], [XmlText(paragraphText)])
        ]);
        paragraph.children.add(newRun);
      }

      // 5. Convert XML to string
      final modifiedXml = xmlDoc.toXmlString();

      // 6. Update the archive
      final updatedDocumentFile = ArchiveFile(
        'word/document.xml',
        modifiedXml.length,
        utf8.encode(modifiedXml),
      );

      final newArchive = Archive();
      for (var f in archive.files) {
        if (f.name != 'word/document.xml') {
          newArchive.addFile(f);
        }
      }
      newArchive.addFile(updatedDocumentFile);

      final encoded = ZipEncoder().encode(newArchive);
      if (encoded == null) {
        throw Exception("Unable to encode the modified file");
      }

      // 7. Download in the browser
      final blob = html.Blob([Uint8List.fromList(encoded)],
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", "modified_document.docx")
        ..click();
      html.Url.revokeObjectUrl(url);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DOCX modified and downloaded (manual).')),
      );
    } catch (e) {
      debugPrint("Error during manual generation: $e");
      _showErrorSnackbar('Error during manual DOCX generation.');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  //----------------------------------------------------------------------------
  // 3) AUTOMATED GENERATION VIA AI
  //----------------------------------------------------------------------------
  Future<void> _generateDocxAutomated() async {
    setState(() => _isProcessing = true);

    try {
      // Define the folder/document
      String folderName = 'Boundly';
      String documentName = 'Modified MBsolution.docx';

      // Build the prompt with necessary information
      String prompt = '''
Modify the document "$documentName" in the folder "$folderName" with the following variables:
${_fieldValues.entries.map((e) => '${e.key}: ${e.value.isNotEmpty ? e.value : _getDefaultValueForVariable(e.key)}').join('\n')}
''';

      debugPrint('Constructed AI prompt: $prompt');

      // Send to AI via AIService
      await _aiService.sendMessage(prompt);
      debugPrint('AI message sent for document modification.');

      // Wait for the AI to process the action (adjust the duration if necessary)
      await Future.delayed(const Duration(seconds: 10));

      // Retrieve the modified document from Firestore
      final folderSnapshot = await _firestore
          .collection('folders')
          .where('name', isEqualTo: folderName)
          .limit(1)
          .get();
      if (folderSnapshot.docs.isEmpty) {
        _showErrorSnackbar('Folder not found: $folderName');
        return;
      }
      final folderId = folderSnapshot.docs.first.id;

      final docSnapshot = await _firestore
          .collection('documents')
          .where('title', isEqualTo: documentName)
          .where('folderId', isEqualTo: folderId)
          .limit(1)
          .get();
      if (docSnapshot.docs.isEmpty) {
        _showErrorSnackbar(
            'Document not found: $documentName in $folderName');
        return;
      }

      // Retrieve the 'modifiedUrl' field
      final modifiedUrl = docSnapshot.docs.first.data()['modifiedUrl'] as String?;
      if (modifiedUrl == null) {
        _showErrorSnackbar('Modified document URL not found.');
        return;
      }

      debugPrint('Modified document URL: $modifiedUrl');

      // Download the modified document
      final response = await http.get(Uri.parse(modifiedUrl));
      if (response.statusCode != 200) {
        _showErrorSnackbar('Error downloading the modified document.');
        return;
      }
      final modifiedBytes = response.bodyBytes;

      // Local download
      final blob = html.Blob([Uint8List.fromList(modifiedBytes)],
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute("download", "modified_document.docx")
        ..click();
      html.Url.revokeObjectUrl(url);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DOCX modified and downloaded (AI).')),
      );
    } catch (e) {
      debugPrint("AI Error: $e");
      _showErrorSnackbar('Error during automated generation (AI).');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  //---------------------------------------------------------------------------
  // 4) ERROR SNACKBAR
  //---------------------------------------------------------------------------
  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.red,
      ),
    );
  }

  //---------------------------------------------------------------------------
  // UI: Build input fields for each annotation
  //---------------------------------------------------------------------------
  Widget _buildAnnotationFields() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          for (var annotation in _annotations)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: TextField(
                decoration: InputDecoration(
                  labelText: _formatLabel(annotation),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => _fieldValues[annotation] = value,
              ),
            ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isProcessing ? null : _generateDocxManually,
            child: _isProcessing
                ? const CircularProgressIndicator()
                : const Text('Generate DOCX (Manual)'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isProcessing ? null : _generateDocxAutomated,
            child: _isProcessing
                ? const CircularProgressIndicator()
                : const Text('Generate Invoice Automatically (AI)'),
          ),
        ],
      ),
    );
  }

  // Format a label "client_name" => "Client Name"
  String _formatLabel(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '')
        .join(' ');
  }

  //----------------------------------------------------------------------------
  // BUILD
  //----------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DOCX Editor'),
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : _annotations.isNotEmpty
              ? _buildAnnotationFields()
              : const Center(child: Text('No annotations found.')),
    );
  }

  //---------------------------------------------------------------------------
  // Retourne une valeur par défaut basée sur la clé de la variable
  //---------------------------------------------------------------------------
  String _getDefaultValueForVariable(String key) {
    switch (key) {
      case 'siret':
        return '00000000000000';
      case 'entrepreneur_name':
        return 'Entrepreneur Name';
      case 'entrepreneur_status':
        return 'Entrepreneur Status';
      case 'client_name':
        return 'Client Name';
      case 'client_email':
        return 'client@example.com';
      case 'client_phone':
        return '0123456789';
      case 'start_date':
        return DateTime.now().toIso8601String().split('T').first; // YYYY-MM-DD
      case 'payment_due_days':
        return '30';
      case 'item_quantity':
        return '1';
      case 'item_unit':
        return 'unit';
      case 'item_price_ht':
        return '100';
      case 'item_tva_total':
        return '20';
      case 'item_ttc_total':
        return '120';
      case 'total_ht':
        return '100';
      case 'total_tva':
        return '20';
      case 'total_ttc':
        return '120';
      case 'bank_name':
        return 'Bank Name';
      case 'entrepreneur_phone':
        return '0987654321';
      case 'bank_iban':
        return 'FR76 3000 6000 0112 3456 7890 189';
      case 'entrepreneur_email':
        return 'entrepreneur@example.com';
      case 'bank_swift':
        return 'BNPAFRPPXXX';
      default:
        return 'N/A';
    }
  }
}

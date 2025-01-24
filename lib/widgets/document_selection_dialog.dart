// lib/widgets/document_selection_dialog.dart

import 'package:flutter/material.dart';

class DocumentSelectionDialog extends StatelessWidget {
  final List<String> documents;
  final Function(int) onSelected;

  const DocumentSelectionDialog({super.key, required this.documents, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Choisissez un document à modifier'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: documents.length,
          itemBuilder: (context, index) {
            return ListTile(
              title: Text(documents[index]),
              onTap: () {
                onSelected(index);
                Navigator.of(context).pop();
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          child: Text('Annuler'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

// lib/widgets/document_form_dialog.dart

import 'package:flutter/material.dart';

class DocumentFormDialog extends StatefulWidget {
  final Function(String, String) onSubmit;

  const DocumentFormDialog({super.key, required this.onSubmit});

  @override
  State<DocumentFormDialog> createState() => _DocumentFormDialogState();
}

class _DocumentFormDialogState extends State<DocumentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  String _title = '';
  String _content = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Créer un Nouveau Document'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: InputDecoration(labelText: 'Titre'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer un titre';
                  }
                  return null;
                },
                onSaved: (value) {
                  _title = value ?? '';
                },
              ),
              TextFormField(
                decoration: InputDecoration(labelText: 'Contenu'),
                maxLines: 5,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer du contenu';
                  }
                  return null;
                },
                onSaved: (value) {
                  _content = value ?? '';
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              _formKey.currentState?.save();
              widget.onSubmit(_title, _content);
              Navigator.of(context).pop();
            }
          },
          child: Text('Créer'),
        ),
      ],
    );
  }
}

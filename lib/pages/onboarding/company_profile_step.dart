import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/onboarding_controller.dart';

class CompanyProfileStep extends StatefulWidget {
  const CompanyProfileStep({Key? key}) : super(key: key);
  @override
  State<CompanyProfileStep> createState() => _CompanyProfileStepState();
}

class _CompanyProfileStepState extends State<CompanyProfileStep> {
  final _nameController = TextEditingController();
  final _industryController = TextEditingController();
  String _selectedSize = 'PME (10-50)';
  final List<String> _companySizes = [
    'Startup (1-9)', 'PME (10-50)', 'Moyenne (51-250)', 'Grande (251-1000)', 'Très grande (1000+)',
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final company = Provider.of<OnboardingController>(context, listen: false).onboardingData['company'];
      _nameController.text = company['name'] ?? '';
      _industryController.text = company['industry'] ?? '';
      if (company['size'] != null && company['size'].isNotEmpty) _selectedSize = company['size'];
    });
  }
  @override
  void dispose() {
    _nameController.dispose();
    _industryController.dispose();
    super.dispose();
  }
  void _save() {
    Provider.of<OnboardingController>(context, listen: false).updateCompanyData({
      'name': _nameController.text,
      'industry': _industryController.text,
      'size': _selectedSize,
      'logo': '', // à remplacer par l'URL si upload
    });
  }
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Profil de l\'Entreprise', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Ces informations nous aideront à personnaliser l\'expérience Boundly.', style: TextStyle(fontSize: 16, color: Colors.grey)),
        const SizedBox(height: 30),
        Center(
          child: Column(children: [
            Container(
              width: 120, height: 120,
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[300]!)),
              child: const Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text('Logo de l\'entreprise', style: TextStyle(fontSize: 14, color: Colors.grey)),
          ]),
        ),
        const SizedBox(height: 30),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(labelText: 'Nom de l\'entreprise', hintText: 'Ex: Acme Corporation', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _industryController,
          decoration: InputDecoration(labelText: 'Secteur d\'activité', hintText: 'Ex: Technologie, Santé, Finance', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          onChanged: (_) => _save(),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          value: _selectedSize,
          decoration: InputDecoration(labelText: 'Taille de l\'entreprise', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          items: _companySizes.map((size) => DropdownMenuItem<String>(value: size, child: Text(size))).toList(),
          onChanged: (value) { if (value != null) { setState(() { _selectedSize = value; }); _save(); } },
        ),
      ]),
    );
  }
}

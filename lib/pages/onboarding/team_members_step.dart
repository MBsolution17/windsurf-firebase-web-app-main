import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/onboarding_controller.dart';

class TeamMembersStep extends StatefulWidget {
  const TeamMembersStep({Key? key}) : super(key: key);
  @override
  State<TeamMembersStep> createState() => _TeamMembersStepState();
}

class _TeamMembersStepState extends State<TeamMembersStep> {
  final TextEditingController _emailController = TextEditingController();
  String _selectedRole = 'Membre';
  bool _isValidEmail = false;
  final List<String> _roles = ['Admin', 'Membre', 'Observateur'];
  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
  void _validateEmail(String value) {
    setState(() {
      _isValidEmail = value.isNotEmpty && value.contains('@') && value.contains('.');
    });
  }
  @override
  Widget build(BuildContext context) {
    return Consumer<OnboardingController>(
      builder: (context, controller, _) {
        final members = controller.onboardingData['members'] as List;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Inviter des Membres', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Ajoutez des collègues pour collaborer dans votre espace Boundly.', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 30),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ajouter un nouveau membre', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Adresse email',
                        hintText: 'Ex: collegue@company.com',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        suffixIcon: _isValidEmail ? const Icon(Icons.check_circle, color: Colors.green) : null,
                      ),
                      keyboardType: TextInputType.emailAddress,
                      onChanged: _validateEmail,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedRole,
                      decoration: InputDecoration(labelText: 'Rôle', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                      items: _roles.map((role) => DropdownMenuItem<String>(value: role, child: Text(role))).toList(),
                      onChanged: (value) { if (value != null) setState(() { _selectedRole = value; }); },
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isValidEmail ? () {
                        controller.addMember({'email': _emailController.text, 'role': _selectedRole});
                        _emailController.clear();
                        setState(() { _isValidEmail = false; });
                      } : null,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Inviter'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (members.isNotEmpty)
              ...[
                Text('Membres invités (${members.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: members.length,
                  itemBuilder: (context, i) {
                    final member = members[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(member['email'] ?? ''),
                        subtitle: Text('Rôle: ${member['role'] ?? 'Membre'}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => controller.removeMember(member['email']),
                        ),
                      ),
                    );
                  },
                ),
              ]
            else
              Card(
                elevation: 0,
                color: Colors.grey[100],
                margin: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: const Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.people_outline, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Aucun membre invité pour le moment', style: TextStyle(fontSize: 16, color: Colors.grey), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }
}

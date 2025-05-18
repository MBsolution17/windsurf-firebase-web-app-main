import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/onboarding_controller.dart';

class IntegrationsStep extends StatefulWidget {
  const IntegrationsStep({Key? key}) : super(key: key);
  @override
  State<IntegrationsStep> createState() => _IntegrationsStepState();
}

class _IntegrationsStepState extends State<IntegrationsStep> {
  final TextEditingController _customApiController = TextEditingController();
  @override
  void dispose() {
    _customApiController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Consumer<OnboardingController>(
      builder: (context, controller, _) {
        final integrations = controller.onboardingData['integrations'];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Intégrations', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Connectez Boundly aux outils que votre entreprise utilise déjà.', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 30),
            _buildSwitch('Google Workspace', 'google', integrations['google'] ?? false, controller),
            _buildSwitch('Slack', 'slack', integrations['slack'] ?? false, controller),
            _buildSwitch('Trello', 'trello', integrations['trello'] ?? false, controller),
            _buildSwitch('Notion', 'notion', integrations['notion'] ?? false, controller),
            _buildSwitch('Jira', 'jira', integrations['jira'] ?? false, controller),
            const SizedBox(height: 24),
            const Text('API personnalisées', style: TextStyle(fontWeight: FontWeight.bold)),
            if ((integrations['custom_apis'] as List).isNotEmpty)
              ...List.generate((integrations['custom_apis'] as List).length, (i) {
                final api = (integrations['custom_apis'] as List)[i];
                return ListTile(
                  title: Text(api['name'] ?? 'API'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () {
                      controller.removeCustomApiAt(i);
                      setState(() {});
                    },
                  ),
                );
              }),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _customApiController,
                  decoration: const InputDecoration(labelText: 'Nom de l\'API'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (_customApiController.text.isNotEmpty) {
                    controller.addCustomApi({'name': _customApiController.text});
                    setState(() { _customApiController.clear(); });
                  }
                },
                child: const Text('Ajouter'),
              ),
            ]),
          ]),
        );
      },
    );
  }
  Widget _buildSwitch(String title, String key, bool value, OnboardingController controller) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: (val) => controller.toggleIntegration(key, val),
      activeColor: Theme.of(context).primaryColor,
    );
  }
}

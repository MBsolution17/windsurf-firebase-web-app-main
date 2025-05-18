import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/onboarding_controller.dart';

class AIConfigurationStep extends StatefulWidget {
  const AIConfigurationStep({Key? key}) : super(key: key);

  @override
  _AIConfigurationStepState createState() => _AIConfigurationStepState();
}

class _AIConfigurationStepState extends State<AIConfigurationStep> {
  @override
  Widget build(BuildContext context) {
    return Consumer<OnboardingController>(
      builder: (context, controller, _) {
        final aiConfig = controller.onboardingData['ai_config'];
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configuration de l\'IA',
                style: GoogleFonts.roboto(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Personnalisez le comportement de l\'assistant IA selon vos préférences.',
                style: GoogleFonts.roboto(
                  fontSize: 16,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 24),
              
              // Image illustrative
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.smart_toy,
                    size: 60,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Options de configuration
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Options Générales',
                        style: GoogleFonts.roboto(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Synthèse vocale
                      SwitchListTile(
                        title: const Text('Synthèse vocale'),
                        subtitle: const Text('L\'assistant lira ses réponses à haute voix'),
                        value: aiConfig['voice_enabled'] ?? true,
                        onChanged: (value) {
                          controller.updateAIConfig({'voice_enabled': value});
                        },
                        activeColor: Theme.of(context).primaryColor,
                      ),
                      
                      const Divider(),
                      
                      // Création automatique de tâches
                      SwitchListTile(
                        title: const Text('Création automatique de tâches'),
                        subtitle: const Text('L\'assistant pourra créer des tâches dans votre calendrier'),
                        value: aiConfig['auto_task_creation'] ?? true,
                        onChanged: (value) {
                          controller.updateAIConfig({'auto_task_creation': value});
                        },
                        activeColor: Theme.of(context).primaryColor,
                      ),
                      
                      const Divider(),
                      
                      // Langue
                      ListTile(
                        title: const Text('Langue'),
                        subtitle: const Text('Choisissez la langue de l\'assistant'),
                        trailing: DropdownButton<String>(
                          value: aiConfig['language'] ?? 'fr-FR',
                          items: const [
                            DropdownMenuItem(
                              value: 'fr-FR',
                              child: Text('Français'),
                            ),
                            DropdownMenuItem(
                              value: 'en-US',
                              child: Text('Anglais'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              controller.updateAIConfig({'language': value});
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

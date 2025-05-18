import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/onboarding_controller.dart';
import 'company_profile_step.dart';
import 'integrations_step.dart';
import 'team_members_step.dart';
import 'ai_configuration_step.dart';
import 'linking_config_step.dart';

class OnboardingPage extends StatefulWidget {
  final String workspaceId;
  const OnboardingPage({Key? key, required this.workspaceId}) : super(key: key);
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late PageController _pageController;
  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<OnboardingController>(context, listen: false).setWorkspaceId(widget.workspaceId);
    });
  }
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Consumer<OnboardingController>(
      builder: (context, controller, _) {
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Image.asset('assets/images/Orion.png', height: 40, fit: BoxFit.contain),
                      const SizedBox(width: 12),
                      const Text('Configuration de votre espace Boundly', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                _buildProgress(controller),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (index) => controller.goToStep(index),
                    children: const [
                      CompanyProfileStep(),
                      LinkingConfigStep(),
                      IntegrationsStep(),
                      TeamMembersStep(),
                      AIConfigurationStep(),
                    ],
                  ),
                ),
                _buildNav(controller),
              ],
            ),
          ),
        );
      },
    );
  }
  Widget _buildProgress(OnboardingController controller) {
    final steps = ["Profil d'entreprise", 'Intégrations', 'Équipe', 'Configuration IA'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isEven) {
            final idx = i ~/ 2, active = idx <= controller.currentStep, current = idx == controller.currentStep;
            return Expanded(
              child: Column(children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: active ? Theme.of(context).primaryColor : Colors.grey[300],
                    shape: BoxShape.circle,
                    border: current ? Border.all(color: Theme.of(context).primaryColor, width: 2) : null,
                  ),
                  child: Center(
                    child: active && !current ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text('${idx + 1}', style: TextStyle(color: active ? Colors.white : Colors.grey[600], fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(steps[idx], style: TextStyle(fontSize: 12, color: active ? Theme.of(context).primaryColor : Colors.grey[600], fontWeight: active ? FontWeight.bold : FontWeight.normal), textAlign: TextAlign.center),
              ]),
            );
          } else {
            final left = i ~/ 2, active = left < controller.currentStep;
            return Expanded(child: Container(height: 2, color: active ? Theme.of(context).primaryColor : Colors.grey[300]));
          }
        }),
      ),
    );
  }
  Widget _buildNav(OnboardingController controller) {
    final isLast = controller.currentStep == 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, -1), blurRadius: 5)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (controller.currentStep > 0)
            ElevatedButton(
              onPressed: controller.isLoading ? null : () {
                controller.previousStep();
                _pageController.animateToPage(controller.currentStep, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300], foregroundColor: Colors.black87, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
              child: const Text('Précédent'),
            )
          else
            const SizedBox.shrink(),
          ElevatedButton(
            onPressed: controller.isLoading ? null : () async {
              if (isLast) {
                final success = await controller.saveOnboardingData();
                if (success && mounted) {
                  Navigator.pushReplacementNamed(context, '/dashboard', arguments: {'workspaceId': controller.workspaceId});
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(controller.errorMessage ?? 'Une erreur est survenue'), backgroundColor: Colors.red),
                  );
                }
              } else {
                controller.nextStep();
                _pageController.animateToPage(controller.currentStep, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            child: controller.isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                : Text(isLast ? 'Terminer' : 'Suivant'),
          ),
        ],
      ),
    );
  }
}

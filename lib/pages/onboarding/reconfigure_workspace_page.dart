import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/onboarding_controller.dart';
import 'company_profile_step.dart';
import 'linking_config_step.dart';
import 'integrations_step.dart';
import 'team_members_step.dart';
import 'ai_configuration_step.dart';

class ReconfigureWorkspacePage extends StatelessWidget {
  final String workspaceId;
  const ReconfigureWorkspacePage({Key? key, required this.workspaceId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OnboardingController()..setWorkspaceId(workspaceId),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reconfigurer le workspace'),
        ),
        body: PageView(
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            CompanyProfileStep(),
            LinkingConfigStep(),
            IntegrationsStep(),
            TeamMembersStep(),
            AIConfigurationStep(),
          ],
        ),
      ),
    );
  }
}

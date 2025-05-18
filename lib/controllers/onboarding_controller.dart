import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OnboardingController extends ChangeNotifier {
  // ...
  // Méthodes pour gérer la configuration des liens personnalisés
  void addLinkingOption(String option) {
    final linkingConfig = onboardingData['linking_config'] ?? {'mappingOptions': [], 'dbMapping': {}};
    final options = List<String>.from(linkingConfig['mappingOptions'] ?? []);
    if (!options.contains(option)) {
      options.add(option);
      linkingConfig['mappingOptions'] = options;
      onboardingData['linking_config'] = linkingConfig;
      notifyListeners();
    }
  }

  void removeLinkingOption(String option) {
    final linkingConfig = onboardingData['linking_config'] ?? {'mappingOptions': [], 'dbMapping': {}};
    final options = List<String>.from(linkingConfig['mappingOptions'] ?? []);
    options.remove(option);
    linkingConfig['mappingOptions'] = options;
    onboardingData['linking_config'] = linkingConfig;
    notifyListeners();
  }

  void updateLinkingDefault(String option, String value) {
    final linkingConfig = onboardingData['linking_config'] ?? {'mappingOptions': [], 'dbMapping': {}};
    final dbMapping = Map<String, String>.from(linkingConfig['dbMapping'] ?? {});
    dbMapping[option.toLowerCase()] = value;
    linkingConfig['dbMapping'] = dbMapping;
    onboardingData['linking_config'] = linkingConfig;
    notifyListeners();
  }

  Future<void> saveLinkingConfigToFirestore(String workspaceId) async {
    final linkingConfig = onboardingData['linking_config'] ?? {'mappingOptions': [], 'dbMapping': {}};
    await FirebaseFirestore.instance.collection('workspaces').doc(workspaceId).set({
      'linking_config': linkingConfig,
    }, SetOptions(merge: true));
  }

  int _currentStep = 0;
  String _workspaceId = '';
  bool _isLoading = false;
  String? _errorMessage;
  
  final Map<String, dynamic> _onboardingData = {
    'company': {
      'name': '',
      'industry': '',
      'size': '',
      'logo': '',
    },
    'integrations': {
      'google': false,
      'slack': false,
      'trello': false,
      'notion': false,
      'jira': false,
      'custom_apis': [],
    },
    'members': [],
    'ai_config': {
      'voice_enabled': true,
      'auto_task_creation': true,
      'language': 'fr-FR',
    }
  };

  // Getters
  int get currentStep => _currentStep;
  String get workspaceId => _workspaceId;
  Map<String, dynamic> get onboardingData => _onboardingData;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Setters
  void setWorkspaceId(String id) {
    _workspaceId = id;
    notifyListeners();
  }

  void updateCompanyData(Map<String, dynamic> data) {
    _onboardingData['company'].addAll(data);
    notifyListeners();
  }

  void toggleIntegration(String name, bool value) {
    _onboardingData['integrations'][name] = value;
    notifyListeners();
  }

  void addCustomApi(Map<String, dynamic> api) {
    (_onboardingData['integrations']['custom_apis'] as List).add(api);
    notifyListeners();
  }

  void removeCustomApiAt(int index) {
    (_onboardingData['integrations']['custom_apis'] as List).removeAt(index);
    notifyListeners();
  }

  void addMember(Map<String, dynamic> member) {
    _onboardingData['members'].add(member);
    notifyListeners();
  }

  void removeMember(String email) {
    _onboardingData['members'].removeWhere((member) => member['email'] == email);
    notifyListeners();
  }

  void updateAIConfig(Map<String, dynamic> config) {
    _onboardingData['ai_config'].addAll(config);
    notifyListeners();
  }

  // Navigation steps
  void nextStep() {
    if (_currentStep < 3) {
      _currentStep++;
      notifyListeners();
    }
  }

  void previousStep() {
    if (_currentStep > 0) {
      _currentStep--;
      notifyListeners();
    }
  }

  void goToStep(int step) {
    if (step >= 0 && step <= 3) {
      _currentStep = step;
      notifyListeners();
    }
  }

  // Save onboarding data to Firestore
  Future<bool> saveOnboardingData() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _workspaceId.isEmpty) {
        _errorMessage = 'Utilisateur non connecté ou workspace invalide';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Sauvegarde des données d'onboarding
      await FirebaseFirestore.instance
          .collection('workspaces')
          .doc(_workspaceId)
          .update({
        'onboarding_completed': true,
        'company_data': _onboardingData['company'],
        'integrations': _onboardingData['integrations'],
        'ai_config': _onboardingData['ai_config'],
      });

      // Traitement des invitations aux membres
      for (var member in _onboardingData['members']) {
        await FirebaseFirestore.instance
            .collection('invitations')
            .add({
          'workspaceId': _workspaceId,
          'email': member['email'],
          'role': member['role'],
          'invitedBy': user.uid,
          'status': 'pending',
          'created': FieldValue.serverTimestamp(),
        });
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Erreur: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}

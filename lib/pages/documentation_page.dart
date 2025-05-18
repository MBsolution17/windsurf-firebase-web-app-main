import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DocumentationPage extends StatefulWidget {
  const DocumentationPage({Key? key}) : super(key: key);

  @override
  _DocumentationPageState createState() => _DocumentationPageState();
}

class _DocumentationPageState extends State<DocumentationPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Simuler un temps de chargement
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _launchVideoUrl() async {
    final Uri url = Uri.parse('https://youtu.be/W0J9BUreLjI?si=AFTJq4KIqRinZ0PZ');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir la vidéo YouTube'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _downloadPDF() async {
    // Ici, vous pouvez ajouter la logique pour télécharger le PDF ou l'ouvrir dans un navigateur externe
    // Par exemple, en utilisant url_launcher pour ouvrir une URL où le PDF est hébergé
    // final Uri url = Uri.parse('https://votre-domaine.com/assets/documents/boundly-business-plan.pdf');
    // await launchUrl(url);
    
    // Comme alternative, affichez un message indiquant que le téléchargement est en cours
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Téléchargement du Business Plan en cours...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Boundly - Documentation'),
        backgroundColor: Colors.blue[700],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Business Plan'),
            Tab(text: 'Pitch Deck'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBusinessPlanTab(),
          _buildPitchDeckTab(),
        ],
      ),
    );
  }

  Widget _buildBusinessPlanTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Container(
          color: Colors.blue[50],
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.description, size: 32, color: Colors.blue),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Business Plan Boundly',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Créé par Mathieu Blanc - Avril 2025',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.description_outlined, size: 80, color: Colors.blue),
                const SizedBox(height: 20),
                const Text(
                  "Business Plan Complet",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Document détaillant la stratégie et le modèle économique de Boundly",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  onPressed: _downloadPDF,
                  icon: const Icon(Icons.download),
                  label: const Text('Télécharger le Business Plan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPitchDeckTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Colors.indigo[50],
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.slideshow, size: 32, color: Colors.indigo),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Pitch Deck Boundly',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Créé par Mathieu Blanc - Avril 2025',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Résumé du Pitch Deck présentant Boundly, l\'outil SaaS propulsé par l\'IA pour les PME.',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Le Problème'),
                _buildContentText(
                  '75% des PME françaises passent plus de 8 heures par semaine sur des tâches administratives.\n'
                  'Les principales tâches chronophages:\n'
                  '• Facturation: 35%\n'
                  '• Gestion des plannings: 25%\n'
                  '• Suivi des clients/CRM: 20%\n'
                  'Les solutions existantes sont soit trop complexes, soit trop coûteuses, soit limitées en fonctionnalités.'
                ),
                
                _buildSectionTitle('La Solution: Boundly'),
                _buildContentText(
                  'Un SaaS tout-en-un propulsé par l\'IA Orion qui:\n'
                  '• Automatise les tâches administratives\n'
                  '• Centralise les données et opérations\n'
                  '• Réduit de 80-90% le temps consacré à l\'administratif\n'
                  '• Offre une interface intuitive sans formation nécessaire'
                ),
                
                _buildSectionTitle('Fonctionnalités'),
                _buildContentText(
                  '• Gestion financière (factures, devis, paiements)\n'
                  '• CRM intégré avec analyses comportementales\n'
                  '• Planification et synchronisation des agendas\n'
                  '• Collaboration (chat, visio, partage de fichiers)\n'
                  '• Tableaux de bord personnalisés avec insights'
                ),
                
                _buildSectionTitle('Modèle Économique'),
                _buildContentText(
                  '• Abonnement unique: 300€/mois par entreprise\n'
                  '• Hébergement: 3-4€/mois par utilisateur\n'
                  '• Adaptations sur mesure: Sur devis'
                ),
                
                _buildSectionTitle('Marché'),
                _buildContentText(
                  '• 150 000 PME françaises de 1 à 50 employés\n'
                  '• Marché potentiel de 2 milliards €/an\n'
                  '• Secteurs cibles: Conseil, Commerce, Santé, Services\n'
                  '• 62% des PME européennes intéressées par l\'automatisation'
                ),
                
                _buildSectionTitle('Roadmap'),
                _buildContentText(
                  '• 2026: Bêta avec 10 PME pilotes, 100 abonnés (CA: 360 000€)\n'
                  '• 2027: 400 abonnés, version multilingue (CA: 1 440 000€)\n'
                  '• 2028: 1 000 abonnés, expansion européenne (CA: 3 600 000€)'
                ),
                
                _buildSectionTitle('À propos du fondateur'),
                _buildContentText(
                  'Mathieu Blanc, 20 ans, entrepreneur passionné avec expérience en:\n'
                  '• Développement IA et solutions complexes\n'
                  '• Applications mobiles (GenZave) publiées sur Android et iOS\n'
                  '• Marketing digital et aspects juridiques'
                ),
                
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _launchVideoUrl,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      children: const [
                        Icon(Icons.play_circle_filled, size: 48, color: Colors.red),
                        SizedBox(height: 8),
                        Text(
                          'Voir la vidéo de présentation',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Découvrez Boundly en action',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.indigo,
        ),
      ),
    );
  }

  Widget _buildContentText(String content) {
    return Text(
      content,
      style: const TextStyle(fontSize: 16, height: 1.5),
    );
  }
}
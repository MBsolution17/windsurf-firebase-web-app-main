import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class BusinessDocumentsPage extends StatefulWidget {
  const BusinessDocumentsPage({Key? key}) : super(key: key);

  @override
  _BusinessDocumentsPageState createState() => _BusinessDocumentsPageState();
}

class _BusinessDocumentsPageState extends State<BusinessDocumentsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentPage = 0;
  int _totalPages = 18; // Total des pages du business plan

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents Boundly'),
        backgroundColor: Colors.blue[700],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Business Plan'),
            Tab(text: 'Pitch Deck'),
          ],
          onTap: (index) {
            setState(() {
              // Réinitialiser la page courante lors du changement d'onglet
              _currentPage = 0;
              
              // Ajuster le nombre total de pages en fonction de l'onglet
              if (index == 0) {
                _totalPages = 18; // Business Plan a 18 pages
              } else {
                _totalPages = 5; // Pitch Deck a 5 pages (exemple)
              }
            });
          },
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBusinessPlanView(),
          _buildPitchDeckView(),
        ],
      ),
    );
  }

  Widget _buildBusinessPlanView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildPageContent(_currentPage),
              ],
            ),
          ),
        ),
        _buildNavigationBar(),
      ],
    );
  }

  Widget _buildPitchDeckView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPitchDeckHeader(),
                  const SizedBox(height: 24),
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
          ),
        ),
      ],
    );
  }

  Widget _buildPitchDeckHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        children: [
          const Text(
            'Pitch Deck Boundly',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Créé par Mathieu Blanc - Avril 2025',
            style: TextStyle(
              fontSize: 16,
              color: Colors.indigo.shade400,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.indigo.shade50),
            ),
            child: const Text(
              'Boundly est un SaaS propulsé par Orion, une IA codée sur mesure, conçu pour optimiser les opérations des PME grâce à l\'automatisation et la centralisation des données.',
              style: TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.indigo.shade700,
        ),
      ),
    );
  }

  Widget _buildContentText(String content) {
    return Text(
      content,
      style: const TextStyle(
        fontSize: 16,
        height: 1.5,
      ),
    );
  }

  Widget _buildPageContent(int page) {
    // Contenu du Business Plan basé sur la page actuelle
    switch (page) {
      case 0:
        return _buildBusinessPlanPage1();
      case 1:
        return _buildBusinessPlanPage2();
      case 2:
        return _buildBusinessPlanPage3();
      // Ajoutez d'autres cas pour les pages restantes
      default:
        return _buildPlaceholderPage(page + 1);
    }
  }

  Widget _buildBusinessPlanPage1() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Text(
            'Business Plan',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Text(
            'Boundly',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: const Text(
              'Boundly est un SaaS propulsé par Orion, une IA codée sur mesure, conçu pour optimiser les opérations des PME grâce à l\'automatisation et la centralisation des données.',
              style: TextStyle(
                fontSize: 18,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 40),
          const Text(
            '24/04/2025',
            style: TextStyle(
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'CRÉÉ PAR',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'MATHIEU BLANC',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 60),
          Image.asset(
            'assets/images/boundly_logo.png',
            width: 150,
            height: 150,
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessPlanPage2() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sommaire',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          _buildSommaireItem('01', 'RÉSUMÉ EXÉCUTIF', '01'),
          _buildSommaireItem('02', 'L\'IDÉE, LE PROJET', '02'),
          _buildSommaireItem('03', 'LE CRÉATEUR', '03'),
          _buildSommaireItem('04', 'L\'ÉTUDE DE MARCHÉ', '04-05-06'),
          _buildSommaireItem('05', 'LA STRATÉGIE', '07-08-09'),
          _buildSommaireItem('06', 'L\'ACTIVITÉ ET LES MOYENS', '10-11'),
          _buildSommaireItem('07', 'PARTIE JURIDIQUE', '12'),
          _buildSommaireItem('08', 'MA DEMANDE D\'ACCOMPAGNEMENT', '13-14'),
          _buildSommaireItem('09', 'ANNEXES', '15'),
          _buildSommaireItem('10', 'CONCLUSION', '16'),
        ],
      ),
    );
  }

  Widget _buildBusinessPlanPage3() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBusinessPlanPageHeader('01', 'RÉSUMÉ EXÉCUTIF'),
          const SizedBox(height: 24),
          const Text(
            'Je suis Mathieu Blanc, créateur de Boundly, une solution innovante qui aide les PME à optimiser leurs opérations grâce à l\'intelligence artificielle. Boundly repose sur deux piliers : Orion, une IA que j\'ai développée pour automatiser des tâches comme la facturation, la planification et l\'analyse de données, et une plateforme tout-en-un qui centralise la gestion des clients, la collaboration (chat, visio), et les insights pour des décisions éclairées. Intuitive et abordable (300 €/mois, hébergement à 3-4 €/mois par utilisateur), Boundly cible les 150 000 PME françaises de 1 à 50 employés, soit un marché de 2 milliards €/an, avec un focus sur des secteurs comme le conseil, le commerce, la santé et les services.',
            style: TextStyle(
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Objectifs stratégiques :',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildBulletPoint('2026 : Lancer une bêta avec 10 PME pilotes et atteindre 100 abonnés payants, générant un CA de 360 000 €.'),
          _buildBulletPoint('2027 : Atteindre 400 abonnés en France (CA : 1 440 000 €) et développer une version multilingue pour l\'expansion européenne.'),
          _buildBulletPoint('2028 : Atteindre 1 000 abonnés (CA : 3 600 000 €) et pénétrer les marchés allemand, espagnol et italien.'),
          const SizedBox(height: 24),
          const Text(
            'Mon modèle est ultra-lean : j\'ai tout codé seul, réduisant les coûts à l\'hébergement cloud et à quelques freelances (design, marketing). Ce business plan est destiné à la BPI pour demander un accompagnement non financier : conseils stratégiques, mise en réseau avec des associations de PME, outils/formations, et visibilité via des événements BPI. Mes coûts sont couverts par mon apport de 15 000 €. Avec cet accompagnement, Boundly vise à devenir un leader des solutions IA pour PME en France, puis en Europe, d\'ici 2028.',
            style: TextStyle(
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderPage(int pageNumber) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.description,
            size: 64,
            color: Colors.blue,
          ),
          const SizedBox(height: 24),
          Text(
            'Page $pageNumber du Business Plan',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Consultez le document complet dans les fichiers ou contactez-nous pour plus d\'informations.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessPlanPageHeader(String number, String title) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.shade700,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          '- $title',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSommaireItem(String number, String title, String pages) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              number,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
              ),
            ),
          ),
          Text(
            pages,
            style: const TextStyle(
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ElevatedButton(
            onPressed: _currentPage > 0
                ? () {
                    setState(() {
                      _currentPage--;
                    });
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Précédent'),
          ),
          Text(
            'Page ${_currentPage + 1} sur $_totalPages',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          ElevatedButton(
            onPressed: _currentPage < _totalPages - 1
                ? () {
                    setState(() {
                      _currentPage++;
                    });
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Suivant'),
          ),
        ],
      ),
    );
  }
}
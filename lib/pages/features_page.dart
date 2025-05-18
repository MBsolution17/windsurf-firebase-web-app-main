import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Page présentant les fonctionnalités de Boundly avec des couleurs plus vives
/// et une identité visuelle cohérente avec la landing page
class FeaturesPage extends StatefulWidget {
  const FeaturesPage({Key? key}) : super(key: key);

  @override
  State<FeaturesPage> createState() => _FeaturesPageState();
}

class _FeaturesPageState extends State<FeaturesPage> {
  final ScrollController _scrollController = ScrollController();
  double _backgroundOpacity = 0.6;
  bool _isScrolled = false;
  
  // Couleurs vives inspirées de la landing page
  final Color primaryBlue = Colors.blue.shade600; // Bleu principal
  final Color secondaryColor = Colors.teal.shade500; // Bleu-vert
  final Color accentColor = Colors.blue.shade400; // Bleu ciel
  final Color highlightColor = Colors.green.shade500; // Vert
  
  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final double offset = _scrollController.offset;
    final double newOpacity = 0.6 + (offset / 500) * 0.2;
    setState(() {
      _backgroundOpacity = newOpacity.clamp(0.6, 0.8);
      _isScrolled = offset > 50;
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Affiche un message indiquant "bientôt disponible"
  void _showComingSoonMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Les inscriptions seront ouvertes prochainement !'),
        backgroundColor: primaryBlue,
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  /// Navigation vers la page des tarifs
  void _navigateToPricingPage() {
    Navigator.pushNamed(context, '/pricing');
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(isMobile),
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.png',
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(_backgroundOpacity),
              colorBlendMode: BlendMode.darken,
            ),
          ),
          
          // Content
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.black.withOpacity(_isScrolled ? 0.7 : 0.0),
                elevation: _isScrolled ? 4 : 0,
                pinned: true,
                automaticallyImplyLeading: false,
                toolbarHeight: 0,
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHero(isMobile),
                    _buildMainFeatures(isMobile),
                    _buildAICapabilities(isMobile),
                    _buildDetailedFeatures(isMobile),
                    _buildSectorSolutions(isMobile),
                    _buildFeatureHighlights(isMobile), // Remplacé le composant de comparaison par des points forts
                    _buildCallToAction(isMobile),
                    _buildFooter(isMobile),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isMobile) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.black.withOpacity(_isScrolled ? 0.7 : 0.0),
      title: const Text(
        'Fonctionnalités',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
      ),
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        // Bouton Tarifs
        TextButton.icon(
          onPressed: _navigateToPricingPage,
          icon: const Icon(Icons.paid, color: Colors.white, size: 20),
          label: const Text(
            'Tarifs',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        
        // Bouton "Bientôt disponible"
        Container(
          margin: const EdgeInsets.only(right: 16),
          child: ElevatedButton.icon(
            onPressed: _showComingSoonMessage,
            icon: Icon(Icons.access_time, size: isMobile ? 14 : 18),
            label: Text(
              isMobile ? 'Bientôt' : 'Bientôt disponible', 
              style: TextStyle(fontSize: isMobile ? 12 : 14)
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 10 : 16, 
                vertical: isMobile ? 6 : 12
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              elevation: 4,
              shadowColor: primaryBlue.withOpacity(0.4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHero(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, isMobile ? 110 : 120, 20, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Badge
          _buildBadge(
            icon: Icons.star,
            label: 'FONCTIONNALITÉS COMPLÈTES',
          ),
          const SizedBox(height: 20),
          
          // Main title
          Text(
            'Transformez votre PME avec l\'IA Orion',
            style: TextStyle(
              fontSize: isMobile ? 26 : 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
              shadows: [
                const Shadow(
                  color: Colors.black,
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          
          // Subtitle
          Container(
            width: MediaQuery.of(context).size.width * 0.9,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primaryBlue.withOpacity(0.5)),
            ),
            child: Text(
              'Découvrez comment Boundly automatise et optimise toutes vos opérations administratives',
              style: TextStyle(
                fontSize: isMobile ? 14 : 16,
                color: Colors.white,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 30),
          
          // Stats
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 20,
            runSpacing: 20,
            children: [
              _buildStat('80-90%', 'Gain de temps'),
              _buildStat('300€', 'Prix fixe mensuel'),
              _buildStat('24/7', 'Support client'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: primaryBlue.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String label) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    final double size = isMobile ? 70 : 90;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            shape: BoxShape.circle,
            border: Border.all(color: primaryBlue, width: 2),
            boxShadow: [
              BoxShadow(
                color: primaryBlue.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: isMobile ? 16 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: isMobile ? 12 : 14,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
      ],
    );
  }
  
  Widget _buildMainFeatures(bool isMobile) {
    return _buildSection(
      isMobile: isMobile,
      icon: Icons.dashboard,
      title: 'Vue d\'ensemble',
      heading: 'Un SaaS conçu pour les PME de 1 à 50 employés',
      description: 'Boundly est un SaaS propulsé par Orion, une IA codée sur mesure, conçu pour optimiser les opérations des PME grâce à l\'automatisation et la centralisation des données. Notre plateforme tout-en-un vous permet de gérer l\'ensemble de vos opérations administratives, financières et relationnelles en un seul endroit.',
      content: GridView.count(
        crossAxisCount: isMobile ? 1 : (MediaQuery.of(context).size.width > 900 ? 4 : 2),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: isMobile ? 2.0 : 1.2,
        children: [
          _buildFeatureCard(
            icon: Icons.speed,
            title: 'Gain de temps',
            description: '80-90% de temps économisé sur les tâches administratives',
            color: primaryBlue,
          ),
          _buildFeatureCard(
            icon: Icons.payments,
            title: 'Tarification simple',
            description: '300€/mois tout inclus, peu importe le nombre d\'utilisateurs',
            color: secondaryColor,
          ),
          _buildFeatureCard(
            icon: Icons.psychology,
            title: 'IA Orion intégrée',
            description: 'IA avancée qui s\'adapte à votre secteur d\'activité',
            color: accentColor,
          ),
          _buildFeatureCard(
            icon: Icons.security,
            title: 'Sécurité maximale',
            description: 'Données cryptées et hébergées en France (RGPD)',
            color: highlightColor,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAICapabilities(bool isMobile) {
    return _buildSection(
      isMobile: isMobile,
      icon: Icons.smart_toy,
      title: 'IA Orion',
      heading: 'Une IA conçue spécifiquement pour les PME',
      description: 'Orion est notre intelligence artificielle propriétaire, développée spécifiquement pour comprendre et optimiser les processus des PME françaises. Contrairement aux IA génériques, Orion a été entraînée sur des données pertinentes pour votre secteur et s\'adapte en continu à vos besoins spécifiques.',
      content: Column(
        children: [
          _buildCapability(
            icon: Icons.auto_awesome,
            title: 'Automatisation intelligente',
            description: 'Orion identifie et automatise les tâches répétitives sans configuration complexe',
            color: primaryBlue,
          ),
          _buildCapability(
            icon: Icons.insights,
            title: 'Analyse prédictive',
            description: 'Prévisions financières et détection d\'opportunités commerciales basées sur vos données',
            color: secondaryColor,
          ),
          _buildCapability(
            icon: Icons.lightbulb,
            title: 'Assistance contextuelle',
            description: 'Suggestions et recommandations en temps réel basées sur votre activité',
            color: accentColor,
          ),
          _buildCapability(
            icon: Icons.sync,
            title: 'Apprentissage continu',
            description: 'Orion s\'améliore avec l\'usage et s\'adapte à vos processus spécifiques',
            color: highlightColor,
          ),
        ],
      ),
    );
  }
  
  Widget _buildCapability({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.2),
                  blurRadius: 5,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: isMobile ? 20 : 24),
          ),
          SizedBox(width: isMobile ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: isMobile ? 13 : 14,
                    color: Colors.white.withOpacity(0.8),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailedFeatures(bool isMobile) {
    return _buildSection(
      isMobile: isMobile,
      icon: Icons.category,
      title: 'Fonctionnalités principales',
      heading: 'Une suite complète d\'outils pour votre PME',
      description: 'Boundly centralise toutes les fonctionnalités dont vous avez besoin pour gérer efficacement votre entreprise.',
      content: Column(
        children: [
          _buildFeatureCategory(
            icon: Icons.receipt_long,
            title: 'Gestion financière',
            color: primaryBlue,
            features: [
              'Facturation automatisée avec relances intelligentes',
              'Devis assistés par IA avec suggestion de prix optimaux',
              'Suivi de trésorerie et prévisions à 6 mois',
              'Notes de frais simplifiées avec scan automatique',
            ],
          ),
          const SizedBox(height: 20),
          _buildFeatureCategory(
            icon: Icons.people,
            title: 'CRM et gestion client',
            color: secondaryColor,
            features: [
              'Profils client enrichis avec historique complet',
              'Relances optimisées au meilleur moment',
              'Segmentation intelligente automatique',
              'Détection d\'opportunités commerciales',
            ],
          ),
          const SizedBox(height: 20),
          _buildFeatureCategory(
            icon: Icons.calendar_month,
            title: 'Planification et gestion du temps',
            color: accentColor,
            features: [
              'Calendrier intelligent avec suggestions Orion',
              'Priorisation automatique des tâches',
              'Synchronisation multi-appareils',
              'Planification d\'équipe et coordination',
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildFeatureCategory({
    required IconData icon,
    required String title,
    required Color color,
    required List<String> features,
  }) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isMobile ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...features.map((feature) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle,
                  color: color,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    feature,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }
  
  Widget _buildSectorSolutions(bool isMobile) {
    return _buildSection(
      isMobile: isMobile,
      icon: Icons.business,
      title: 'Solutions par secteur',
      heading: 'Boundly s\'adapte à votre domaine d\'activité',
      description: 'Notre plateforme fournit des fonctionnalités dédiées à différents secteurs d\'activité.',
      content: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: primaryBlue.withOpacity(0.5)),
              ),
              child: TabBar(
                isScrollable: isMobile,
                indicator: BoxDecoration(
                  color: primaryBlue,
                  borderRadius: BorderRadius.circular(30),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                unselectedLabelColor: Colors.white.withOpacity(0.6),
                labelColor: Colors.white,
                tabs: const [
                  Tab(text: 'Conseil'),
                  Tab(text: 'Commerce'),
                  Tab(text: 'Santé'),
                  Tab(text: 'Services'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 300,
              child: TabBarView(
                children: [
                  _buildSectorContent(
                    title: 'Conseil et Freelances',
                    points: [
                      'Suivi précis du temps facturable par client et projet',
                      'Génération automatique de rapports d\'activité',
                      'Gestion de propositions commerciales',
                      'Facturation au forfait ou à l\'heure',
                      'Bibliothèque de connaissances interne',
                    ],
                    color: primaryBlue,
                    icon: Icons.business,
                  ),
                  _buildSectorContent(
                    title: 'Commerce et Distribution',
                    points: [
                      'Gestion des stocks et alertes de réapprovisionnement',
                      'Prévisions de ventes par saison et produit',
                      'Suivi des performances des points de vente',
                      'Programmes de fidélité et segmentation client',
                      'Intégration e-commerce et gestion omnicanale',
                    ],
                    color: accentColor,
                    icon: Icons.shopping_cart,
                  ),
                  _buildSectorContent(
                    title: 'Santé et Bien-être',
                    points: [
                      'Gestion des rendez-vous avec rappels automatiques',
                      'Suivi patient et historique des interventions',
                      'Facturation sécu et mutuelles simplifiée',
                      'Salle d\'attente virtuelle et formulaires numériques',
                      'Conformité RGPD et données médicales',
                    ],
                    color: secondaryColor,
                    icon: Icons.medical_services,
                  ),
                  _buildSectorContent(
                    title: 'Services aux entreprises',
                    points: [
                      'Gestion des contrats de service récurrents',
                      'Suivi des SLAs et des indicateurs de qualité',
                      'Planification d\'équipe et optimisation',
                      'Rapports clients automatisés',
                      'Portail client avec accès aux factures',
                    ],
                    color: highlightColor,
                    icon: Icons.miscellaneous_services,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSectorContent({
    required String title,
    required List<String> points,
    required Color color,
    required IconData icon,
  }) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isMobile ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: points.map((point) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: color,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        point,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }
  
  // Nouveau widget remplaçant la section de comparaison
  Widget _buildFeatureHighlights(bool isMobile) {
    return _buildSection(
      isMobile: isMobile,
      icon: Icons.stars,
      title: 'POINTS FORTS',
      heading: 'Ce qui fait la différence',
      description: 'Découvrez les atouts qui font de Boundly la solution idéale pour les PME modernes.',
      content: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primaryBlue.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: primaryBlue.withOpacity(0.2),
              blurRadius: 15,
              spreadRadius: 0,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHighlightItem(
              icon: Icons.psychology,
              title: 'IA dédiée aux PME françaises',
              description: 'Contrairement aux solutions génériques, Orion est entraînée spécifiquement pour comprendre les besoins des PME et le contexte français.',
              color: primaryBlue,
            ),
            const SizedBox(height: 20),
            _buildHighlightItem(
              icon: Icons.people,
              title: 'Utilisateurs illimités',
              description: 'Ajoutez autant d\'utilisateurs que nécessaire sans surcoût. Notre tarification transparente est basée sur l\'entreprise, pas sur le nombre d\'utilisateurs.',
              color: secondaryColor,
            ),
            const SizedBox(height: 20),
            _buildHighlightItem(
              icon: Icons.integration_instructions,
              title: 'Intégrations sur mesure',
              description: 'Boundly s\'adapte à vos outils existants grâce à nos services d\'intégration personnalisés, pour une transition fluide et sans rupture.',
              color: accentColor,
            ),
            const SizedBox(height: 20),
            _buildHighlightItem(
              icon: Icons.support_agent,
              title: 'Support francophone 24/7',
              description: 'Une équipe dédiée basée en France est disponible à tout moment pour vous accompagner et répondre à vos questions.',
              color: highlightColor,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHighlightItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.2),
                blurRadius: 5,
                spreadRadius: 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildCallToAction(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: isMobile ? 40 : 60, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            primaryBlue.withOpacity(0.3),
            secondaryColor.withOpacity(0.3),
          ],
        ),
        border: Border(
          top: BorderSide(color: primaryBlue.withOpacity(0.5), width: 1),
          bottom: BorderSide(color: primaryBlue.withOpacity(0.5), width: 1),
        ),
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              Text(
                'Prêt à transformer votre PME ?',
                style: TextStyle(
                  fontSize: isMobile ? 28 : 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryBlue.withOpacity(0.5)),
                ),
                child: Text(
                  'Rejoignez les PME qui utilisent déjà Boundly et économisez jusqu\'à 90% du temps consacré aux tâches administratives',
                  style: TextStyle(
                    fontSize: isMobile ? 15 : 18,
                    color: Colors.white,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _navigateToPricingPage,
                    icon: const Icon(Icons.paid, size: 20),
                    label: Text(
                      'Voir les tarifs', 
                      style: TextStyle(fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.grey[800],
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 20 : 30, 
                        vertical: isMobile ? 16 : 20
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                      shadowColor: Colors.black.withOpacity(0.3),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _showComingSoonMessage,
                    icon: const Icon(Icons.access_time, size: 20),
                    label: Text(
                      'Essai gratuit', 
                      style: TextStyle(fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 20 : 30, 
                        vertical: isMobile ? 16 : 20
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                      shadowColor: primaryBlue.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildFooter(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: isMobile ? 40 : 60, horizontal: 20),
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Column(
          children: [
            // Texte "Boundly" sans le logo à côté
            const Text(
              'Boundly',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '© 2025 Boundly. Tous droits réservés.',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required bool isMobile,
    required IconData icon,
    required String title,
    required String heading,
    required String description,
    required Widget content,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? 40 : 60, 
        horizontal: isMobile ? 16 : 20
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBadge(icon: icon, label: title.toUpperCase()),
              SizedBox(height: isMobile ? 16 : 24),
              Text(
                heading,
                style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                description,
                style: TextStyle(
                  fontSize: isMobile ? 14 : 16,
                  color: Colors.white,
                  height: 1.6,
                ),
              ),
              SizedBox(height: isMobile ? 24 : 30),
              content,
            ],
          ),
        ),
      ),
    );
  }
}
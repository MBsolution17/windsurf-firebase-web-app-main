import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget qui affiche la page de tarification de Boundly avec des couleurs plus vibrantes
/// et une identité visuelle cohérente avec la landing page
class PricingPage extends StatelessWidget {
  const PricingPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: _BackgroundContainer(
        child: _PricingPageContent(),
      ),
    );
  }

  /// Construit l'AppBar avec des actions spécifiques
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      title: const Text(
        'Nos Tarifs',
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
        Container(
          margin: const EdgeInsets.only(right: 16),
          child: ElevatedButton.icon(
            onPressed: () => _showComingSoonMessage(context),
            icon: Icon(Icons.access_time, size: isMobile ? 14 : 18),
            label: Text(
              isMobile ? 'Bientôt' : 'Bientôt disponible', 
              style: TextStyle(fontSize: isMobile ? 12 : 14)
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 10 : 16, 
                vertical: isMobile ? 6 : 12
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              elevation: 4,
              shadowColor: Colors.blue.shade600.withOpacity(0.4),
            ),
          ),
        ),
      ],
    );
  }

  /// Affiche un message indiquant que les inscriptions seront bientôt disponibles
  void _showComingSoonMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Les inscriptions seront ouvertes prochainement !'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 3),
      ),
    );
  }
}

/// Conteneur avec arrière-plan qui gère l'opacité lors du défilement
class _BackgroundContainer extends StatefulWidget {
  final Widget child;

  const _BackgroundContainer({required this.child});

  @override
  State<_BackgroundContainer> createState() => _BackgroundContainerState();
}

class _BackgroundContainerState extends State<_BackgroundContainer> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  double _backgroundOpacity = 0.6;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    
    _animationController.forward();
  }

  void _onScroll() {
    final double offset = _scrollController.offset;
    final double newOpacity = 0.6 + (offset / 500) * 0.2;
    final clampedOpacity = newOpacity.clamp(0.6, 0.8);
    
    setState(() {
      _backgroundOpacity = clampedOpacity;
      _isScrolled = offset > 50;
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/background.png',
            fit: BoxFit.cover,
            color: Colors.black.withOpacity(_backgroundOpacity),
            colorBlendMode: BlendMode.darken,
          ),
        ),
        Positioned.fill(
          child: CustomScrollView(
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
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Contenu principal de la page de fonctionnalités
class _PricingPageContent extends StatelessWidget {
  // Couleurs plus vibrantes inspirées de la landing page
  final Color primaryBlue = Colors.blue.shade600;
  final Color secondaryColor = Colors.teal.shade500;
  final Color accentColor = Colors.blue.shade400;
  final Color highlightColor = Colors.green.shade500;

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 600;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderSection(context, isMobile),
        _buildMainFeaturesCard(context, isMobile),
        _buildComparisonSection(context, isMobile),
        _buildAIPoweredSection(context, isMobile),
        _buildTargetIndustriesSection(context, isMobile),
        _buildFAQSection(context, isMobile),
        _buildContactSection(context, isMobile),
        _buildFooter(context),
      ],
    );
  }

  /// Section d'en-tête avec titre et sous-titre
  Widget _buildHeaderSection(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, isMobile ? 140 : 160, 20, 40),
      child: Column(
        children: [
          _LabelBadge(
            icon: Icons.business,
            label: 'SOLUTION COMPLÈTE POUR PME',
            darkBackground: true,
            color: primaryBlue,
          ),
          const SizedBox(height: 20),
          Text(
            'La plateforme tout-en-un propulsée par l\'IA',
            style: TextStyle(
              fontSize: isMobile ? 26 : 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            width: MediaQuery.of(context).size.width * 0.9,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: primaryBlue.withOpacity(0.5)),
            ),
            child: Text(
              'Réduisez jusqu\'à 90% du temps consacré aux tâches administratives grâce à Orion, notre IA dédiée aux PME',
              style: TextStyle(
                fontSize: isMobile ? 14 : 16,
                color: Colors.white,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 30),
          _buildCompactPricingBox(context, isMobile),
        ],
      ),
    );
  }
  
  /// Section tarification compacte, adaptée à la fois pour PC et mobile
  Widget _buildCompactPricingBox(BuildContext context, bool isMobile) {
    return Container(
      width: isMobile ? MediaQuery.of(context).size.width * 0.9 : 600,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 40, 
        vertical: isMobile ? 20 : 25
      ),
      decoration: BoxDecoration(
        color: primaryBlue.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryBlue.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: isMobile 
          ? _buildMobilePricingContent() 
          : _buildDesktopPricingContent(),
    );
  }
  
  /// Contenu de tarification pour mobile (disposition verticale)
  Widget _buildMobilePricingContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'TARIFICATION SIMPLE',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: primaryBlue,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '300',
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              '€',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 4),
            Text(
              '/mois',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Text(
          'Prix fixe par entreprise, utilisateurs illimités',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Container(
            height: 1,
            color: primaryBlue.withOpacity(0.3),
          ),
        ),
        Text(
          'Hébergement : 3-4€/mois par utilisateur',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  /// Contenu de tarification pour desktop (disposition horizontale)
  Widget _buildDesktopPricingContent() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TARIFICATION SIMPLE',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: primaryBlue,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Prix fixe par entreprise, utilisateurs illimités',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Hébergement : 3-4€/mois par utilisateur',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '300',
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              '€',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 4),
            Text(
              '/mois',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Carte des fonctionnalités principales
  Widget _buildMainFeaturesCard(BuildContext context, bool isMobile) {
    return Center(
      child: Container(
        width: isMobile ? double.infinity : 800,
        margin: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 0),
        padding: EdgeInsets.all(isMobile ? 20 : 30),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              primaryBlue.withOpacity(0.15),
              secondaryColor.withOpacity(0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: primaryBlue.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: primaryBlue.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(0.7),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: primaryBlue.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                'TOUTES LES FONCTIONNALITÉS INCLUSES',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 30),
            
            Text(
              'Une plateforme unifiée pour toutes vos opérations',
              style: TextStyle(
                fontSize: isMobile ? 16 : 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            Column(
              children: [
                _FeatureItem(
                  feature: 'IA Orion complète pour l\'automatisation des tâches',
                  description: 'Réduisez jusqu\'à 90% du temps consacré aux tâches administratives',
                  color: primaryBlue
                ),
                _FeatureItem(
                  feature: 'Module financier intégré',
                  description: 'Gérez vos factures, devis et paiements en un seul endroit',
                  color: primaryBlue
                ),
                _FeatureItem(
                  feature: 'CRM intelligent',
                  description: 'Bénéficiez d\'analyses comportementales pour optimiser vos relations clients',
                  color: primaryBlue
                ),
                _FeatureItem(
                  feature: 'Planification intelligente',
                  description: 'Synchronisez tous vos agendas et optimisez votre temps',
                  color: primaryBlue
                ),
                _FeatureItem(
                  feature: "Collaboration d'équipe",
                  description: 'Chat, visio et réseau social d\'entreprise intégrés',
                  color: primaryBlue
                ),
                _FeatureItem(
                  feature: 'Tableaux de bord personnalisables',
                  description: 'Visualisez vos données clés et prenez des décisions éclairées',
                  color: primaryBlue
                ),
                _FeatureItem(
                  feature: 'Support 24/7',
                  description: 'Une équipe dédiée pour répondre à toutes vos questions',
                  color: primaryBlue
                ),
                _FeatureItem(
                  feature: 'Utilisateurs illimités',
                  description: 'Ajoutez autant d\'utilisateurs que nécessaire sans surcoût',
                  color: primaryBlue
                ),
                _FeatureItem(
                  feature: 'Adaptations sur mesure',
                  description: 'Intégrations avec vos outils existants et fonctionnalités personnalisées',
                  color: primaryBlue
                ),
              ],
            ),
            
            const SizedBox(height: 30),
            
            _ActionButton(
              label: 'Essai gratuit bientôt disponible',
              icon: Icons.access_time,
              isMobile: isMobile,
              onPressed: () => _showComingSoonMessage(context),
              color: primaryBlue,
            ),
          ],
        ),
      ),
    );
  }

  /// Section de comparaison avec les concurrents - Nouvelle version responsive
  Widget _buildComparisonSection(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: isMobile ? 40 : 60),
      padding: EdgeInsets.symmetric(vertical: 40, horizontal: isMobile ? 16 : 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            primaryBlue.withOpacity(0.2),
            Colors.black.withOpacity(0.3),
          ],
        ),
        border: Border(
          top: BorderSide(color: primaryBlue.withOpacity(0.5), width: 1),
          bottom: BorderSide(color: primaryBlue.withOpacity(0.5), width: 1),
        ),
      ),
      child: Column(
        children: [
          _LabelBadge(
            icon: Icons.compare_arrows,
            label: 'POURQUOI CHOISIR BOUNDLY',
            darkBackground: true,
            color: primaryBlue,
          ),
          const SizedBox(height: 24),
          Text(
            'Boundly vs. Les autres solutions',
            style: TextStyle(
              fontSize: isMobile ? 22 : 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Découvrez ce qui différencie Boundly des autres solutions du marché',
            style: TextStyle(
              fontSize: isMobile ? 14 : 16,
              color: Colors.white.withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isMobile ? 30 : 40),
          
          // Conditionnellement afficher la table de comparaison en fonction de la taille de l'écran
          if (!isMobile)
            _buildDesktopComparisonTable()
          else
            _buildMobileComparisonTable(),
        ],
      ),
    );
  }

  /// Version mobile du tableau de comparaison avec cartes par fonctionnalité
  Widget _buildMobileComparisonTable() {
    return Column(
      children: [
        _buildFeatureComparisonCard(
          featureName: 'IA dédiée aux PME',
          products: {
            'Boundly': true,
            'Zoho': false,
            'HubSpot': false,
            'Monday': false,
            'Axonaut': false,
          },
        ),
        _buildFeatureComparisonCard(
          featureName: 'Automatisation complète',
          products: {
            'Boundly': true,
            'Zoho': false,
            'HubSpot': false,
            'Monday': false,
            'Axonaut': false,
          },
        ),
        _buildFeatureComparisonCard(
          featureName: 'Facturation automatisée',
          products: {
            'Boundly': true,
            'Zoho': true,
            'HubSpot': false,
            'Monday': false,
            'Axonaut': true,
          },
        ),
        _buildFeatureComparisonCard(
          featureName: 'CRM intelligent',
          products: {
            'Boundly': true,
            'Zoho': true,
            'HubSpot': true,
            'Monday': false,
            'Axonaut': false,
          },
        ),
        _buildFeatureComparisonCard(
          featureName: 'Interface intuitive',
          products: {
            'Boundly': true,
            'Zoho': false,
            'HubSpot': false,
            'Monday': true,
            'Axonaut': true,
          },
        ),
        _buildFeatureComparisonCard(
          featureName: 'Support 24/7',
          products: {
            'Boundly': true,
            'Zoho': false,
            'HubSpot': false,
            'Monday': false,
            'Axonaut': false,
          },
        ),
        _buildFeatureComparisonCard(
          featureName: 'Utilisateurs illimités',
          products: {
            'Boundly': true,
            'Zoho': false,
            'HubSpot': false,
            'Monday': false,
            'Axonaut': false,
          },
        ),
        _buildFeatureComparisonCard(
          featureName: 'Planification intelligente',
          products: {
            'Boundly': true,
            'Zoho': true,
            'HubSpot': true,
            'Monday': true,
            'Axonaut': false,
          },
        ),
      ],
    );
  }

  /// Carte pour une fonctionnalité comparée entre produits
  Widget _buildFeatureComparisonCard({
    required String featureName,
    required Map<String, bool> products,
  }) {
    final checkIcon = Icon(Icons.check_circle, color: Colors.green.shade400, size: 18);
    final crossIcon = Icon(Icons.cancel, color: Colors.red.shade400, size: 18);
    
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryBlue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre de la fonctionnalité
          Text(
            featureName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          
          // Grille de comparaison compact
          GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.0,
            children: products.entries.map((entry) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icône de présence ou non de la fonctionnalité
                  entry.value ? checkIcon : crossIcon,
                  const SizedBox(height: 4),
                  // Nom du produit
                  Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Table de comparaison pour l'affichage desktop
  Widget _buildDesktopComparisonTable() {
    // Définition des icônes et couleurs pour l'état des fonctionnalités
    final checkIcon = Icon(Icons.check_circle, color: Colors.green.shade400, size: 24);
    final crossIcon = Icon(Icons.cancel, color: Colors.red.shade400, size: 24);
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryBlue.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          dataRowHeight: 60,
          headingRowHeight: 70,
          headingRowColor: MaterialStateProperty.all(primaryBlue.withOpacity(0.3)),
          headingTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          dataTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
          columns: const [
            DataColumn(
              label: Text('Fonctionnalités', style: TextStyle(fontSize: 16)),
            ),
            DataColumn(
              label: Padding(
                padding: EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Boundly', style: TextStyle(fontSize: 16)),
                    Text('Notre solution', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ),
            DataColumn(
              label: Padding(
                padding: EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Zoho', style: TextStyle(fontSize: 16)),
                    Text('Concurrent', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ),
            DataColumn(
              label: Padding(
                padding: EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('HubSpot', style: TextStyle(fontSize: 16)),
                    Text('Concurrent', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ),
            DataColumn(
              label: Padding(
                padding: EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Monday', style: TextStyle(fontSize: 16)),
                    Text('Concurrent', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ),
            DataColumn(
              label: Padding(
                padding: EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Axonaut', style: TextStyle(fontSize: 16)),
                    Text('Concurrent', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ),
          ],
          rows: [
            // IA dédiée aux PME
            DataRow(
              color: MaterialStateProperty.all(Colors.black.withOpacity(0.1)),
              cells: [
                DataCell(Text('IA dédiée aux PME', style: TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
              ],
            ),
            // Automatisation administratives
            DataRow(
              cells: [
                DataCell(Text('Automatisation complète')),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
              ],
            ),
            // Facturation automatisée
            DataRow(
              color: MaterialStateProperty.all(Colors.black.withOpacity(0.1)),
              cells: [
                DataCell(Text('Facturation automatisée')),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: checkIcon)),
              ],
            ),
            // CRM intelligent
            DataRow(
              cells: [
                DataCell(Text('CRM intelligent')),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
              ],
            ),
            // Interface intuitive
            DataRow(
              color: MaterialStateProperty.all(Colors.black.withOpacity(0.1)),
              cells: [
                DataCell(Text('Interface intuitive')),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: checkIcon)),
              ],
            ),
            // Support 24/7
            DataRow(
              cells: [
                DataCell(Text('Support 24/7')),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
              ],
            ),
            // Utilisateurs illimités
            DataRow(
              color: MaterialStateProperty.all(Colors.black.withOpacity(0.1)),
              cells: [
                DataCell(Text('Utilisateurs illimités')),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
                DataCell(Center(child: crossIcon)),
              ],
            ),
            // Planification intelligente
            DataRow(
              cells: [
                DataCell(Text('Planification intelligente')),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: checkIcon)),
                DataCell(Center(child: crossIcon)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Section sur l'IA Orion
  Widget _buildAIPoweredSection(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: isMobile ? 40 : 60),
      padding: EdgeInsets.symmetric(vertical: 40, horizontal: isMobile ? 16 : 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            secondaryColor.withOpacity(0.2),
            Colors.black.withOpacity(0.3),
          ],
        ),
        border: Border(
          top: BorderSide(color: secondaryColor.withOpacity(0.5), width: 1),
          bottom: BorderSide(color: secondaryColor.withOpacity(0.5), width: 1),
        ),
      ),
      child: Column(
        children: [
          _LabelBadge(
            icon: Icons.smart_toy,
            label: 'ORION: NOTRE IA DÉDIÉE',
            darkBackground: true,
            color: secondaryColor,
          ),
          const SizedBox(height: 24),
          Text(
            'Une IA conçue spécifiquement pour les PME',
            style: TextStyle(
              fontSize: isMobile ? 22 : 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Orion est une IA codée sur mesure qui automatise vos opérations et vous propose des actions intelligentes basées sur vos données',
            style: TextStyle(
              fontSize: isMobile ? 14 : 16,
              color: Colors.white.withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isMobile ? 30 : 40),
          
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              _AIFeatureCard(
                icon: Icons.receipt_long,
                title: 'Facturation automatisée',
                description: 'Génération et envoi de factures à partir de vos données client et de vos modèles personnalisés',
                color: secondaryColor,
              ),
              _AIFeatureCard(
                icon: Icons.schedule,
                title: 'Planification intelligente',
                description: 'Optimisation de vos plannings en fonction des priorités, des ressources et des contraintes',
                color: secondaryColor,
              ),
              _AIFeatureCard(
                icon: Icons.people,
                title: 'Gestion client prédictive',
                description: 'Suggestions de relances basées sur l\'analyse comportementale de vos clients',
                color: secondaryColor,
              ),
              _AIFeatureCard(
                icon: Icons.insights,
                title: 'Analyses avancées',
                description: 'Tableaux de bord personnalisés qui mettent en évidence les tendances et opportunités',
                color: secondaryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Section des industries cibles
  Widget _buildTargetIndustriesSection(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 40, horizontal: isMobile ? 16 : 40),
      child: Column(
        children: [
          _LabelBadge(
            icon: Icons.category,
            label: 'ADAPTÉ À VOTRE SECTEUR',
            darkBackground: true,
            color: accentColor,
          ),
          const SizedBox(height: 24),
          Text(
            'Une solution sur mesure pour votre industrie',
            style: TextStyle(
              fontSize: isMobile ? 22 : 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Boundly s\'adapte aux besoins spécifiques de votre secteur d\'activité',
            style: TextStyle(
              fontSize: isMobile ? 14 : 16,
              color: Colors.white.withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isMobile ? 30 : 40),
          
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              _IndustryCard(
                icon: Icons.business_center,
                title: 'Cabinets de conseil',
                description: 'Gestion de clients et de projets, suivi du temps, facturation automatisée',
                color: accentColor,
              ),
              _IndustryCard(
                icon: Icons.shopping_cart,
                title: 'Commerce',
                description: 'Centralisation des ventes, gestion des stocks, fidélisation client',
                color: accentColor,
              ),
              _IndustryCard(
                icon: Icons.local_hospital,
                title: 'Santé',
                description: 'Planification des rendez-vous, gestion des dossiers patients, facturation',
                color: accentColor,
              ),
              _IndustryCard(
                icon: Icons.miscellaneous_services,
                title: 'Services',
                description: 'Automatisation administrative, gestion des interventions, suivi client',
                color: accentColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Section FAQ avec questions et réponses
  Widget _buildFAQSection(BuildContext context, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? 40 : 60, 
        horizontal: isMobile ? 16 : 24
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LabelBadge(
            icon: Icons.help,
            label: 'QUESTIONS FRÉQUENTES',
            darkBackground: true,
            color: primaryBlue,
          ),
          const SizedBox(height: 24),
          Text(
            'Tout ce que vous devez savoir sur Boundly',
            style: TextStyle(
              fontSize: isMobile ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          _FAQItem(
            question: 'Comment Boundly se différencie des autres solutions ?',
            answer: "Boundly se distingue par son IA Orion codée sur mesure qui automatise les tâches administratives, son interface intuitive qui ne nécessite pas de formation, et son modèle transparent permettant d'avoir des utilisateurs illimités. Notre solution réduit jusqu'à 90% du temps consacré aux tâches administratives.",
            color: primaryBlue,
          ),
          _FAQItem(
            question: 'Est-ce que Boundly est adapté à mon secteur d\'activité ?',
            answer: "Oui, Boundly est conçu pour s'adapter à divers secteurs d'activité, notamment le conseil, le commerce, la santé et les services. Notre IA Orion peut être personnalisée pour répondre aux besoins spécifiques de votre industrie, qu'il s'agisse de gestion de projets, de suivi client ou de facturation.",
            color: primaryBlue,
          ),
          _FAQItem(
            question: 'Est-ce difficile d\'implémenter Boundly dans mon entreprise ?',
            answer: "Non, Boundly a été conçu pour être simple à utiliser. Notre interface intuitive permet une prise en main rapide, sans formation technique requise. De plus, notre équipe vous accompagne dans l'implémentation et l'intégration avec vos outils existants pour assurer une transition en douceur.",
            color: primaryBlue,
          ),
          _FAQItem(
            question: 'Quelles sont les capacités de l\'IA Orion ?',
            answer: "Orion peut automatiser une large gamme de tâches administratives, comme la facturation, la planification et les relances clients. Elle analyse vos données pour vous suggérer des actions pertinentes et personnalisées. Contrairement aux IA génériques, Orion est spécifiquement conçue pour les opérations des PME, ce qui la rend plus précise et efficace dans ce contexte.",
            color: primaryBlue,
          ),
          _FAQItem(
            question: 'Boundly est-il conforme au RGPD ?',
            answer: 'Oui, Boundly est entièrement conforme au RGPD. Vos données sont chiffrées et stockées de manière sécurisée en Europe. Nous vous donnons un contrôle total sur vos données, avec la possibilité de les exporter ou de les supprimer à tout moment.',
            color: primaryBlue,
          ),
          _FAQItem(
            question: 'Comment fonctionne le support client ?',
            answer: "Notre support client est disponible 24/7 pour répondre à toutes vos questions. Vous pouvez nous contacter par chat, email ou téléphone. Nous proposons également des webinaires et des tutoriels pour vous aider à tirer le meilleur parti de Boundly.",
            color: primaryBlue,
          ),
          _FAQItem(
            question: 'Puis-je intégrer Boundly à mes outils existants ?',
            answer: "Oui, Boundly peut s'intégrer à vos outils existants grâce à nos options d'adaptation sur mesure. Que vous utilisiez des logiciels de comptabilité, des CRM ou d'autres outils spécifiques à votre industrie, nous pouvons créer des intégrations personnalisées pour répondre à vos besoins.",
            color: primaryBlue,
          ),
        ],
      ),
    );
  }

  /// Section de contact
  Widget _buildContactSection(BuildContext context, bool isMobile) {
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
                  fontSize: isMobile ? 24 : 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Contactez-nous pour découvrir comment Boundly peut répondre aux besoins spécifiques de votre entreprise',
                style: TextStyle(
                  fontSize: isMobile ? 16 : 18,
                  color: Colors.white.withOpacity(0.9),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, '/contact_landing');
                },
                icon: const Icon(Icons.send),
                label: const Text('Contactez-nous'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                  shadowColor: Colors.black.withOpacity(0.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pied de page
  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Column(
          children: [
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

  /// Affiche un message pour les fonctionnalités à venir
  void _showComingSoonMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Les inscriptions seront ouvertes prochainement !'),
        backgroundColor: primaryBlue,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// Composant pour afficher une caractéristique
class _FeatureItem extends StatelessWidget {
  final String feature;
  final String description;
  final Color color;
  
  const _FeatureItem({required this.feature, required this.description, required this.color});
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Badges avec icône et texte
class _LabelBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool darkBackground;
  final Color color;
  
  const _LabelBadge({
    required this.icon,
    required this.label,
    this.darkBackground = false,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: darkBackground 
            ? Colors.black.withOpacity(0.6)
            : color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 5,
            spreadRadius: 0,
          ),
        ],
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
}

/// Bouton d'action avec icône
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isMobile;
  final VoidCallback onPressed;
  final Color color;
  
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isMobile,
    required this.onPressed,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue.shade700,
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 20 : 30, 
          vertical: isMobile ? 12 : 16
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        elevation: 4,
        shadowColor: color.withOpacity(0.3),
      ),
    );
  }
}

/// Cartes de comparaison pour la vue mobile
class _ComparisonCard extends StatelessWidget {
  final String product;
  final String description;
  final Color color;
  final bool isRecommended;
  
  const _ComparisonCard({
    required this.product,
    required this.description,
    required this.color,
    required this.isRecommended,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRecommended ? color.withOpacity(0.3) : Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRecommended ? color.withOpacity(0.7) : color.withOpacity(0.3),
          width: isRecommended ? 2 : 1,
        ),
        boxShadow: isRecommended ? [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 5),
          ),
        ] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                product,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (isRecommended)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 5,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: const Text(
                    'Recommandé',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Composant pour chaque élément de FAQ
class _FAQItem extends StatelessWidget {
  final String question;
  final String answer;
  final Color color;
  
  const _FAQItem({
    required this.question,
    required this.answer,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        iconColor: color,
        collapsedIconColor: Colors.white,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              answer,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte pour les fonctionnalités de l'IA
class _AIFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  
  const _AIFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
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
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Carte pour les industries cibles
class _IndustryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  
  const _IndustryCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
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
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
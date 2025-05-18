import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';

/// Service pour la gestion des URL
class UrlService {
  /// Lance une URL externe
  static Future<void> launchExternalUrl(BuildContext context, String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Impossible d'ouvrir $urlString"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de l'ouverture de $urlString: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Affiche un message indiquant que la fonctionnalité sera disponible prochainement
  static void showComingSoonMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Les inscriptions seront ouvertes prochainement !"),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 3),
      ),
    );
  }
}

/// Thème et styles communs de l'application avec une palette plus vibrante
class AppStyles {
  // Couleurs principales inspirées de la landing page
  static final Color primaryColor = Colors.blue.shade600;
  static final Color secondaryColor = Colors.teal.shade500; 
  static final Color accentColor = Colors.blue.shade400;
  static final Color highlightColor = Colors.green.shade500;
  
  // Couleurs de fond
  static final Color backgroundOverlay = Colors.black;
  
  // Decorations
  static BoxDecoration transparentButtonDecoration = BoxDecoration(
    color: Colors.white.withOpacity(0.2),
    borderRadius: BorderRadius.circular(8),
  );
  
  static BoxDecoration badgeDecoration({bool darkBackground = false}) => BoxDecoration(
    color: darkBackground ? Colors.black.withOpacity(0.5) : primaryColor.withOpacity(0.3),
    borderRadius: BorderRadius.circular(30),
    border: Border.all(color: primaryColor.withOpacity(0.5)),
    boxShadow: [
      BoxShadow(
        color: primaryColor.withOpacity(0.2),
        blurRadius: 6,
        spreadRadius: 0,
      ),
    ],
  );
  
  static BoxDecoration cardDecoration({double opacity = 0.15}) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        primaryColor.withOpacity(opacity),
        Colors.black.withOpacity(opacity + 0.1),
      ],
    ),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: primaryColor.withOpacity(0.3), width: 1),
    boxShadow: [
      BoxShadow(
        color: primaryColor.withOpacity(0.1),
        blurRadius: 10,
        spreadRadius: 0,
        offset: const Offset(0, 5),
      ),
    ],
  );
  
  // Styles de texte
  static const TextStyle titleStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.bold,
    fontSize: 22,
  );
  
  static TextStyle headingStyle(bool isMobile) => TextStyle(
    fontSize: isMobile ? 24 : 36,
    fontWeight: FontWeight.bold,
    color: Colors.white,
    height: 1.2,
    shadows: const [
      Shadow(
        color: Colors.black,
        blurRadius: 10,
        offset: Offset(0, 2),
      ),
    ],
  );
  
  static TextStyle bodyStyle(bool isMobile) => TextStyle(
    fontSize: isMobile ? 15 : 18,
    color: Colors.white,
    height: 1.5,
  );
  
  // Styles de bouton
  static ButtonStyle primaryButtonStyle(bool isMobile) => ElevatedButton.styleFrom(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
    padding: EdgeInsets.symmetric(
      horizontal: isMobile ? 10 : 16,
      vertical: isMobile ? 6 : 12,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    elevation: 4,
    shadowColor: primaryColor.withOpacity(0.4),
  );
  
  static ButtonStyle outlineButtonStyle(bool isMobile) => OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    side: BorderSide(color: primaryColor, width: 2),
    padding: EdgeInsets.symmetric(
      horizontal: isMobile ? 10 : 16,
      vertical: isMobile ? 6 : 12,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
  );
}

/// Widget principal pour la page À propos
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        if (authService.isAuthenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacementNamed(context, '/dashboard');
          });
          return const SizedBox.shrink(); // Placeholder pendant la redirection
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: _buildAppBar(context),
          body: const _BackgroundContainer(
            child: _AboutContent(),
          ),
        );
      },
    );
  }

  /// Construit l'AppBar avec des actions spécifiques
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 768;
    
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      title: const Text(
        'À propos',
        style: AppStyles.titleStyle,
      ),
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: AppStyles.transparentButtonDecoration,
          child: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          child: ElevatedButton.icon(
            onPressed: () => UrlService.showComingSoonMessage(context),
            icon: Icon(Icons.access_time, size: isMobile ? 14 : 18),
            label: Text(
              isMobile ? 'Bientôt' : 'Bientôt disponible',
              style: TextStyle(fontSize: isMobile ? 12 : 14),
            ),
            style: AppStyles.primaryButtonStyle(isMobile),
          ),
        ),
      ],
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
  double _backgroundOpacity = 0.3;
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
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
    final double newOpacity = 0.3 + (offset / 300) * 0.45;
    final clampedOpacity = newOpacity.clamp(0.3, 0.75);
    setState(() {
      _isScrolled = _scrollController.offset > 80;
      _backgroundOpacity = clampedOpacity;
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

/// Contenu principal de la page À propos
class _AboutContent extends StatelessWidget {
  const _AboutContent();
  
  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 768;
    
    return Column(
      children: [
        _buildHeroSection(context, isMobile),
        _buildMissionSection(context, isMobile),
        _buildFounderSection(context, isMobile),
        _buildVisionSection(context, isMobile),
        _buildFooter(context, isMobile),
      ],
    );
  }

  /// Section héro avec titre principal
  Widget _buildHeroSection(BuildContext context, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? 100 : 120,
        horizontal: isMobile ? 20 : 40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: AppStyles.badgeDecoration(),
            child: const Text(
              'À PROPOS DE BOUNDLY',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Donnez du pouvoir aux PME grâce à des solutions basées sur l\'IA',
            style: AppStyles.headingStyle(isMobile),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 800),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppStyles.primaryColor.withOpacity(0.5)),
            ),
            child: Text(
              "Boundly est une plateforme SaaS propulsée par l'IA Orion, conçue pour automatiser et optimiser les opérations des petites et moyennes entreprises.",
              style: AppStyles.bodyStyle(isMobile),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// Section mission
  Widget _buildMissionSection(BuildContext context, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? 40 : 80,
        horizontal: isMobile ? 16 : 80,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppStyles.primaryColor.withOpacity(0.2),
            Colors.black.withOpacity(0.3),
          ],
        ),
        border: Border(
          top: BorderSide(color: AppStyles.primaryColor.withOpacity(0.5), width: 1),
          bottom: BorderSide(color: AppStyles.primaryColor.withOpacity(0.5), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _SectionHeader(
            title: 'NOTRE MISSION',
            icon: Icons.lightbulb,
          ),
          const SizedBox(height: 24),
          Text(
            "Transformer les PME grâce à l'IA",
            style: AppStyles.headingStyle(isMobile),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 700),
            child: Text(
              "Nous croyons que chaque PME mérite des outils puissants pour rivaliser avec les grandes entreprises. Notre mission est de fournir une solution tout-en-un qui automatise les tâches administratives, centralise les données et offre des insights exploitables grâce à l'IA Orion.",
              style: AppStyles.bodyStyle(isMobile),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// Section fondateur
  Widget _buildFounderSection(BuildContext context, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? 40 : 80,
        horizontal: isMobile ? 20 : 80,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(color: AppStyles.primaryColor.withOpacity(0.5), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _SectionHeader(
            title: 'LE FONDATEUR',
            icon: Icons.person,
          ),
          const SizedBox(height: 24),
          _FounderProfile(isMobile: isMobile),
        ],
      ),
    );
  }

  /// Section vision
  Widget _buildVisionSection(BuildContext context, bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? 40 : 80,
        horizontal: isMobile ? 16 : 80,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppStyles.secondaryColor.withOpacity(0.2),
            Colors.black.withOpacity(0.3),
          ],
        ),
        border: Border(
          bottom: BorderSide(color: AppStyles.primaryColor.withOpacity(0.5), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _SectionHeader(
            title: 'NOTRE VISION',
            icon: Icons.rocket_launch,
          ),
          const SizedBox(height: 24),
          Text(
            "Un avenir où les PME prospèrent grâce à l'IA",
            style: AppStyles.headingStyle(isMobile),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 700),
            child: Text(
              "Nous visons à devenir le partenaire de confiance des PME en Europe, en offrant une plateforme qui évolue avec leurs besoins. D'ici 2028, nous ambitionnons de servir 1 000 entreprises avec des solutions IA sur mesure.",
              style: AppStyles.bodyStyle(isMobile),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 40),
          
          if (!isMobile)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _VisionCard(
                    icon: Icons.trending_up,
                    title: 'Croissance',
                    content: '100 clients en 2026, 400 en 2027, et 1 000 en 2028.',
                    isMobile: isMobile,
                    color: AppStyles.primaryColor,
                  ),
                ),
                Expanded(
                  child: _VisionCard(
                    icon: Icons.euro,
                    title: 'Accessibilité',
                    content: 'Tarification simple à 300€/mois, tout inclus, pour toutes les PME.',
                    isMobile: isMobile,
                    onTap: () => Navigator.pushNamed(context, '/pricing'),
                    showArrow: true,
                    color: AppStyles.secondaryColor,
                  ),
                ),
                Expanded(
                  child: _VisionCard(
                    icon: Icons.language,
                    title: 'Expansion',
                    content: 'Déploiement en Europe pour répondre aux besoins des PME internationales.',
                    isMobile: isMobile,
                    color: AppStyles.accentColor,
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                _VisionCard(
                  icon: Icons.trending_up,
                  title: 'Croissance',
                  content: '100 clients en 2026, 400 en 2027, et 1 000 en 2028.',
                  isMobile: isMobile,
                  color: AppStyles.primaryColor,
                ),
                _VisionCard(
                  icon: Icons.euro,
                  title: 'Accessibilité',
                  content: 'Tarification simple à 300€/mois, tout inclus, pour toutes les PME.',
                  isMobile: isMobile,
                  onTap: () => Navigator.pushNamed(context, '/pricing'),
                  showArrow: true,
                  color: AppStyles.secondaryColor,
                ),
                _VisionCard(
                  icon: Icons.language,
                  title: 'Expansion',
                  content: 'Déploiement en Europe pour répondre aux besoins des PME internationales.',
                  isMobile: isMobile,
                  color: AppStyles.accentColor,
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Section pied de page
  Widget _buildFooter(BuildContext context, bool isMobile) {
    return _Footer(isMobile: isMobile);
  }
}

/// Profil du fondateur avec style et layout améliorés
class _FounderProfile extends StatelessWidget {
  final bool isMobile;
  
  const _FounderProfile({required this.isMobile});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 20 : 40),
      decoration: AppStyles.cardDecoration(opacity: 0.3),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo carrée à gauche avec effet d'ombre amélioré
              Container(
                width: isMobile ? 120 : 180,
                height: isMobile ? 120 : 180,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: AppStyles.primaryColor.withOpacity(0.5),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                  image: const DecorationImage(
                    image: AssetImage('assets/images/profil.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Informations à droite de la photo
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mathieu Blanc',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppStyles.primaryColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: AppStyles.primaryColor.withOpacity(0.5)),
                      ),
                      child: Text(
                        'Fondateur & Développeur',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _SocialIcon(
                          icon: Icons.email,
                          onTap: () => UrlService.launchExternalUrl(context, 'mailto:mathieu.blanc@boundly.com'),
                          color: AppStyles.primaryColor,
                        ),
                        const SizedBox(width: 12),
                        _SocialIcon(
                          icon: Icons.language,
                          onTap: () => UrlService.launchExternalUrl(context, 'https://boundly.fr'),
                          color: AppStyles.secondaryColor,
                        ),
                        const SizedBox(width: 12),
                        _SocialIcon(
                          icon: Icons.work,
                          onTap: () => UrlService.launchExternalUrl(context, 'https://www.linkedin.com/in/mathieu-blanc-408b37357/'),
                          color: AppStyles.accentColor,
                        ),
                        const SizedBox(width: 12),
                        _SocialIcon(
                          icon: Icons.camera_alt,
                          onTap: () => UrlService.launchExternalUrl(context, 'https://instagram.com/mathieu.blapro'),
                          color: AppStyles.highlightColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Text(
            "J'ai 20 ans et j'ai commencé à entreprendre dès mon adolescence. Depuis mes 18 ans, j'ai lancé plusieurs projets qui m'ont permis de développer des compétences techniques, stratégiques et juridiques, me préparant pleinement pour le développement de Boundly, une idée que j'avais en tête depuis plusieurs années.",
            style: TextStyle(fontSize: isMobile ? 14 : 16, color: Colors.white, height: 1.6),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 16),
          Text(
            "Mon premier projet majeur, lancé à 18 ans, était un applicatif pour la maintenance dans les parcs éoliens. Ce logiciel permettait une visualisation 3D des éoliennes, mettant en évidence leurs problèmes techniques pour faciliter les interventions. Cette innovation m'a appris à développer des solutions complexes et à comprendre les besoins spécifiques d'un secteur industriel.",
            style: TextStyle(fontSize: isMobile ? 14 : 16, color: Colors.white, height: 1.6),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 16),
          Text(
            "Ensuite, j'ai créé GenZave, une application de développement personnel disponible sur Android et l'App Store. Ce projet m'a permis d'approfondir mes connaissances juridiques et administratives, notamment pour pénétrer le marché américain avec Apple et Android.",
            style: TextStyle(fontSize: isMobile ? 14 : 16, color: Colors.white, height: 1.6),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 16),
          Text(
            "Aujourd'hui, en tant que créateur solo de Boundly, j'ai codé l'intégralité de la solution, de l'IA Orion à l'interface utilisateur. Je maîtrise le développement full-stack, l'intelligence artificielle, et le marketing digital, ce qui me permet de gérer tous les aspects du projet sans dépendre d'une équipe externe.",
            style: TextStyle(fontSize: isMobile ? 14 : 16, color: Colors.white, height: 1.6),
            textAlign: TextAlign.left,
          ),
        ],
      ),
    );
  }
}

/// Composant pour l'affichage des en-têtes de section
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  
  const _SectionHeader({
    required this.title,
    required this.icon,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: AppStyles.badgeDecoration(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Icône de réseau social cliquable
class _SocialIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  
  const _SocialIcon({
    required this.icon,
    required this.onTap,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 768;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isMobile ? 36 : 40,
        height: isMobile ? 36 : 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.3),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: isMobile ? 18 : 20),
      ),
    );
  }
}

/// Carte pour afficher un élément de vision
class _VisionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  final bool isMobile;
  final VoidCallback? onTap;
  final bool showArrow;
  final Color color;
  
  const _VisionCard({
    required this.icon,
    required this.title,
    required this.content,
    required this.isMobile,
    this.onTap,
    this.showArrow = false,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 0,
        color: Colors.transparent, // Rendre la carte transparente
        margin: EdgeInsets.all(isMobile ? 8 : 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withOpacity(0.5), width: 1),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(0.3),
                Colors.black.withOpacity(0.5),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 0,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          padding: EdgeInsets.all(isMobile ? 20 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(isMobile ? 10 : 12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.2),
                      blurRadius: 5,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: isMobile ? 24 : 28),
              ),
              SizedBox(height: isMobile ? 16 : 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (showArrow)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.arrow_forward, color: Colors.white, size: isMobile ? 16 : 20),
                    ),
                ],
              ),
              SizedBox(height: isMobile ? 8 : 12),
              Text(
                content,
                style: TextStyle(fontSize: isMobile ? 14 : 16, color: Colors.white, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Composant pied de page
class _Footer extends StatelessWidget {
  final bool isMobile;
  
  const _Footer({required this.isMobile});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: isMobile ? 40 : 60,
        horizontal: isMobile ? 20 : 80,
      ),
      color: Colors.black.withOpacity(0.7),
      child: Column(
        children: [
          if (!isMobile)
            _buildDesktopFooterContent(context)
          else
            _buildMobileFooterContent(context),
            
          const SizedBox(height: 60),
          Divider(color: AppStyles.primaryColor.withOpacity(0.2)),
          const SizedBox(height: 24),
          
          if (!isMobile)
            _buildDesktopFooterBottom()
          else
            _buildMobileFooterBottom(),
        ],
      ),
    );
  }

  /// Contenu du pied de page version desktop
  Widget _buildDesktopFooterContent(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: _buildFooterInfo(context),
        ),
        Expanded(
          child: _FooterLinksColumn(
            title: 'Produit',
            links: [
              _FooterLink(title: 'Fonctionnalités', route: '/features'),
              _FooterLink(title: 'Tarification', route: '/pricing'),
              _FooterLink(title: 'À propos', route: '/about'),
            ],
          ),
        ),
        Expanded(
          child: _FooterLinksColumn(
            title: 'Support',
            links: [
              _FooterLink(title: 'Contact', route: '/contact_landing'),
              _FooterLink(title: 'FAQ'),
              _FooterLink(title: 'Démonstration'),
            ],
          ),
        ),
      ],
    );
  }

  /// Contenu du pied de page version mobile
  Widget _buildMobileFooterContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFooterInfo(context),
        const SizedBox(height: 40),
        ExpansionTile(
          title: const Text(
            'Produit',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          iconColor: AppStyles.primaryColor,
          collapsedIconColor: Colors.white,
          children: [
            _buildMobileFooterLink('Fonctionnalités', '/features', context),
            _buildMobileFooterLink('Tarification', '/pricing', context),
            _buildMobileFooterLink('À propos', '/about', context),
          ],
        ),
        ExpansionTile(
          title: const Text(
            'Support',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          iconColor: AppStyles.primaryColor,
          collapsedIconColor: Colors.white,
          children: [
            _buildMobileFooterLink('Contact', '/contact_landing', context),
            _buildMobileFooterItem('FAQ'),
            _buildMobileFooterItem('Démonstration'),
          ],
        ),
      ],
    );
  }

  /// Information principale du pied de page
  Widget _buildFooterInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Boundly',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Boundly est un SaaS propulsé par Orion, une IA codée sur mesure, conçu pour optimiser les opérations des PME grâce à l'automatisation et la centralisation des données.",
          style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _SocialIcon(
              icon: Icons.email,
              onTap: () => UrlService.launchExternalUrl(context, 'mailto:contact@boundly.com'),
              color: AppStyles.primaryColor,
            ),
            const SizedBox(width: 12),
            _SocialIcon(
              icon: Icons.language,
              onTap: () => UrlService.launchExternalUrl(context, 'https://boundly.com'),
              color: AppStyles.secondaryColor,
            ),
            const SizedBox(width: 12),
            _SocialIcon(
              icon: Icons.camera_alt,
              onTap: () => UrlService.launchExternalUrl(context, 'https://instagram.com/mathieu.blapro'),
              color: AppStyles.accentColor,
            ),
          ],
        ),
      ],
    );
  }

  /// Partie basse du pied de page version desktop
  Widget _buildDesktopFooterBottom() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '© 2025 Boundly. Tous droits réservés.',
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
        Row(
          children: [
            const _TextLink(text: "Conditions d'utilisation"),
            const _DotSeparator(),
            const _TextLink(text: 'Politique de confidentialité'),
            const _DotSeparator(),
            const _TextLink(text: 'RGPD'),
          ],
        ),
      ],
    );
  }

  /// Partie basse du pied de page version mobile
  Widget _buildMobileFooterBottom() {
    return Column(
      children: [
        Text(
          '© 2025 Boundly. Tous droits réservés.',
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _TextLink(text: 'Conditions'),
            const _DotSeparator(),
            const _TextLink(text: 'Confidentialité'),
            const _DotSeparator(),
            const _TextLink(text: 'RGPD'),
          ],
        ),
      ],
    );
  }

  /// Item de pied de page mobile
  Widget _buildMobileFooterItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: TextStyle(color: Colors.grey[400], fontSize: 16)),
      ),
    );
  }

  /// Lien de pied de page mobile
  Widget _buildMobileFooterLink(String text, String route, BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      child: _buildMobileFooterItem(text),
    );
  }
}

/// Colonne de liens pour le pied de page
class _FooterLinksColumn extends StatelessWidget {
  final String title;
  final List<_FooterLink> links;
  
  const _FooterLinksColumn({
    required this.title,
    required this.links,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        ...links.map((link) {
          return link.buildLink(context);
        }).toList(),
      ],
    );
  }
}

/// Structure pour un lien de pied de page
class _FooterLink {
  final String title;
  final String? route;
  
  const _FooterLink({
    required this.title,
    this.route,
  });
  
  Widget buildLink(BuildContext context) {
    final Widget linkItem = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: TextStyle(color: Colors.grey[400], fontSize: 16)),
    );
    
    if (route != null) {
      return InkWell(
        onTap: () => Navigator.pushNamed(context, route!),
        child: linkItem,
      );
    }
    
    return linkItem;
  }
}

/// Lien texte simple
class _TextLink extends StatelessWidget {
  final String text;
  
  const _TextLink({required this.text});
  
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Text(text, style: TextStyle(color: Colors.grey[400], fontSize: 14)),
    );
  }
}

/// Séparateur sous forme de point
class _DotSeparator extends StatelessWidget {
  const _DotSeparator();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      width: 4,
      height: 4,
      decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
    );
  }
}
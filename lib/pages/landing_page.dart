import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'dart:math' as math;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/auth_service.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  _LandingPageState createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  bool _showLogin = false;
  bool _isScrolled = false;
  bool _showMobileMenu = false;
  double _backgroundOpacity = 0.3;

  // Contrôleurs de vidéo pour PC et mobile
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoError = false;
  
  // Controllers pour l'authentification
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  
  // Option "Rester connecté"
  bool _rememberMe = false;

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
    
    // Initialiser la vidéo après le premier build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initVideoPlayer();
    });
  }

  void _initVideoPlayer() {
    // En cas d'erreur ou si nous sommes sur le web, nous gérons différemment
    try {
      final screenWidth = MediaQuery.of(context).size.width;
      final bool isMobile = screenWidth < 768;
      
      // Utiliser la vidéo appropriée selon l'appareil
      final videoPath = isMobile ? 'assets/videos/boundly_tel.mp4' : 'assets/videos/boundly_pc.mp4';
      
      _videoController = VideoPlayerController.asset(videoPath)
        ..initialize().then((_) {
          // Une fois la vidéo initialisée, nous la mettons en boucle et la lançons
          _videoController!.setLooping(true);
          _videoController!.play();
          
          // Mettre à jour l'état pour indiquer que la vidéo est initialisée
          if (mounted) {
            setState(() {
              _isVideoInitialized = true;
            });
          }
        }).catchError((error) {
          print('Erreur d\'initialisation de la vidéo: $error');
          if (mounted) {
            setState(() {
              _isVideoError = true;
            });
          }
        });
    } catch (e) {
      print('Exception lors de la création du contrôleur vidéo: $e');
      setState(() {
        _isVideoError = true;
      });
    }
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impossible d\'ouvrir $urlString'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

  void _scrollToFeatures() {
    final screenHeight = MediaQuery.of(context).size.height;
    _scrollController.animateTo(
      screenHeight,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
    );
  }
  
  // Méthode pour tenter de se connecter
  Future<void> _login() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Accéder à AuthService via Provider
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Tenter de se connecter avec email et mot de passe
      // Cette méthode retourne un UserCredential et non un booléen
      await authService.signInWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text,
        rememberDevice: _rememberMe, // Utiliser la valeur de _rememberMe
      );
      
      // Si on arrive ici, c'est que la connexion a réussi (sinon une exception aurait été levée)
      if (mounted) {
        setState(() {
          _showLogin = false;
        });
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } catch (e) {
      // Gérer les erreurs d'authentification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur de connexion: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Réinitialiser l'état de chargement
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _animationController.dispose();
    // Libérer les contrôleurs
    _emailController.dispose();
    _passwordController.dispose();
    // Libérer les ressources de la vidéo
    if (_videoController != null) {
      _videoController!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 768;
    
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        if (authService.isAuthenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacementNamed(context, '/dashboard');
          });
        }

        return Scaffold(
          body: Stack(
            children: [
              // Background vidéo ou image si la vidéo n'est pas encore chargée
              Positioned.fill(
                child: _isVideoInitialized && !_isVideoError && _videoController != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _videoController!.value.size.width,
                            height: _videoController!.value.size.height,
                            child: VideoPlayer(_videoController!),
                          ),
                        ),
                        // Overlay pour assombrir la vidéo
                        Container(
                          color: Colors.black.withOpacity(_backgroundOpacity + (isMobile ? 0.1 : 0)),
                        ),
                      ],
                    )
                  : Image.asset(
                      'assets/images/background.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      color: Colors.black.withOpacity(_backgroundOpacity + (isMobile ? 0.1 : 0)),
                      colorBlendMode: BlendMode.darken,
                    ),
              ),
              
              // Content
              SafeArea(
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(child: SizedBox(height: 70)), // Space for AppBar
                    SliverToBoxAdapter(child: _buildHeroSection(screenHeight, isMobile)),
                    SliverToBoxAdapter(child: _buildFeaturesSection(isMobile)),
                    SliverToBoxAdapter(child: _buildBusinessSection(isMobile)),
                    SliverToBoxAdapter(child: _buildHowItWorksSection(isMobile)),
                    SliverToBoxAdapter(child: _buildFinalCTASection(isMobile)),
                    SliverToBoxAdapter(child: _buildFooter(isMobile)),
                  ],
                ),
              ),
              
              // AppBar (simplified)
              _buildAppBar(isMobile),
              
              // Mobile Menu
              if (isMobile && _showMobileMenu) _buildMobileMenu(),
              
              // Login Overlay
              if (_showLogin) _buildLoginOverlay(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAppBar(bool isMobile) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        color: _isScrolled 
          ? Colors.black.withOpacity(0.7) // More opaque when scrolled
          : Colors.transparent,
        child: SafeArea(
          child: Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Logo text only, no icon
                const Text(
                  'Boundly',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                
                if (!isMobile)
                  Row(
                    children: [
                      _buildNavItem('Accueil', Icons.home),
                      _buildNavItem('Fonctionnalités', Icons.grid_view),
                      _buildNavItem('Tarifs', Icons.paid),
                      _buildNavItem('À propos', Icons.info),
                      _buildNavItem('Contact', Icons.mail),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() => _showLogin = true);
                        },
                        icon: const Icon(Icons.login, size: 18),
                        label: const Text('Se connecter'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 4,
                          shadowColor: Colors.blue.withOpacity(0.4),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.login, size: 24, color: Colors.white),
                        onPressed: () {
                          setState(() => _showLogin = true);
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          _showMobileMenu ? Icons.close : Icons.menu,
                          size: 28,
                          color: Colors.white,
                        ),
                        onPressed: () => setState(() => _showMobileMenu = !_showMobileMenu),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileMenu() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 70,
      left: 0, right: 0,
      child: Container(
        color: Colors.black.withOpacity(0.9), // More opaque for better readability
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildMobileMenuItem('Accueil', Icons.home),
            _buildMobileMenuItem('Fonctionnalités', Icons.grid_view),
            _buildMobileMenuItem('Tarifs', Icons.paid),
            _buildMobileMenuItem('À propos', Icons.info),
            _buildMobileMenuItem('Contact', Icons.mail),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _showMobileMenu = false;
                  _showLogin = true;
                });
              },
              icon: const Icon(Icons.login),
              label: const Text('Se connecter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileMenuItem(String title, IconData icon) {
    return InkWell(
      onTap: () {
        setState(() => _showMobileMenu = false);
        if (title == 'Accueil') {
          // Rester sur la page d'accueil
        } else if (title == 'Fonctionnalités') {
          Navigator.pushNamed(context, '/features');
        } else if (title == 'Tarifs') {
          Navigator.pushNamed(context, '/pricing');
        } else if (title == 'À propos') {
          Navigator.pushNamed(context, '/about');
        } else if (title == 'Contact') {
          Navigator.pushNamed(context, '/contact_landing');
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        onTap: () {
          if (title == 'Accueil') {
            // Rester sur la page d'accueil
          } else if (title == 'Fonctionnalités') {
            Navigator.pushNamed(context, '/features');
          } else if (title == 'Tarifs') {
            Navigator.pushNamed(context, '/pricing');
          } else if (title == 'À propos') {
            Navigator.pushNamed(context, '/about');
          } else if (title == 'Contact') {
            Navigator.pushNamed(context, '/contact_landing');
          }
        },
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isScrolled ? Colors.white.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(double screenHeight, bool isMobile) {
    final appBarHeight = 70.0;
    // Assurez-vous que la hauteur ne soit jamais négative
    final heroHeight = math.max(screenHeight - appBarHeight, 0.0);
    
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Colors.blue.shade700,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: isMobile ? 12 : 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.3),
    );
    
    final outlineButtonStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white, width: 2),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: isMobile ? 12 : 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    if (isMobile) {
      return Container(
        constraints: BoxConstraints(
          minHeight: heroHeight,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Automatisez\nvotre PME',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      height: 1.1,
                      shadows: const [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: const Text(
                      'La plateforme collaborative propulsée par l\'IA Orion qui transforme les PME',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildKeyPoint(Icons.speed, 'Gain de temps 80-90%'),
                      const SizedBox(height: 10),
                      _buildKeyPoint(Icons.payments, '300€/mois tout inclus'),
                      const SizedBox(height: 10),
                      _buildKeyPoint(Icons.smart_toy, 'IA Orion intégrée'),
                    ],
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _showLogin = true);
                      },
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('Connexion à l\'application', style: TextStyle(fontSize: 14)),
                      style: buttonStyle,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: GestureDetector(
                onTap: _scrollToFeatures,
                child: Container(
                  height: 60,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _animationController..repeat(reverse: true),
                        builder: (context, child) {
                          return Container(
                            width: 40 + (10 * _animationController.value),
                            height: 40 + (10 * _animationController.value),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.1 * _animationController.value),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2 + 0.3 * _animationController.value),
                                width: 1,
                              ),
                            ),
                          );
                        },
                      ),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 20,
                alignment: Alignment.center,
                child: const Text(
                  'Défiler pour découvrir',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } 
    else {
      return SizedBox(
        height: heroHeight,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withOpacity(0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'IA Orion disponible',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Automatisez\nvotre PME',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        height: 1.1,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                      ),
                      child: const Text(
                        'La plateforme collaborative propulsée par l\'IA Orion qui transforme les PME',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Expanded(child: _buildKeyPoint(Icons.speed, 'Gain de temps 80-90%')),
                        const SizedBox(width: 16),
                        Expanded(child: _buildKeyPoint(Icons.payments, '300€/mois tout inclus')),
                        const SizedBox(width: 16),
                        Expanded(child: _buildKeyPoint(Icons.smart_toy, 'IA Orion intégrée')),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() => _showLogin = true);
                          },
                          icon: const Icon(Icons.login),
                          label: const Text('Connexion à l\'application'),
                          style: buttonStyle,
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton.icon(
                          onPressed: _scrollToFeatures,
                          icon: const Icon(Icons.arrow_downward),
                          label: const Text('En savoir plus'),
                          style: outlineButtonStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _scrollToFeatures,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _animationController..repeat(reverse: true),
                            builder: (context, child) {
                              return Container(
                                width: 70 + (20 * _animationController.value),
                                height: 70 + (20 * _animationController.value),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.1 * _animationController.value),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2 + 0.3 * _animationController.value),
                                    width: 2,
                                  ),
                                ),
                              );
                            },
                          ),
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: GestureDetector(
                          onTap: _scrollToFeatures,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Colors.white.withOpacity(0.15),
                              border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Défiler pour découvrir',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 4,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_downward,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildKeyPoint(IconData icon, String text) {
    final bool isMobile = MediaQuery.of(context).size.width < 768;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? 6 : 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: Icon(icon, color: Colors.white, size: isMobile ? 14 : 16),
        ),
        SizedBox(width: isMobile ? 6 : 8),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.w500,
              shadows: const [Shadow(color: Colors.black, blurRadius: 5, offset: Offset(0, 1))],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesSection(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 40 : 80, horizontal: isMobile ? 16 : 80),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.3), width: 1),
          bottom: BorderSide(color: Colors.white.withOpacity(0.3), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildSectionHeader('FONCTIONNALITÉS', Icons.star),
          const SizedBox(height: 24),
          
          Text(
            'Un SaaS propulsé par l\'IA pour optimiser vos opérations',
            style: TextStyle(
              fontSize: isMobile ? 24 : 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          
          Container(
            constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 700),
            child: Text(
              'Boundly centralise et automatise vos tâches administratives grâce à Orion, notre IA conçue sur mesure pour les PME de 1 à 50 employés.',
              style: TextStyle(fontSize: isMobile ? 15 : 18, color: Colors.white, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: isMobile ? 30 : 50),
          
          if (!isMobile)
            Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildFeatureCard(icon: Icons.receipt_long, color: Colors.blue, title: 'Gestion financière', description: 'Automatisez vos factures, devis et paiements grâce à l\'IA Orion, réduisant jusqu\'à 90% du temps consacré aux tâches administratives.')),
                    Expanded(child: _buildFeatureCard(icon: Icons.people, color: Colors.purple, title: 'CRM intégré', description: 'Centralisez toutes vos données clients et laissez Orion analyser leurs comportements pour des relances automatiques et personnalisées.')),
                    Expanded(child: _buildFeatureCard(icon: Icons.calendar_month, color: Colors.green, title: 'Planification intelligente', description: 'Synchronisez vos agendas et optimisez vos plannings grâce aux suggestions d\'Orion basées sur vos priorités et disponibilités.')),
                  ],
                ),
                const SizedBox(height: 40),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildFeatureCard(icon: Icons.chat, color: Colors.teal, title: 'Collaboration intégrée', description: 'Discutez en direct, partagez des fichiers et organisez des réunions vidéo avec la possibilité de générer automatiquement des comptes-rendus.')),
                    Expanded(child: _buildFeatureCard(icon: Icons.insert_chart, color: Colors.orange, title: 'Tableaux de bord personnalisés', description: 'Visualisez vos données et obtenez des insights pertinents avec des analyses en temps réel générées par Orion pour des décisions éclairées.')),
                    Expanded(child: _buildFeatureCard(icon: Icons.settings, color: Colors.indigo, title: 'Adaptations sur mesure', description: 'Intégrez Boundly à votre écosystème existant avec des adaptations spécifiques à votre secteur (conseil, commerce, santé, services).')),
                  ],
                ),
              ],
            )
          else
            Column(
              children: [
                _buildFeatureCard(icon: Icons.receipt_long, color: Colors.blue, title: 'Gestion financière', description: 'Automatisez vos factures, devis et paiements grâce à l\'IA Orion, réduisant jusqu\'à 90% du temps consacré aux tâches administratives.'),
                _buildFeatureCard(icon: Icons.people, color: Colors.purple, title: 'CRM intégré', description: 'Centralisez toutes vos données clients et laissez Orion analyser leurs comportements pour des relances automatiques et personnalisées.'),
                _buildFeatureCard(icon: Icons.calendar_month, color: Colors.green, title: 'Planification intelligente', description: 'Synchronisez vos agendas et optimisez vos plannings grâce aux suggestions d\'Orion basées sur vos priorités et disponibilités.'),
                _buildFeatureCard(icon: Icons.chat, color: Colors.teal, title: 'Collaboration intégrée', description: 'Discutez en direct, partagez des fichiers et organisez des réunions vidéo avec la possibilité de générer automatiquement des comptes-rendus.'),
                _buildFeatureCard(icon: Icons.insert_chart, color: Colors.orange, title: 'Tableaux de bord personnalisés', description: 'Visualisez vos données et obtenez des insights pertinents avec des analyses en temps réel générées par Orion pour des décisions éclairées.'),
                _buildFeatureCard(icon: Icons.settings, color: Colors.indigo, title: 'Adaptations sur mesure', description: 'Intégrez Boundly à votre écosystème existant avec des adaptations spécifiques à votre secteur (conseil, commerce, santé, services).'),
              ],
            ),
          const SizedBox(height: 30),
          
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pushNamed(context, '/features');
            },
            icon: const Icon(Icons.visibility),
            label: const Text('Voir toutes les fonctionnalités'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.2),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: isMobile ? 12 : 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required Color color,
    required String title,
    required String description,
  }) {
    final bool isMobile = MediaQuery.of(context).size.width < 768;
    
    return Card(
      elevation: 0,
      color: Colors.white.withOpacity(0.15),
      margin: EdgeInsets.all(isMobile ? 4 : 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.4), width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 8 : 12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: isMobile ? 22 : 28),
            ),
            SizedBox(height: isMobile ? 12 : 20),
            Text(
              title,
              style: TextStyle(
                fontSize: isMobile ? 16 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: isMobile ? 6 : 12),
            Text(
              description,
              style: TextStyle(fontSize: isMobile ? 13 : 16, color: Colors.white, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.4)),
          ),
          child: Row(
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
        ),
      ],
    );
  }

  // Version raccourcie de la section Business/Vision avec lien vers la page À propos
  Widget _buildBusinessSection(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 60 : 100, horizontal: isMobile ? 20 : 80),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.3), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildSectionHeader('NOTRE VISION', Icons.insert_chart),
          const SizedBox(height: 24),
          
          Text(
            'Une IA au service des PME françaises',
            style: TextStyle(
              fontSize: isMobile ? 28 : 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          
          Container(
            constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 800),
            child: Text(
              'Boundly est un SaaS propulsé par Orion, une IA codée sur mesure, conçu pour optimiser les opérations des PME grâce à l\'automatisation et la centralisation des données.',
              style: TextStyle(fontSize: isMobile ? 18 : 20, color: Colors.white, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: isMobile ? 40 : 60),
          
          if (!isMobile)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildBusinessCard(icon: Icons.trending_up, title: 'Marché', content: 'Un marché de 2 milliards €/an avec 150 000 PME françaises de 1 à 50 employés.')),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/pricing'),
                    child: _buildBusinessCard(
                      icon: Icons.euro, 
                      title: 'Modèle', 
                      content: 'Abonnement unique à 300€/mois pour toutes les fonctionnalités, quel que soit le nombre d\'utilisateurs.',
                      showArrow: true,
                    ),
                  ),
                ),
                Expanded(child: _buildBusinessCard(icon: Icons.rocket_launch, title: 'Objectifs', content: '100 clients en 2026, 400 en 2027, et 1 000 en 2028 avec expansion européenne.')),
              ],
            )
          else
            Column(
              children: [
                _buildBusinessCard(icon: Icons.trending_up, title: 'Marché', content: 'Un marché de 2 milliards €/an avec 150 000 PME françaises de 1 à 50 employés.'),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/pricing'),
                  child: _buildBusinessCard(
                    icon: Icons.euro, 
                    title: 'Modèle', 
                    content: 'Abonnement unique à 300€/mois pour toutes les fonctionnalités, quel que soit le nombre d\'utilisateurs.',
                    showArrow: true,
                  ),
                ),
                _buildBusinessCard(icon: Icons.rocket_launch, title: 'Objectifs', content: '100 clients en 2026, 400 en 2027, et 1 000 en 2028 avec expansion européenne.'),
              ],
            ),
          
          SizedBox(height: isMobile ? 40 : 60),
          
          // Version simplifiée de la section fondateur avec bouton vers la page À propos
          Container(
            padding: EdgeInsets.all(isMobile ? 20 : 30),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.4), width: 1),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Photo du fondateur
                    CircleAvatar(
                      radius: isMobile ? 40 : 50,
                      backgroundImage: const AssetImage('assets/images/profil.png'),
                    ),
                    const SizedBox(width: 20),
                    // Informations sur le fondateur
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mathieu Blanc',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Fondateur & Développeur',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Entrepreneur passionné de 20 ans, j\'ai développé Boundly pour résoudre les problèmes d\'efficacité des PME.',
                            style: TextStyle(fontSize: isMobile ? 14 : 16, color: Colors.white, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Bouton vers la page À propos
                ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/about'),
                  icon: const Icon(Icons.info),
                  label: const Text('En savoir plus sur Boundly et son créateur'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: isMobile ? 12 : 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessCard({
    required IconData icon, 
    required String title, 
    required String content,
    bool showArrow = false,
  }) {
    final bool isMobile = MediaQuery.of(context).size.width < 768;
    
    return Card(
      elevation: 0,
      color: Colors.white.withOpacity(0.15),
      margin: EdgeInsets.all(isMobile ? 8 : 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.4), width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 20 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(isMobile ? 10 : 12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
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
                    style: TextStyle(
                      fontSize: isMobile ? 20 : 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (showArrow)
                  Icon(Icons.arrow_forward, color: Colors.white, size: isMobile ? 20 : 24),
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
    );
  }

  Widget _buildHowItWorksSection(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 50 : 80, horizontal: isMobile ? 16 : 80),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.3), width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildSectionHeader('COMMENT ÇA MARCHE', Icons.lightbulb),
          const SizedBox(height: 24),
          
          Text(
            'Une transformation digitale accessible aux PME',
            style: TextStyle(
              fontSize: isMobile ? 28 : 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          
          Container(
            constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 700),
            child: Text(
              'Notre processus d\'intégration est conçu pour être simple et efficace, vous permettant de transformer rapidement votre PME grâce à l\'IA Orion.',
              style: TextStyle(fontSize: isMobile ? 15 : 18, color: Colors.white, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: isMobile ? 30 : 50),
          
          if (!isMobile)
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(child: _buildStepCard(number: '1', title: 'Créez votre compte', description: 'Inscrivez-vous en quelques minutes et accédez immédiatement à toutes les fonctionnalités de Boundly pour 300€/mois, quel que soit le nombre d\'utilisateurs.', color: Colors.blue)),
                  _buildStepConnector(),
                  Expanded(child: _buildStepCard(number: '2', title: 'Configurez Orion', description: 'Notre IA s\'adapte à votre secteur d\'activité et apprend de vos données pour automatiser efficacement vos tâches administratives.', color: Colors.purple)),
                  _buildStepConnector(),
                  Expanded(child: _buildStepCard(number: '3', title: 'Gagnez du temps', description: 'Réduisez jusqu\'à 90% du temps consacré aux tâches administratives et concentrez-vous sur votre cœur de métier et votre croissance.', color: Colors.green)),
                ],
              ),
            )
          else
            Column(
              children: [
                _buildStepCard(number: '1', title: 'Créez votre compte', description: 'Inscrivez-vous en quelques minutes et accédez immédiatement à toutes les fonctionnalités de Boundly pour 300€/mois, quel que soit le nombre d\'utilisateurs.', color: Colors.blue),
                Container(height: 40, alignment: Alignment.center, child: Container(width: 2, height: 30, color: Colors.white.withOpacity(0.3))),
                _buildStepCard(number: '2', title: 'Configurez Orion', description: 'Notre IA s\'adapte à votre secteur d\'activité et apprend de vos données pour automatiser efficacement vos tâches administratives.', color: Colors.purple),
                Container(height: 40, alignment: Alignment.center, child: Container(width: 2, height: 30, color: Colors.white.withOpacity(0.3))),
                _buildStepCard(number: '3', title: 'Gagnez du temps', description: 'Réduisez jusqu\'à 90% du temps consacré aux tâches administratives et concentrez-vous sur votre cœur de métier et votre croissance.', color: Colors.green),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStepConnector() {
    return Column(
      children: [
        const SizedBox(height: 60),
        Expanded(
          child: Container(
            width: 40,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Container(height: 2, color: Colors.white.withOpacity(0.3))],
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildStepCard({required String number, required String title, required String description, required Color color}) {
    final bool isMobile = MediaQuery.of(context).size.width < 768;
    
    return Column(
      children: [
        Container(
          width: isMobile ? 50 : 60,
          height: isMobile ? 50 : 60,
          decoration: BoxDecoration(
            color: color.withOpacity(0.7),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 10, spreadRadius: 2, offset: const Offset(0, 4))],
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: TextStyle(color: Colors.white, fontSize: isMobile ? 20 : 24, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(height: isMobile ? 20 : 30),
        Text(
          title,
          style: TextStyle(fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: isMobile ? 12 : 16),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 20),
          child: Text(
            description,
            style: TextStyle(fontSize: isMobile ? 14 : 16, color: Colors.white, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildFinalCTASection(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 50 : 80, horizontal: isMobile ? 20 : 80),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.3), width: 1)),
      ),
      child: Container(
        padding: EdgeInsets.all(isMobile ? 24 : 48),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
          boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.05), blurRadius: 15, spreadRadius: 0)],
        ),
        child: Column(
          children: [
            Icon(Icons.rocket_launch, color: Colors.white, size: isMobile ? 36 : 48),
            SizedBox(height: isMobile ? 16 : 24),
            Text(
              'Prêt à transformer votre PME avec l\'IA?',
              style: TextStyle(
                fontSize: isMobile ? 24 : 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isMobile ? 12 : 16),
            Container(
              constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 700),
              child: Text(
                'Rejoignez les PME qui utilisent déjà Boundly pour automatiser leurs opérations et centraliser leurs données grâce à notre IA Orion.',
                style: TextStyle(fontSize: isMobile ? 15 : 18, color: Colors.white, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: isMobile ? 30 : 40),
            if (!isMobile)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _showLogin = true);
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Connexion à l\'application'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blue.shade800,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton.icon(
                    onPressed: () => _launchUrl('https://youtu.be/W0J9BUreLjI?si=AFTJq4KIqRinZ0PZ'),
                    icon: const Icon(Icons.play_circle),
                    label: const Text('Voir la démonstration'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _showLogin = true);
                    },
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('Connexion à l\'application', style: TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blue.shade800,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _launchUrl('https://youtu.be/W0J9BUreLjI?si=AFTJq4KIqRinZ0PZ'),
                    icon: const Icon(Icons.play_circle, size: 18),
                    label: const Text('Voir la démonstration', style: TextStyle(fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 40 : 60, horizontal: isMobile ? 20 : 80),
      color: Colors.black.withOpacity(0.7),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo et description
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo text only
                    const Text(
                      'Boundly',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Boundly est un SaaS propulsé par Orion, une IA codée sur mesure, conçu pour optimiser les opérations des PME grâce à l\'automatisation et la centralisation des données.',
                      style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.6),
                    ),
                  ],
                ),
              ),
              
              // Les colonnes de liens, exactement comme sur desktop
              Expanded(child: _buildFooterLinksColumn(title: 'Produit', links: ['Fonctionnalités', 'Tarification', 'À propos'])),
              Expanded(child: _buildFooterLinksColumn(title: 'Secteurs', links: ['Conseil', 'Commerce', 'Santé', 'Services'])),
              Expanded(child: _buildFooterLinksColumn(title: 'Support', links: ['Aide', 'Contact', 'Démonstration', 'Communauté'])),
            ],
          ),
          
          const SizedBox(height: 60),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),
          
          if (!isMobile)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('© 2025 Boundly. Tous droits réservés.', style: TextStyle(color: Colors.white60, fontSize: 14)),
                Row(
                  children: [
                    _buildFooterLink('Conditions d\'utilisation'),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      width: 4, height: 4,
                      decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                    ),
                    _buildFooterLink('Politique de confidentialité'),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      width: 4, height: 4,
                      decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                    ),
                    _buildFooterLink('RGPD'),
                  ],
                ),
              ],
            )
          else
            Column(
              children: [
                const Text('© 2025 Boundly. Tous droits réservés.', style: TextStyle(color: Colors.white60, fontSize: 14)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildFooterLink('Conditions'),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 4, height: 4,
                      decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                    ),
                    _buildFooterLink('Confidentialité'),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 4, height: 4,
                      decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                    ),
                    _buildFooterLink('RGPD'),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMobileFooterItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: const TextStyle(color: Colors.white60, fontSize: 16)),
      ),
    );
  }

  Widget _buildFooterLink(String text) {
    return InkWell(
      onTap: () {},
      child: Text(text, style: const TextStyle(color: Colors.white60, fontSize: 14)),
    );
  }

  Widget _buildFooterLinksColumn({required String title, required List<String> links}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        ...links.map((link) {
          Widget linkItem = Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(link, style: const TextStyle(color: Colors.white60, fontSize: 16)),
          );

          if (link == 'Fonctionnalités') {
            return InkWell(
              onTap: () => Navigator.pushNamed(context, '/features'),
              child: linkItem,
            );
          } else if (link == 'Tarification') {
            return InkWell(
              onTap: () => Navigator.pushNamed(context, '/pricing'),
              child: linkItem,
            );
          } else if (link == 'À propos') {
            return InkWell(
              onTap: () => Navigator.pushNamed(context, '/about'),
              child: linkItem,
            );
          } else if (link == 'Contact') {
            return InkWell(
              onTap: () => Navigator.pushNamed(context, '/contact_landing'),
              child: linkItem,
            );
          }

          return linkItem;
        }).toList(),
      ],
    );
  }

  Widget _buildLoginOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF263238),
                      const Color(0xFF1C262B),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF37474F), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF546E7A).withOpacity(0.15),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                constraints: const BoxConstraints(maxWidth: 450),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF546E7A).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.login, color: Color(0xFF78909C), size: 24),
                            ),
                            const SizedBox(width: 16),
                            const Text(
                              'Connexion',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => setState(() => _showLogin = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    
                    // Formulaire de connexion
                    TextField(
                      controller: _emailController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Email',
                        labelStyle: const TextStyle(color: Color(0xFF90A4AE)),
                        hintText: 'Entrez votre email',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        prefixIcon: const Icon(Icons.email, color: Color(0xFF90A4AE)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF37474F)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF37474F)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF607D8B), width: 2),
                        ),
                        fillColor: const Color(0xFF1E2A30),
                        filled: true,
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    TextField(
                      controller: _passwordController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        labelStyle: const TextStyle(color: Color(0xFF90A4AE)),
                        hintText: 'Entrez votre mot de passe',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        prefixIcon: const Icon(Icons.lock, color: Color(0xFF90A4AE)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF37474F)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF37474F)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF607D8B), width: 2),
                        ),
                        fillColor: const Color(0xFF1E2A30),
                        filled: true,
                      ),
                      obscureText: true,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Option "Rester connecté"
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (value) {
                            setState(() {
                              _rememberMe = value ?? false;
                            });
                          },
                          fillColor: MaterialStateProperty.resolveWith<Color>(
                            (Set<MaterialState> states) {
                              if (states.contains(MaterialState.selected)) {
                                return const Color(0xFF546E7A);
                              }
                              return Colors.transparent;
                            },
                          ),
                          checkColor: Colors.white,
                          side: const BorderSide(
                            color: Color(0xFF78909C),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const Text(
                          'Rester connecté',
                          style: TextStyle(
                            color: Color(0xFF90A4AE),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Un email de réinitialisation a été envoyé'),
                                backgroundColor: Color(0xFF455A64),
                              ),
                            );
                          },
                          child: const Text(
                            'Mot de passe oublié ?',
                            style: TextStyle(
                              color: Color(0xFF90A4AE),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 30),
                    
                    _isLoading 
                      ? const CircularProgressIndicator(color: Color(0xFF546E7A))
                      : ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF546E7A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            minimumSize: const Size(double.infinity, 54),
                            elevation: 8,
                            shadowColor: const Color(0xFF546E7A).withOpacity(0.4),
                          ),
                          child: const Text(
                            'Se connecter',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                    
                    const SizedBox(height: 24),
                    
                    Row(
                      children: [
                        Expanded(child: Divider(color: const Color(0xFF37474F))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Ou',
                            style: TextStyle(color: Colors.white.withOpacity(0.7)),
                          ),
                        ),
                        Expanded(child: Divider(color: const Color(0xFF37474F))),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, '/register');
                      },
                      icon: const Icon(Icons.person_add),
                      label: const Text('Créer un compte'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF90A4AE),
                        side: const BorderSide(color: Color(0xFF546E7A)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        minimumSize: const Size(double.infinity, 54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
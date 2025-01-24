// lib/pages/landing_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart'; // Import video_player
import '../services/auth_service.dart';
import 'dart:math'; // Import sans alias
// import 'dart:math' as math; // Option avec alias si nécessaire

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  _LandingPageState createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  // Video Player Controller
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;

  // État pour contrôler l'affichage du formulaire de connexion
  bool _showLogin = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  // Initialize Video Player
  void _initializeVideo() {
    _videoController = VideoPlayerController.asset('assets/videos/Video.mp4') // Remplacez par le chemin de votre vidéo
      ..addListener(() {
        final bool isPlaying = _videoController.value.isPlaying;
        final bool hasError = _videoController.value.hasError;
        if (hasError) {
          print("Video Error: ${_videoController.value.errorDescription}");
        }
        print("Video isPlaying: $isPlaying, hasError: $hasError");
      })
      ..initialize().then((_) {
        setState(() {
          _isVideoInitialized = true;
        });
        _videoController.setLooping(true);
        _videoController.setVolume(0.0); // Mute la vidéo pour permettre l'autoplay
        _videoController.play();
        print("Vidéo initialisée et en cours de lecture.");
      }).catchError((error) {
        // Gestion des erreurs d'initialisation
        print("Erreur lors de l'initialisation de la vidéo : $error");
      });
  }

  @override
  void dispose() {
    _videoController.dispose(); // Dispose le contrôleur vidéo
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        if (authService.isAuthenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacementNamed(context, '/dashboard');
          });
        }

        return Scaffold(
          backgroundColor: Colors.grey.shade900,
          body: Stack(
            children: [
              // Image de Fond
              Positioned.fill(
                child: Image.asset(
                  'assets/images/background.png',
                  fit: BoxFit.cover,
                ),
              ),
              // Superposition Sombre
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                ),
              ),
              // Contenu Principal
              Row(
                crossAxisAlignment: CrossAxisAlignment.start, // Aligner en haut
                children: [
                  // Menu Latéral
                  _buildSideMenu(context),

                  // Espace pour le contenu principal
                  Expanded(
                    child: Container(),
                  ),

                  // Conteneur de Droite avec Fonctionnalités et CTA
                  _buildRightContainer(context),
                ],
              ),
              // **Lecteur Vidéo Positionné entre la gauche et le centre**
              Positioned(
                top: 20,
                left: MediaQuery.of(context).size.width * 0.15, // 15% depuis la gauche
                child: _buildVideoPlayer(),
              ),
              // **SUPPRIMER LE TEXTE ROTATIF AUTOUR DE LA VIDÉO**
              // Vous pouvez simplement commenter ou supprimer ce bloc de code
              /*
              Positioned(
                top: 40, // Positionner légèrement au-dessus de la vidéo
                left: MediaQuery.of(context).size.width * 0.15 - 10, // Aligné avec la vidéo
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _buildRotatingText(
                      text: 'Innovation',
                      angle: 0,
                    ),
                    _buildRotatingText(
                      text: 'Technologie',
                      angle: pi / 2, // Utilisation de 'pi' directement
                    ),
                    _buildRotatingText(
                      text: 'Créativité',
                      angle: pi,
                    ),
                    _buildRotatingText(
                      text: 'Design',
                      angle: -pi / 2,
                    ),
                  ],
                ),
              ),
              */
              // Bouton de Connexion pour afficher le formulaire de connexion
              Positioned(
                bottom: 30,
                right: 30,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showLogin = true;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text(
                    'Se Connecter',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
              // Superposition du Formulaire de Connexion
              if (_showLogin) _buildLoginOverlay(),
            ],
          ),
        );
      },
    );
  }

  // Construire le Lecteur Vidéo
  Widget _buildVideoPlayer() {
    double videoSize = MediaQuery.of(context).size.width * 0.25; // 25% de la largeur de l'écran

    return Opacity(
      opacity: 0.5, // Ajustez l'opacité selon vos besoins
      child: SizedBox(
        width: videoSize,
        height: videoSize,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: _isVideoInitialized
              ? (_videoController.value.hasError
                  ? Center(
                      child: Text(
                        'Erreur de lecture vidéo',
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  : VideoPlayer(_videoController))
              : const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  // Construire le Menu Latéral avec Transparence
  Widget _buildSideMenu(BuildContext context) {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.7), // Appliquer une transparence de 70%
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(30),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Icône Principal
          Icon(Icons.assistant, size: 32, color: Colors.white),

          // Icônes de Navigation
          Column(
            children: [
              HoverIcon(icon: Icons.home, tooltip: "Accueil", route: '/home'),
              HoverIcon(icon: Icons.settings, tooltip: "Paramètres", route: '/settings'),
              HoverIcon(icon: Icons.help_outline, tooltip: "FAQ", route: '/faq'),
              HoverIcon(
                icon: Icons.login,
                tooltip: "Connexion",
                onTap: () {
                  setState(() {
                    _showLogin = true;
                  });
                },
              ),
            ],
          ),

          // Icônes ou Éléments Supplémentaires peuvent être ajoutés ici
        ],
      ),
    );
  }

  // Construire le Conteneur de Droite avec Fonctionnalités et CTA
  Widget _buildRightContainer(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(30),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Première Fonctionnalité
            _buildRightFeatureSection(
              icon: Icons.group,
              title: 'Groupes',
              description: 'Rejoignez des groupes et collaborez efficacement.',
              onTap: () {
                Navigator.pushNamed(context, '/groupes');
              },
            ),
            const SizedBox(height: 16),

            // Deuxième Fonctionnalité
            _buildRightFeatureSection(
              icon: Icons.event,
              title: 'Événements',
              description: 'Participez à des événements exclusifs.',
              onTap: () {
                Navigator.pushNamed(context, '/evenements');
              },
            ),
            const SizedBox(height: 16),

            // Troisième Fonctionnalité
            _buildRightFeatureSection(
              icon: Icons.notifications,
              title: 'Notifications',
              description: 'Restez informé des dernières mises à jour.',
              onTap: () {
                Navigator.pushNamed(context, '/notifications');
              },
            ),
            const SizedBox(height: 24),

            // Section CTA
            _buildCTASection(context),
          ],
        ),
      ),
    );
  }

  // Construire une Section Fonctionnalité Individuelle
  Widget _buildRightFeatureSection({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, color: Colors.white),
          ],
        ),
      ),
    );
  }

  // Construire la Section CTA
  Widget _buildCTASection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // Aligner à gauche
      children: [
        const Text(
          'Rejoignez Boundly dès aujourd\'hui',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [
              Shadow(
                blurRadius: 4.0,
                color: Colors.black,
                offset: Offset(2.0, 2.0),
              ),
            ],
          ),
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _showLogin = true;
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          child: const Text('Créer un compte gratuit'),
        ),
      ],
    );
  }

  // Construire le Texte Rotatif Autour de la Vidéo
  Widget _buildRotatingText({required String text, required double angle}) {
    return Transform.rotate(
      angle: angle, // Angle fixe
      child: Container(
        padding: const EdgeInsets.all(8.0),
        color: Colors.black.withOpacity(0.5),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  // Construire la Superposition du Formulaire de Connexion
  Widget _buildLoginOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black54, // Fond semi-transparent
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16), // Réduction des marges
              padding: const EdgeInsets.all(20), // Réduction du padding
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 90, 90, 90).withOpacity(0.85), // Légère réduction de l'opacité
                borderRadius: BorderRadius.circular(16),
              ),
              constraints: BoxConstraints(
                maxWidth: 400, // Largeur maximale pour un conteneur plus petit
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Titre
                  const Text(
                    'Connexion',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white, // Changer le texte en blanc
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Formulaire de Connexion
                  _LoginForm(
                    onClose: () {
                      setState(() {
                        _showLogin = false;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Widget Formulaire de Connexion intégré
class _LoginForm extends StatefulWidget {
  final VoidCallback onClose;

  const _LoginForm({super.key, required this.onClose});

  @override
  __LoginFormState createState() => __LoginFormState();
}

class __LoginFormState extends State<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  bool _rememberMe = false;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Column(
      children: [
        // Bouton de fermeture
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white), // Bouton de fermeture en blanc
            onPressed: widget.onClose,
          ),
        ),
        const SizedBox(height: 8),
        Form(
          key: _formKey,
          child: Column(
            children: [
              // Champ Email
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: Colors.white), // Label en blanc
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white), // Bordure en blanc
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white), // Bordure en blanc
                  ),
                ),
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white), // Texte en blanc
                onSaved: (value) {
                  _email = value!.trim();
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer votre email';
                  }
                  final RegExp emailRegex = RegExp(
                      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
                  if (!emailRegex.hasMatch(value)) {
                    return 'Veuillez entrer un email valide';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Champ Mot de Passe
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Mot de Passe',
                  labelStyle: TextStyle(color: Colors.white), // Label en blanc
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white), // Bordure en blanc
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white), // Bordure en blanc
                  ),
                ),
                obscureText: true,
                style: const TextStyle(color: Colors.white), // Texte en blanc
                onSaved: (value) {
                  _password = value!.trim();
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer votre mot de passe';
                  }
                  if (value.length < 6) {
                    return 'Le mot de passe doit contenir au moins 6 caractères';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Checkbox Se Souvenir de Moi
              Row(
                children: [
                  Checkbox(
                    value: _rememberMe,
                    checkColor: Colors.black, // Couleur de la coche
                    activeColor: Colors.white, // Couleur de l'arrière-plan de la checkbox
                    onChanged: (value) {
                      if (!mounted) return;
                      setState(() {
                        _rememberMe = value!;
                      });
                    },
                  ),
                  const Text(
                    'Se souvenir de moi',
                    style: TextStyle(color: Colors.white), // Texte en blanc
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Bouton de Connexion par Email/Mot de Passe
              _isLoading
                  ? const CircularProgressIndicator(
                      color: Colors.white, // Spinner en blanc
                    )
                  : ElevatedButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          _formKey.currentState!.save();
                          if (!mounted) return;
                          setState(() {
                            _isLoading = true;
                          });
                          try {
                            // Connexion avec email et mot de passe
                            await authService.signInWithEmailAndPassword(
                              _email,
                              _password,
                              rememberDevice: _rememberMe,
                            );

                            // Fermer la superposition et naviguer
                            widget.onClose();
                            Navigator.pushReplacementNamed(context, '/friends');
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erreur : $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } finally {
                            if (!mounted) return;
                            setState(() {
                              _isLoading = false;
                            });
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue, // Couleur du bouton
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text(
                        'Login',
                        style: TextStyle(color: Colors.white), // Texte en blanc
                      ),
                    ),
              const SizedBox(height: 16),
              // Bouton de Connexion avec Google
              _isLoading
                  ? Container()
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.login, color: Colors.white),
                      label: const Text(
                        'Se connecter avec Google',
                        style: TextStyle(color: Colors.white), // Texte en blanc
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red, // Couleur différente pour Google
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        if (!mounted) return;
                        setState(() {
                          _isLoading = true;
                        });
                        try {
                          bool googleSignedIn = await authService.signInWithGoogle();
                          if (googleSignedIn) {
                            // Fermer la superposition et naviguer
                            widget.onClose();
                            Navigator.pushReplacementNamed(context, '/friends');
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Connexion Google requise.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Erreur : $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } finally {
                          if (!mounted) return;
                          setState(() {
                            _isLoading = false;
                          });
                        }
                      },
                    ),
              const SizedBox(height: 16),
              // Lien vers la Page d'Inscription
              TextButton(
                onPressed: () {
                  // Fermer la superposition et naviguer vers l'inscription
                  widget.onClose();
                  Navigator.pushNamed(context, '/register');
                },
                child: const Text(
                  'Vous n\'avez pas de compte ? Inscrivez-vous',
                  style: TextStyle(color: Colors.white), // Texte en blanc
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Widget HoverIcon
class HoverIcon extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final String? route;
  final VoidCallback? onTap;

  const HoverIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    this.route,
    this.onTap,
  });

  @override
  _HoverIconState createState() => _HoverIconState();
}

class _HoverIconState extends State<HoverIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTap: () {
          if (widget.route != null) {
            Navigator.pushNamed(context, widget.route!);
          } else if (widget.onTap != null) {
            widget.onTap!();
          }
        },
        child: MouseRegion(
          onEnter: (_) {
            setState(() {
              _isHovered = true;
            });
          },
          onExit: (_) {
            setState(() {
              _isHovered = false;
            });
          },
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Icon(
              widget.icon,
              size: _isHovered ? 40 : 32, // Agrandir la taille au survol
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

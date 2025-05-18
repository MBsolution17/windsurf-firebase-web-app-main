import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AppColors {
  static final Color primaryBlue = const Color.fromARGB(255, 77, 77, 77);
  static final Color accentColor = const Color.fromARGB(255, 139, 139, 139);
}

class ContactPageLanding extends StatefulWidget {
  const ContactPageLanding({Key? key}) : super(key: key);

  @override
  _ContactPageLandingState createState() => _ContactPageLandingState();
}

class _ContactPageLandingState extends State<ContactPageLanding> {
  final ScrollController _scrollController = ScrollController();
  double _backgroundOpacity = 0.6;
  bool _isScrolled = false;

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
      _isScrolled = offset > 20;
    });
  }

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'mathieu.blanc@boundly.fr',
    );
    
    try {
      await launchUrl(emailUri);
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ouvrir votre application de messagerie'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _launchPhone() async {
    final Uri phoneUri = Uri(
      scheme: 'tel',
      path: '0630684468',
    );
    
    try {
      await launchUrl(phoneUri);
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ouvrir votre application téléphone'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _launchInstagram() async {
    final Uri instagramUri = Uri.parse('https://www.instagram.com/mathieu.blapro/');
    
    try {
      await launchUrl(instagramUri, mode: LaunchMode.externalApplication);
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ouvrir Instagram'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _launchLinkedIn() async {
    final Uri linkedinUri = Uri.parse('https://www.linkedin.com/in/mathieu-blanc-408b37357/');
    
    try {
      await launchUrl(linkedinUri, mode: LaunchMode.externalApplication);
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ouvrir LinkedIn'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _launchWebsite() async {
    final Uri websiteUri = Uri.parse('https://boundly.fr');
    
    try {
      await launchUrl(websiteUri, mode: LaunchMode.externalApplication);
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d\'ouvrir le site web'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Contact',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.black.withOpacity(_isScrolled ? 0.7 : 0.0),
        elevation: _isScrolled ? 4 : 0,
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
      ),
      body: Stack(
        children: [
          // Image de fond avec opacité
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.png',
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(_backgroundOpacity),
              colorBlendMode: BlendMode.darken,
            ),
          ),
          
          // Contenu principal
          Center(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 100),
                    
                    // Logo ou image de marque
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primaryBlue,
                            AppColors.accentColor,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.chat_outlined,
                        color: Colors.white,
                        size: 60,
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Titre
                    const Text(
                      'Contact',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    
                    const SizedBox(height: 50),
                    
                    // Email
                    _buildContactCard(
                      icon: Icons.email_outlined,
                      title: 'mathieu.blanc@boundly.fr',
                      gradient: [Colors.indigo, Colors.blue],
                      onTap: _launchEmail,
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Téléphone
                    _buildContactCard(
                      icon: Icons.phone_outlined,
                      title: '06 30 68 44 68',
                      gradient: [Colors.green.shade700, Colors.lightGreen],
                      onTap: _launchPhone,
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Instagram
                    _buildContactCard(
                      icon: Icons.camera_alt_outlined,
                      title: 'Instagram',
                      gradient: [Colors.purple, Colors.pink],
                      onTap: _launchInstagram,
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // LinkedIn
                    _buildContactCard(
                      icon: Icons.business,
                      title: 'LinkedIn',
                      gradient: [Colors.blue.shade800, Colors.blue.shade400],
                      onTap: _launchLinkedIn,
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Website
                    _buildContactCard(
                      icon: Icons.web,
                      title: 'boundly.fr',
                      gradient: [Colors.teal.shade700, Colors.teal.shade300],
                      onTap: _launchWebsite,
                    ),
                    
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: gradient[0].withOpacity(0.3),
          highlightColor: gradient[0].withOpacity(0.1),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.6),
                  Colors.black.withOpacity(0.4),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: gradient[0].withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      icon,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white.withOpacity(0.7),
                    size: 16,
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
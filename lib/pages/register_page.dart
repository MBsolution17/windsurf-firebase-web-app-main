import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../services/auth_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreeToTerms = false;
  
  // Indicateur de force du mot de passe
  double _passwordStrength = 0;
  String _passwordStrengthText = 'Entrez un mot de passe';
  Color _passwordStrengthColor = Colors.grey;
  
  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
  
  void _checkPasswordStrength(String password) {
    setState(() {
      if (password.isEmpty) {
        _passwordStrength = 0;
        _passwordStrengthText = 'Entrez un mot de passe';
        _passwordStrengthColor = Colors.grey;
        return;
      }
      
      double strength = 0;
      
      // Critères de base
      if (password.length >= 6) strength += 0.2;
      if (password.length >= 8) strength += 0.2;
      
      // Complexité
      if (password.contains(RegExp(r'[A-Z]'))) strength += 0.2; // Majuscules
      if (password.contains(RegExp(r'[0-9]'))) strength += 0.2; // Chiffres
      if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength += 0.2; // Caractères spéciaux
      
      // Mise à jour des indicateurs
      _passwordStrength = strength;
      
      if (strength < 0.3) {
        _passwordStrengthText = 'Faible';
        _passwordStrengthColor = Colors.red;
      } else if (strength < 0.7) {
        _passwordStrengthText = 'Moyen';
        _passwordStrengthColor = Colors.orange;
      } else {
        _passwordStrengthText = 'Fort';
        _passwordStrengthColor = Colors.green;
      }
    });
  }
  
  Future<void> _register() async {
    if (!_formKey.currentState!.validate() || !_agreeToTerms) {
      if (!_agreeToTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vous devez accepter les conditions d\'utilisation pour continuer'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
    _formKey.currentState!.save();
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Créer l'utilisateur avec email et mot de passe
      await authService.createUserWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );
      
      // Redirection vers la page de profil ou la page d'accueil après inscription
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'inscription: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Background dégradé
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E3C56),
              Color(0xFF0F1B2B),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo et titre
                    const Text(
                      'Boundly',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Sous-titre
                    const Text(
                      'Créez votre compte pour accéder à la plateforme',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    
                    // Carte du formulaire
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF263238),
                            Color(0xFF1C262B),
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
                      child: _isLoading 
                        ? const Center(
                            child: Column(
                              children: [
                                CircularProgressIndicator(color: Color(0xFF90A4AE)),
                                SizedBox(height: 24),
                                Text(
                                  'Création de votre compte...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          )
                        : Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // En-tête du formulaire
                                const Text(
                                  'Inscription',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Veuillez remplir tous les champs pour créer votre compte',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                
                                // Ligne avec Prénom et Nom
                                Row(
                                  children: [
                                    // Prénom
                                    Expanded(
                                      child: TextFormField(
                                        controller: _firstNameController,
                                        style: const TextStyle(color: Colors.white),
                                        decoration: InputDecoration(
                                          labelText: 'Prénom',
                                          labelStyle: const TextStyle(color: Color(0xFF90A4AE)),
                                          hintText: 'Votre prénom',
                                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                          prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF90A4AE)),
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
                                          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Veuillez entrer votre prénom';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Nom
                                    Expanded(
                                      child: TextFormField(
                                        controller: _lastNameController,
                                        style: const TextStyle(color: Colors.white),
                                        decoration: InputDecoration(
                                          labelText: 'Nom',
                                          labelStyle: const TextStyle(color: Color(0xFF90A4AE)),
                                          hintText: 'Votre nom',
                                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                          prefixIcon: const Icon(Icons.person, color: Color(0xFF90A4AE)),
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
                                          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Veuillez entrer votre nom';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                
                                // Email
                                TextFormField(
                                  controller: _emailController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: 'Email',
                                    labelStyle: const TextStyle(color: Color(0xFF90A4AE)),
                                    hintText: 'votre.email@exemple.com',
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
                                    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
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
                                
                                // Mot de passe
                                TextFormField(
                                  controller: _passwordController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: 'Mot de passe',
                                    labelStyle: const TextStyle(color: Color(0xFF90A4AE)),
                                    hintText: 'Votre mot de passe',
                                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                    prefixIcon: const Icon(Icons.lock, color: Color(0xFF90A4AE)),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                        color: const Color(0xFF90A4AE),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
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
                                    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                  ),
                                  obscureText: _obscurePassword,
                                  onChanged: _checkPasswordStrength,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Veuillez entrer un mot de passe';
                                    }
                                    if (value.length < 6) {
                                      return 'Le mot de passe doit contenir au moins 6 caractères';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                
                                // Indicateur de force du mot de passe
                                Row(
                                  children: [
                                    Expanded(
                                      child: LinearProgressIndicator(
                                        value: _passwordStrength,
                                        backgroundColor: Colors.grey.shade800,
                                        color: _passwordStrengthColor,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _passwordStrengthText,
                                      style: TextStyle(
                                        color: _passwordStrengthColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                
                                // Suggestions de mot de passe
                                Text(
                                  'Le mot de passe doit contenir au moins 6 caractères, incluant idéalement des majuscules, chiffres et caractères spéciaux.',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                
                                // Confirmation mot de passe
                                TextFormField(
                                  controller: _confirmPasswordController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    labelText: 'Confirmer mot de passe',
                                    labelStyle: const TextStyle(color: Color(0xFF90A4AE)),
                                    hintText: 'Confirmez votre mot de passe',
                                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                    prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF90A4AE)),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                                        color: const Color(0xFF90A4AE),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscureConfirmPassword = !_obscureConfirmPassword;
                                        });
                                      },
                                    ),
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
                                    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                  ),
                                  obscureText: _obscureConfirmPassword,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Veuillez confirmer votre mot de passe';
                                    }
                                    if (value != _passwordController.text) {
                                      return 'Les mots de passe ne correspondent pas';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 24),
                                
                                // Conditions d'utilisation
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _agreeToTerms,
                                      onChanged: (value) {
                                        setState(() {
                                          _agreeToTerms = value!;
                                        });
                                      },
                                      fillColor: MaterialStateProperty.resolveWith<Color>(
                                        (Set<MaterialState> states) {
                                          if (states.contains(MaterialState.selected)) {
                                            return const Color(0xFF607D8B);
                                          }
                                          return Colors.transparent;
                                        },
                                      ),
                                      side: const BorderSide(color: Color(0xFF90A4AE)),
                                    ),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                                          children: const [
                                            TextSpan(text: 'J\'accepte les '),
                                            TextSpan(
                                              text: 'Conditions d\'utilisation',
                                              style: TextStyle(
                                                color: Color(0xFF90A4AE),
                                                fontWeight: FontWeight.bold,
                                                decoration: TextDecoration.underline,
                                              ),
                                            ),
                                            TextSpan(text: ' et la '),
                                            TextSpan(
                                              text: 'Politique de confidentialité',
                                              style: TextStyle(
                                                color: Color(0xFF90A4AE),
                                                fontWeight: FontWeight.bold,
                                                decoration: TextDecoration.underline,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 32),
                                
                                // Bouton d'inscription
                                ElevatedButton(
                                  onPressed: _register,
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
                                    'Créer mon compte',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                
                                // Séparateur
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
                                const SizedBox(height: 16),
                                
                                // Connexion avec Google
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    setState(() {
                                      _isLoading = true;
                                    });
                                    try {
                                      final authService = Provider.of<AuthService>(context, listen: false);
                                      bool googleSignedIn = await authService.signInWithGoogle();
                                      if (googleSignedIn && mounted) {
                                        Navigator.pushReplacementNamed(context, '/dashboard');
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Erreur: $e'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _isLoading = false;
                                        });
                                      }
                                    }
                                  },
                                  icon: const Icon(FontAwesomeIcons.google, size: 20),
                                  label: const Text('Continuer avec Google'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Color(0xFF607D8B)),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    minimumSize: const Size(double.infinity, 54),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ),
                    
                    // Lien vers la page de connexion
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Vous avez déjà un compte? ',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            // Retour à la landing page avec le modal de connexion ouvert
                            Navigator.pushReplacementNamed(
                              context, 
                              '/',
                              arguments: {'openLoginModal': true},
                            );
                          },
                          child: const Text(
                            'Connectez-vous',
                            style: TextStyle(
                              color: Color(0xFF90A4AE),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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
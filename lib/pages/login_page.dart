// lib/pages/login_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  bool _rememberMe = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Charger la préférence "Se souvenir de moi" au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authService = Provider.of<AuthService>(context, listen: false);
      setState(() {
        _rememberMe = authService.rememberMe;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        backgroundColor: Colors.indigo,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Champ Email
                      TextFormField(
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
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
                        decoration: const InputDecoration(labelText: 'Mot de Passe'),
                        obscureText: true,
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
                            onChanged: (value) {
                              if (!mounted) return;
                              setState(() {
                                _rememberMe = value!;
                              });
                            },
                          ),
                          const Text('Se souvenir de moi'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Bouton de Connexion par Email/Mot de Passe
                      ElevatedButton(
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

                              Navigator.pushReplacementNamed(context, '/profile'); // Changé pour '/profile' au lieu de '/friends'
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
                        child: const Text('Login'),
                      ),
                      const SizedBox(height: 16),
                      // Bouton de Connexion avec Google
                      ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text('Se connecter avec Google'),
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
                              Navigator.pushReplacementNamed(context, '/profile'); // Changé pour '/profile'
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
                          Navigator.pushNamed(context, '/register');
                        },
                        child: const Text('Vous n\'avez pas de compte ? Inscrivez-vous'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
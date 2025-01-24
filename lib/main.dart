// lib/main.dart

import 'package:firebase_web_app/services/speech_recognition_js.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Import des pages
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/chat_page.dart';
import 'pages/friends_page.dart';
import 'pages/landing_page.dart';
import 'pages/task_tracker_page.dart';
import 'pages/document_page.dart';
import 'pages/voice_assistant_page.dart';
import 'pages/calendar_page.dart';
import 'pages/analytics_page.dart';
import 'pages/contact_page.dart'; // Import de ContactPage

// Import des services
import 'services/channel_list_page.dart';
import 'services/create_channel_page.dart';
import 'services/auth_service.dart';
import 'services/ai_service.dart';
import 'services/web_speech_recognition_service.dart';

// Import des widgets
import 'widgets/auth_guard.dart';
import 'firebase_options.dart';

Future<void> initializeFirebase() async {
  try {
    print('Starting Firebase initialization...');

    final app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    print('Firebase core initialized with app name: ${app.name}');

    // Configuration de Firestore
    await FirebaseFirestore.instance.enablePersistence();
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      sslEnabled: true,
    );

    print('Firestore settings configured');
    print('Firebase initialization completed successfully');
  } catch (e, stackTrace) {
    print('Error during Firebase initialization: $e');
    print('Stack trace: $stackTrace');
    rethrow;
  }
}

Future<void> main() async {
  // Charger les variables d'environnement
  await dotenv.load(fileName: ".env");

  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  await initializeFirebase();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => AIService()), // ChangeNotifierProvider pour AIService
        Provider(create: (_) => WebSpeechRecognitionService()), // Utiliser Provider au lieu de ChangeNotifierProvider
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boundly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.purple,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // Utiliser le StreamBuilder pour gérer l'état d'authentification
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Afficher un indicateur de chargement pendant la vérification de l'état d'authentification
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // Si l'utilisateur est authentifié, naviguer vers la DashboardPage
          if (snapshot.hasData && snapshot.data != null) {
            return const DashboardPage();
          }

          // Sinon, naviguer vers la LandingPage (ou LoginPage selon votre logique)
          return const LandingPage();
        },
      ),
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/dashboard': (context) => const AuthGuard(child: DashboardPage()),
        '/channel_list': (context) => const AuthGuard(child: ChannelListPage()),
        '/create_channel': (context) => const AuthGuard(child: CreateChannelPage()),
        '/friends': (context) => const AuthGuard(child: FriendsPage()),
        '/task_tracker': (context) => const AuthGuard(child: TaskTrackerPage()),
        '/documents': (context) => const AuthGuard(child: DocumentPage()),
        '/voice_assistant': (context) => const AuthGuard(child: VoiceAssistantPage()),
        '/calendar': (context) => const AuthGuard(child: CalendarPage()),
        '/analytics': (context) => const AuthGuard(child: AnalyticsPage()), // Route ajoutée
        '/contact_page': (context) => const AuthGuard(child: ContactPage()), // Route pour ContactPage
        // '/chat': (context) => const ChatPage(), // Supprimé pour éviter les erreurs
        // Ajoutez les autres routes ici si nécessaire
      },
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    if (settings.name == '/chat') {
      final args = settings.arguments;
      if (args is Map<String, dynamic>) {
        final channelId = args['channelId'];
        final channelName = args['channelName'];
        final isVoiceChannel = args['isVoiceChannel'] ?? false;
        if (channelId != null && channelName != null) {
          return MaterialPageRoute(
            builder: (context) => AuthGuard(
              child: ChatPage(
                channelId: channelId,
                channelName: channelName,
                isVoiceChannel: isVoiceChannel,
              ),
            ),
          );
        }
      }
      // Si les arguments sont manquants ou incorrects, afficher une page d'erreur
      return MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Erreur de Navigation')),
          body: const Center(child: Text('Arguments manquants pour la page de chat.')),
        ),
      );
    }
    // Si la route n'est pas gérée, retourner une page d'erreur ou null
    return MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Page non trouvée')),
        body: const Center(child: Text('La page que vous recherchez n\'existe pas.')),
      ),
    );
  }
}

// lib/main.dart

import 'package:firebase_web_app/services/speech_recognition_js.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Import pour l'initialisation des locales
import 'package:intl/date_symbol_data_local.dart';

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
import 'pages/contact_page.dart';
import 'pages/profile_page.dart';
import 'pages/create_workspace_page.dart';

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
  await dotenv.load(fileName: ".env");

  // Assurez-vous que Flutter est initialisé.
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialiser les données de localisation pour le français.
  await initializeDateFormatting('fr_FR', null);
  
  usePathUrlStrategy();

  await initializeFirebase();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => AIService()),
        Provider(create: (_) => WebSpeechRecognitionService()),
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
      home: const AuthCheck(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/channel_list': (context) =>
            AuthGuard(child: const ChannelListPage()),
        '/create_channel': (context) =>
            AuthGuard(child: const CreateChannelPage()),
        '/friends': (context) => AuthGuard(child: const FriendsPage()),
        '/voice_assistant': (context) =>
            AuthGuard(child: const VoiceAssistantPage()),
        '/analytics': (context) => AuthGuard(child: const AnalyticsPage()),
        '/profile_page': (context) => AuthGuard(child: const ProfilePage()),
        '/create_workspace': (context) => CreateWorkspacePage(), // Sans 'const'
      },
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    if (settings.name == '/documents') {
      final args = settings.arguments as Map<String, dynamic>?;
      if (args != null && args.containsKey('workspaceId')) {
        final workspaceId = args['workspaceId'] as String;
        return MaterialPageRoute(
          builder: (context) => AuthGuard(
            child: DocumentPage(workspaceId: workspaceId),
          ),
        );
      }
      return MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Erreur de Navigation')),
          body: const Center(child: Text('Paramètres manquants pour DocumentPage')),
        ),
      );
    }

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
      return MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Erreur de Navigation')),
          body: const Center(child: Text('Arguments manquants pour la page de chat.')),
        ),
      );
    }

    if (settings.name == '/contact_page') {
      final args = settings.arguments as Map<String, dynamic>?;
      if (args != null && args.containsKey('workspaceId')) {
        final workspaceId = args['workspaceId'] as String;
        return MaterialPageRoute(
          builder: (context) => AuthGuard(
            child: ContactPage(workspaceId: workspaceId),
          ),
        );
      }
      return MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Erreur de Navigation')),
          body: const Center(child: Text('Paramètres manquants pour ContactPage')),
        ),
      );
    }

    if (settings.name == '/task_tracker') {
      final args = settings.arguments as Map<String, dynamic>?;
      if (args != null && args.containsKey('workspaceId')) {
        final workspaceId = args['workspaceId'] as String;
        return MaterialPageRoute(
          builder: (context) => AuthGuard(
            child: TaskTrackerPage(workspaceId: workspaceId),
          ),
        );
      }
      return MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Erreur de Navigation')),
          body: const Center(child: Text('Paramètres manquants pour TaskTrackerPage')),
        ),
      );
    }

    if (settings.name == '/calendar') {
      final args = settings.arguments as Map<String, dynamic>?;
      if (args != null && args.containsKey('workspaceId')) {
        final workspaceId = args['workspaceId'] as String;
        return MaterialPageRoute(
          builder: (context) => AuthGuard(
            child: CalendarPage(workspaceId: workspaceId),
          ),
        );
      }
      return MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Erreur de Navigation')),
          body: const Center(child: Text('Paramètres manquants pour CalendarPage')),
        ),
      );
    }

    // Page 404
    return MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Page non trouvée')),
        body: const Center(child: Text('La page que vous recherchez n\'existe pas.')),
      ),
    );
  }
}

class AuthCheck extends StatelessWidget {
  const AuthCheck({super.key});

  Future<String?> _getUserWorkspace() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (userDoc.exists && userDoc.data() != null) {
      final data = userDoc.data() as Map<String, dynamic>;
      return data['workspaceId'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData) {
          return const LandingPage();
        }

        return FutureBuilder<String?>(
          future: _getUserWorkspace(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!snapshot.hasData || snapshot.data == null) {
              return CreateWorkspacePage(); // Sans 'const'
            }

            return DashboardPage(workspaceId: snapshot.data!);
          },
        );
      },
    );
  }
}

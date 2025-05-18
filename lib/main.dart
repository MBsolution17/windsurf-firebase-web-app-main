import 'package:firebase_web_app/services/speech_recognition_js.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'controllers/onboarding_controller.dart';
import 'package:intl/date_symbol_data_local.dart';
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
import 'pages/documentation_page.dart';
import 'pages/contact_page_landing.dart';
import 'pages/features_page.dart' as features;
import 'pages/pricingpage.dart' as pricing;
import 'pages/about_page.dart';
import 'services/channel_list_page.dart';
import 'services/create_channel_page.dart';
import 'services/auth_service.dart';
import 'services/ai_service.dart';
import 'services/web_speech_recognition_service.dart';
import 'widgets/auth_guard.dart';
import 'firebase_options.dart';
import 'theme_provider.dart';

Future<void> initializeFirebase() async {
  try {
    print('Starting Firebase initialization...');

    final app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    print('Firebase core initialized with app name: ${app.name}');

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

  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  usePathUrlStrategy();

  await initializeFirebase();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => AIService()),
        Provider(create: (_) => WebSpeechRecognitionService()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => OnboardingController()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Boundly',
          debugShowCheckedModeBanner: false,
          theme: themeProvider.themeData,
          home: const AuthCheck(),
          routes: {
            '/login': (context) => const LoginPage(),
            '/register': (context) => const RegisterPage(),
            '/channel_list': (context) => AuthGuard(child: const ChannelListPage()),
            '/create_channel': (context) => AuthGuard(child: const CreateChannelPage()),
            '/friends': (context) => AuthGuard(child: const FriendsPage()),
            '/voice_assistant': (context) => AuthGuard(child: const VoiceAssistantPage()),
            '/profile_page': (context) => AuthGuard(child: const ProfilePage()),
            '/create_workspace': (context) => CreateWorkspacePage(),
            '/documentation': (context) => const DocumentationPage(),
            '/contact_landing': (context) => const ContactPageLanding(),
            '/features': (context) => const features.FeaturesPage(),
            '/pricing': (context) => const pricing.PricingPage(),
            '/about': (context) => const AboutPage(),
          },
          onGenerateRoute: _onGenerateRoute,
        );
      },
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final String? routeName = settings.name;
    final args = settings.arguments as Map<String, dynamic>?;

    if (routeName == '/dashboard') {
      final workspaceId = args?['workspaceId'] as String?;
      if (workspaceId == null || workspaceId.isEmpty) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Erreur')),
            body: const Center(child: Text('Workspace ID manquant')),
          ),
        );
      }
      return MaterialPageRoute(
        builder: (context) => AuthGuard(child: DashboardPage(workspaceId: workspaceId)),
      );
    }

    Future<String?> getWorkspaceId() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists && userDoc.data() != null) {
          return userDoc.data()!['workspaceId'] as String?;
        }
      }
      return null;
    }

    if (routeName == '/analytics') {
      return MaterialPageRoute(
        builder: (context) => FutureBuilder<String?>(
          future: getWorkspaceId(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (!snapshot.hasData || snapshot.data == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Erreur')),
                body: const Center(child: Text('Workspace non trouvé')),
              );
            }
            return AuthGuard(
              child: AnalyticsPage(workspaceId: snapshot.data!),
            );
          },
        ),
      );
    }

    if (routeName == '/documents') {
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

    if (routeName == '/chat') {
      if (args != null) {
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

    if (routeName == '/contact') {
      if (args != null && args.containsKey('workspaceId')) {
        final workspaceId = args['workspaceId'] as String;
        return MaterialPageRoute(
          builder: (context) => AuthGuard(
            child: ContactPage(workspaceId: workspaceId),
          ),
        );
      }
      
      return MaterialPageRoute(
        builder: (context) => FutureBuilder<String?>(
          future: getWorkspaceId(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (!snapshot.hasData || snapshot.data == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Erreur')),
                body: const Center(child: Text('Workspace non trouvé, impossible d\'accéder à la page de contact')),
              );
            }
            return AuthGuard(
              child: ContactPage(workspaceId: snapshot.data!),
            );
          },
        ),
      );
    }

    if (routeName == '/task_tracker') {
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

    if (routeName == '/calendar') {
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

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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
              return CreateWorkspacePage();
            }

            return DashboardPage(workspaceId: snapshot.data!);
          },
        );
      },
    );
  }
}
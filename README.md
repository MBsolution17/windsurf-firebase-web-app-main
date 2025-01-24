# Firebase Web Application

## Project Setup

### Prerequisites
- Flutter SDK
- Firebase Account
- Web Browser

### Firebase Configuration
1. Create a new Firebase project in the Firebase Console
2. Register a new web app in Firebase
3. Replace placeholders in `lib/firebase_options.dart` with your Firebase project credentials

### Installation
1. Clone the repository
2. Run `flutter pub get`
3. Configure Firebase:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

### Running the App
```bash
flutter run -d chrome
```

### Features
- Firebase Core Integration
- Firebase Authentication
- Firestore Database
- Firebase Analytics

### Troubleshooting
- Ensure all dependencies are installed
- Check Firebase configuration
- Verify web platform is enabled

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/user_activity_screen.dart';
import 'screens/nickname_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase başlatma ayarlarını yapılandır
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Cihaz dilini al
  final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
  final languageCode = deviceLocale.languageCode;

  // Desteklenen diller listesi
  const supportedLanguages = ['en', 'tr'];

  // Cihaz dili desteklenen diller listesinde var mı kontrol et
  if (supportedLanguages.contains(languageCode)) {
    FirebaseAuth.instance.setLanguageCode(languageCode);
  } else {
    // Varsayılan olarak İngilizce kullan
    FirebaseAuth.instance.setLanguageCode('en');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WhySup',
      // Localization desteği ekle
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'), // İngilizce
        Locale('tr'), // Türkçe
      ],
      // Cihazın dilini kullan, eğer desteklemiyorsa varsayılan olarak İngilizce kullan
      locale: _getDeviceLocale(),
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueGrey[900],
        colorScheme: ColorScheme.dark(
          primary: Colors.blueGrey[700]!,
          secondary: Colors.blue[700]!,
          surface: Colors.grey[900]!,
          background: Colors.black,
          onBackground: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blueGrey[900],
          foregroundColor: Colors.white,
        ),
        cardTheme: CardTheme(
          color: Colors.grey[850],
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.blue[700],
          ),
        ),
        dialogTheme: DialogTheme(
          backgroundColor: Colors.grey[900],
        ),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasData) {
                  final user = snapshot.data!;
                  // Kullanıcının nickname'i var mı kontrol et
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .get(),
                    builder: (context, userSnapshot) {
                      if (userSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      // Eğer kullanıcı dokümanı yoksa veya nickname yoksa, nickname ekranına yönlendir
                      if (!userSnapshot.hasData ||
                          !userSnapshot.data!.exists ||
                          !(userSnapshot.data!.data() as Map<String, dynamic>)
                              .containsKey('nickname')) {
                        return const NicknameScreen();
                      }

                      // Nickname varsa ana ekrana yönlendir
                      return const UserActivityScreen();
                    },
                  );
                }

                return const LoginScreen();
              },
            ),
      },
    );
  }

  Locale _getDeviceLocale() {
    // Cihaz dilini al
    final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final languageCode = deviceLocale.languageCode;

    // Desteklenen diller listesi
    const supportedLanguages = ['en', 'tr'];

    // Cihaz dili desteklenen diller listesinde var mı kontrol et
    if (supportedLanguages.contains(languageCode)) {
      return Locale(languageCode);
    }

    // Desteklenmeyen diller için varsayılan olarak İngilizce kullan
    return const Locale('en');
  }
}

// Diğer sınıflar kaldırıldı çünkü artık kendi dosyalarında tanımlı

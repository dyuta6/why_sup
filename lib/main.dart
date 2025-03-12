import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  // Firebase için varsayılan dil ayarını yap
  FirebaseAuth.instance.setLanguageCode('tr');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WhySup',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
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
}

// Diğer sınıflar kaldırıldı çünkü artık kendi dosyalarında tanımlı

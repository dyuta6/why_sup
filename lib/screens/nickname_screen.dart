import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'user_activity_screen.dart';
import 'profile_image_screen.dart';
import 'login_screen.dart';
import 'package:flutter/services.dart';

class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key});

  @override
  _NicknameScreenState createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final _nicknameController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkPhoneNumber();
  }

  Future<void> _checkPhoneNumber() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      print('Firebase Authentication telefon numarası: ${user.phoneNumber}');

      // Kullanıcının telefon numarasını Firestore'da kontrol et
      final userDocRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final userDoc = await userDocRef.get();

      if (userDoc.exists) {
        final userData = userDoc.data();
        final phoneNumber = userData?['phoneNumber'] as String?;
        print('Firestore\'daki telefon numarası: $phoneNumber');

        // Telefon numarası yoksa ve Firebase Auth'da telefon numarası varsa kaydet
        if ((phoneNumber == null || phoneNumber.isEmpty) &&
            user.phoneNumber != null) {
          await userDocRef.update({
            'phoneNumber': user.phoneNumber,
            'lastUpdated': FieldValue.serverTimestamp(),
          });

          print(
              'Firebase Auth\'dan telefon numarası Firestore\'a kaydedildi: ${user.phoneNumber}');

          // Doğrulama için tekrar oku
          final updatedDoc = await userDocRef.get();
          final updatedPhoneNumber =
              updatedDoc.data()?['phoneNumber'] as String?;
          print('Güncelleme sonrası telefon numarası: $updatedPhoneNumber');
        }
      } else {
        // Kullanıcı dökümanı yoksa ve telefon numarası varsa yeni döküman oluştur
        if (user.phoneNumber != null) {
          await userDocRef.set({
            'userId': user.uid,
            'phoneNumber': user.phoneNumber,
            'createdAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
            'isAnonymous': user.isAnonymous,
          });

          print(
              'Yeni kullanıcı dökümanı oluşturuldu, telefon: ${user.phoneNumber}');
        }
      }
    }
  }

  Future<void> _saveNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.nicknameEmptyError)),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Önce bu kullanıcı adının kullanılıp kullanılmadığını kontrol et
      final nicknameQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('nickname', isEqualTo: nickname)
          .get();

      if (nicknameQuery.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.nicknameTakenError),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          // Telefon numarasını al
          String? phoneNumber = user.phoneNumber;
          print('Nickname kaydedilirken telefon numarası: $phoneNumber');

          // Firestore'a kaydet
          final userDocRef =
              FirebaseFirestore.instance.collection('users').doc(user.uid);
          final userDoc = await userDocRef.get();

          Map<String, dynamic> userData = {
            'nickname': nickname,
            'userId': user.uid,
            'isAnonymous': user.isAnonymous,
            'lastUpdated': FieldValue.serverTimestamp(),
          };

          // Telefon numarasını ekle (eğer varsa)
          if (phoneNumber != null && phoneNumber.isNotEmpty) {
            userData['phoneNumber'] = phoneNumber;
          }

          if (!userDoc.exists) {
            // Yeni döküman oluştur
            userData['createdAt'] = FieldValue.serverTimestamp();
            await userDocRef.set(userData);
            print('Yeni kullanıcı dökümanı oluşturuldu: $userData');
          } else {
            // Varolan dökümanı güncelle
            await userDocRef.set(userData, SetOptions(merge: true));
            print('Mevcut kullanıcı dökümanı güncellendi: $userData');
          }

          // Doğrulama için tekrar oku
          final updatedDoc = await userDocRef.get();
          print('Kaydedilen döküman: ${updatedDoc.data()}');

          // Firebase Auth profilini güncellemeyi dene
          // Anonim kullanıcılarda sorun oluşturduğu için bu işlemi es geçiyoruz
          try {
            // Sadece anonim olmayan kullanıcılar için profil güncellemesi yap
            if (!user.isAnonymous) {
              await user.updateDisplayName(nickname);
            }
          } catch (profileError) {
            print('Profil güncelleme hatası (önemli değil): $profileError');
            // Profil güncellemesi başarısız olsa bile devam et
          }

          if (mounted) {
            // Profil resmi seçme ekranına yönlendir
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const ProfileImageScreen(),
              ),
            );
          }
        } catch (firestoreError) {
          print('Firestore kayıt hatası: $firestoreError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.nicknameSaveError),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.sessionClosedError),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.genericError}: $e'),
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
    final localizations = AppLocalizations.of(context)!;

    return WillPopScope(
      onWillPop: () async {
        // Önce Firebase Auth'dan çıkış yap
        await FirebaseAuth.instance.signOut();

        // Login ekranına yönlendir
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const LoginScreen(),
            ),
            (route) => false,
          );
        }
        return false; // Varsayılan geri tuşu davranışını devre dışı bırak
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(localizations.appTitle),
          centerTitle: true,
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          automaticallyImplyLeading: false, // Geri butonunu gizle
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      localizations.welcome,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      localizations.nicknameDescription,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _nicknameController,
                      decoration: InputDecoration(
                        labelText: localizations.nicknameLabel,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.person),
                      ),
                      maxLength: 20,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () async {
                                  // Önce Firebase Auth'dan çıkış yap
                                  await FirebaseAuth.instance.signOut();

                                  if (mounted) {
                                    // Login ekranına yönlendir ve mevcut sayfaları temizle
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const LoginScreen(),
                                      ),
                                      (route) => false,
                                    );
                                  }
                                },
                          child: Text(localizations.logoutButton),
                        ),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _saveNickname,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(localizations.continueButton),
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

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }
}

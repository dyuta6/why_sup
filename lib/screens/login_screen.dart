import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'nickname_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _smsController = TextEditingController();
  bool _isLoading = false;
  String? _verificationId;
  int? _resendToken;

  Future<void> _verifyPhone() async {
    // Klavyeyi kapat
    FocusScope.of(context).unfocus();

    if (_phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.phoneEmptyError)),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Telefon numarasını E.164 formatına dönüştür
    String phoneNumber = _phoneController.text.trim();

    // Eğer numara + ile başlamıyorsa hata ver
    if (!phoneNumber.startsWith('+')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.invalidPhoneFormat)),
      );
      setState(() {
        _isLoading = false;
      });
      return;
    }

    print('Doğrulama için kullanılacak telefon numarası: $phoneNumber');

    try {
      // İşlem öncesi mevcut kullanıcı durumunu kontrol et
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        print(
            'Aktif oturum var, önce çıkış yapılıyor. Aktif kullanıcı: ${currentUser.uid}');
        await FirebaseAuth.instance.signOut();
        // Oturumun kapanması için kısa bir bekleme süresi
        await Future.delayed(const Duration(milliseconds: 500));
        print('Çıkış yapıldı, telefon doğrulama başlatılıyor');
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Android'de SMS otomatik doğrulandığında buraya girer
          print('Otomatik doğrulama tamamlandı');
          setState(() {
            _isLoading = true;
          });

          try {
            final userCredential =
                await FirebaseAuth.instance.signInWithCredential(credential);
            print(
                'Otomatik doğrulama: Kullanıcı başarıyla giriş yaptı: ${userCredential.user?.uid}');
            print(
                'Otomatik doğrulama: Kullanıcı telefon numarası: ${userCredential.user?.phoneNumber}');

            // Telefon numarasını Users koleksiyonuna kaydet
            if (userCredential.user != null) {
              String phoneNumber = _phoneController.text.trim();

              // Telefon numarasını normalize et
              if (!phoneNumber.startsWith('+')) {
                if (phoneNumber.startsWith('0')) {
                  phoneNumber = phoneNumber.substring(1);
                }
                phoneNumber = '+90$phoneNumber';
              }

              // Eğer kontrolcüden alınan numara boşsa Firebase Auth'dan alalım
              if (phoneNumber.isEmpty &&
                  userCredential.user?.phoneNumber != null) {
                phoneNumber = userCredential.user!.phoneNumber!;
              }

              print(
                  'Otomatik doğrulama: Kaydedilecek telefon numarası: $phoneNumber');

              // Users koleksiyonunu kontrol et ve gerekirse oluştur
              final userDocRef = FirebaseFirestore.instance
                  .collection('users')
                  .doc(userCredential.user!.uid);
              final userDoc = await userDocRef.get();

              if (!userDoc.exists) {
                // Döküman yoksa oluştur
                await userDocRef.set({
                  'userId': userCredential.user!.uid,
                  'phoneNumber': phoneNumber,
                  'createdAt': FieldValue.serverTimestamp(),
                  'isAnonymous': false,
                  'lastUpdated': FieldValue.serverTimestamp(),
                });
                print(
                    'Otomatik doğrulama: Yeni kullanıcı dökümanı oluşturuldu');
              } else {
                // Döküman varsa güncelle
                await userDocRef.update({
                  'phoneNumber': phoneNumber,
                  'lastUpdated': FieldValue.serverTimestamp(),
                  'isAnonymous': false,
                });
                print(
                    'Otomatik doğrulama: Mevcut kullanıcı dökümanı güncellendi');
              }

              // Doğrulama için okuyalım
              final updatedDoc = await userDocRef.get();
              final savedPhoneNumber =
                  updatedDoc.data()?['phoneNumber'] as String?;
              print(
                  'Otomatik doğrulama: Firestore\'a kaydedilen telefon numarası: $savedPhoneNumber');
            }

            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => const NicknameScreen(),
                ),
              );
            }
          } catch (e) {
            print('Otomatik doğrulama hatası: $e');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${AppLocalizations.of(context)!.genericError}: ${e.toString()}',
                  ),
                ),
              );
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          print('Doğrulama başarısız: ${e.code} - ${e.message}');
          setState(() {
            _isLoading = false;
          });

          String errorMessage = AppLocalizations.of(context)!.loginFailedError;
          switch (e.code) {
            case 'invalid-phone-number':
              errorMessage = 'Geçersiz telefon numarası formatı';
              break;
            case 'too-many-requests':
              errorMessage =
                  'Çok fazla giriş denemesi yapıldı, lütfen daha sonra tekrar deneyin';
              break;
            case 'app-not-authorized':
              errorMessage =
                  'Uygulama telefon doğrulama için yetkilendirilmemiş';
              break;
            default:
              errorMessage =
                  e.message ?? AppLocalizations.of(context)!.loginFailedError;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage)),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          print('SMS kodu gönderildi. VerificationId: $verificationId');
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _isLoading = false;
          });

          // SMS dialogunu göster
          _showSMSDialog();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          print('Otomatik kod alımı zaman aşımına uğradı');
          setState(() {
            _verificationId = verificationId;
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      print('Phone Auth genel hata: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppLocalizations.of(context)!.genericError}: ${e.toString()}',
          ),
        ),
      );
    }
  }

  Future<void> _verifySMSCode(String smsCode) async {
    if (_verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.verificationIdMissingError),
        ),
      );
      return;
    }

    if (smsCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.smsEmptyError)),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print(
          'SMS kodu doğrulanıyor: $smsCode için verificationId: $_verificationId');

      // Aktif oturum kontrolü
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        print(
            'SMS doğrulama: Aktif oturum bulundu, çıkış yapılıyor: ${currentUser.uid}');
        await FirebaseAuth.instance.signOut();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      print('Kullanıcı başarıyla giriş yaptı: ${userCredential.user?.uid}');
      print('Kullanıcı telefon numarası: ${userCredential.user?.phoneNumber}');

      // Telefon numarasını Users koleksiyonuna kaydet
      if (userCredential.user != null) {
        String phoneNumber = _phoneController.text.trim();

        // Telefon numarasını normalize et
        if (!phoneNumber.startsWith('+')) {
          if (phoneNumber.startsWith('0')) {
            phoneNumber = phoneNumber.substring(1);
          }
          phoneNumber = '+90$phoneNumber';
        }

        // Eğer kontrolcüden alınan numara boşsa Firebase Auth'dan alalım
        if (phoneNumber.isEmpty && userCredential.user?.phoneNumber != null) {
          phoneNumber = userCredential.user!.phoneNumber!;
        }

        print(
            'Kullanıcının phoneNumber alanı FirebaseAuth\'dan: ${userCredential.user?.phoneNumber}');
        print('Kullanıcının phoneNumber alanı girilen numaradan: $phoneNumber');

        // Users koleksiyonunu kontrol et ve gerekirse oluştur
        final userDocRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid);
        final userDoc = await userDocRef.get();

        if (!userDoc.exists) {
          // Döküman yoksa oluştur
          await userDocRef.set({
            'userId': userCredential.user!.uid,
            'phoneNumber': phoneNumber,
            'createdAt': FieldValue.serverTimestamp(),
            'isAnonymous': false,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
          print('Yeni kullanıcı dökümanı oluşturuldu');
        } else {
          // Döküman varsa güncelle
          await userDocRef.update({
            'phoneNumber': phoneNumber,
            'lastUpdated': FieldValue.serverTimestamp(),
            'isAnonymous': false,
          });
          print('Mevcut kullanıcı dökümanı güncellendi');
        }

        // Doğrulama için kullanıcı belgesini oku
        final updatedDoc = await userDocRef.get();
        final savedPhoneNumber = updatedDoc.data()?['phoneNumber'] as String?;
        print(
            'Firestore\'dan kontrol: Kaydedilen telefon numarası: $savedPhoneNumber');
      }

      if (mounted) {
        // Kullanıcı adı ekranına yönlendir
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const NicknameScreen(),
          ),
        );
      }
    } catch (e) {
      print('SMS doğrulama hatası: $e');
      String errorMessage = AppLocalizations.of(context)!.loginFailedError;

      if (e is FirebaseAuthException) {
        print('FirebaseAuthException kodu: ${e.code}');
        switch (e.code) {
          case 'invalid-verification-code':
            errorMessage = AppLocalizations.of(context)!.invalidSmsCodeError;
            break;
          case 'invalid-verification-id':
            errorMessage =
                AppLocalizations.of(context)!.invalidVerificationIdError;
            break;
          case 'session-expired':
            errorMessage = 'Doğrulama süresi doldu, lütfen tekrar deneyin';
            break;
          case 'user-disabled':
            errorMessage = 'Bu kullanıcı hesabı devre dışı bırakılmış';
            break;
          default:
            errorMessage =
                e.message ?? AppLocalizations.of(context)!.loginFailedError;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
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

  Future<void> _signInAnonymously() async {
    // Klavyeyi kapat
    FocusScope.of(context).unfocus();

    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Firebase Auth durumunu temizle
      await FirebaseAuth.instance.signOut();

      // Kısa bekletme - Auth durumunun temizlenmesi için
      await Future.delayed(const Duration(milliseconds: 500));

      // Şimdi anonim giriş yap
      await FirebaseAuth.instance.signInAnonymously();

      if (!mounted) return;

      // Kullanıcı adı ekranına yönlendir
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const NicknameScreen(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String errorMessage;
      switch (e.code) {
        case 'network-request-failed':
          errorMessage = AppLocalizations.of(context)!.networkError;
          break;
        case 'operation-not-allowed':
          errorMessage =
              AppLocalizations.of(context)!.anonymousLoginDisabledError;
          break;
        default:
          errorMessage =
              e.message ?? AppLocalizations.of(context)!.loginFailedError;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppLocalizations.of(context)!.genericError}: ${e.toString()}',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSMSDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).dialogTheme.backgroundColor,
        title: Text(AppLocalizations.of(context)!.smsDialogTitle),
        content: TextField(
          controller: _smsController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.smsCodeLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _smsController.clear();
            },
            child: Text(AppLocalizations.of(context)!.cancelButton),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _verifySMSCode(_smsController.text.trim());
              _smsController.clear();
            },
            child: Text(AppLocalizations.of(context)!.verifyButton),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.appTitle),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      // SingleChildScrollView ile içeriği kaydırılabilir yap
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ekran yüksekliği için biraz boşluk ekle
              const SizedBox(height: 40),
              // Telefon numarası girişi
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        localizations.phoneLoginTitle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _phoneController,
                        decoration: InputDecoration(
                          labelText: localizations.phoneNumberLabel,
                          border: const OutlineInputBorder(),
                          helperText: localizations.phoneNumberHelper,
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _verifyPhone,
                          child: Text(localizations.phoneLoginButton),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // VEYA ayracı
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 24, bottom: 24),
                  child: CircularProgressIndicator(),
                ),
              // Ekranın en altında boşluk bırak (klavye açıldığında içerik görünür kalsın)
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _smsController.dispose();
    super.dispose();
  }
}

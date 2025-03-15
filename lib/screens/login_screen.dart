import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
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
        const SnackBar(content: Text('Lütfen telefon numaranızı girin')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Telefon numarasını E.164 formatına dönüştür
    String phoneNumber = _phoneController.text.trim();

    // Eğer numara + ile başlamıyorsa ve Türkiye numarası ise
    if (!phoneNumber.startsWith('+')) {
      // Numara 0 ile başlıyorsa 0'ı kaldır
      if (phoneNumber.startsWith('0')) {
        phoneNumber = phoneNumber.substring(1);
      }
      // Türkiye ülke kodunu ekle
      phoneNumber = '+90$phoneNumber';
    }

    print('Doğrulama için kullanılacak telefon numarası: $phoneNumber');

    try {
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
            await FirebaseAuth.instance.signInWithCredential(credential);
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
                SnackBar(content: Text('Giriş yaparken hata oluştu: $e')),
              );
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          print('Doğrulama başarısız: ${e.message}');
          setState(() {
            _isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Doğrulama başarısız')),
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
        SnackBar(content: Text('Bir hata oluştu: $e')),
      );
    }
  }

  Future<void> _verifySMSCode(String smsCode) async {
    if (_verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Doğrulama kimliği eksik. Lütfen tekrar deneyin.')),
      );
      return;
    }

    if (smsCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen SMS kodunu girin')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print(
          'SMS kodu doğrulanıyor: $smsCode için verificationId: $_verificationId');

      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      print('Kullanıcı başarıyla giriş yaptı: ${userCredential.user?.uid}');

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
      String errorMessage = 'SMS kodu doğrulanamadı';

      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'invalid-verification-code':
            errorMessage = 'Geçersiz SMS kodu. Lütfen tekrar deneyin.';
            break;
          case 'invalid-verification-id':
            errorMessage =
                'Geçersiz doğrulama kimliği. Lütfen tekrar telefon numaranızı girin.';
            break;
          default:
            errorMessage = e.message ?? 'SMS kodu doğrulanamadı';
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
          errorMessage = 'İnternet bağlantınızı kontrol edin';
          break;
        case 'operation-not-allowed':
          errorMessage = 'Anonim giriş şu anda devre dışı';
          break;
        default:
          errorMessage = e.message ?? 'Giriş başarısız';
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
          content: Text('Beklenmeyen bir hata oluştu: $e'),
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
        title: const Text('SMS Kodunu Girin'),
        content: TextField(
          controller: _smsController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'SMS Kodu',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _smsController.clear();
            },
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _verifySMSCode(_smsController.text.trim());
              _smsController.clear();
            },
            child: const Text('Doğrula'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhySup'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Telefon Numarası ile Giriş',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Telefon Numarası',
                          hintText: '5XX XXX XX XX',
                          prefixText: '+90 ',
                          border: OutlineInputBorder(),
                          helperText:
                              'Örnek: 5XX XXX XX XX (başında 0 olmadan)',
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _verifyPhone,
                          child: const Text('Telefon ile Giriş Yap'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // VEYA ayracı
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('VEYA'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
              // Anonim giriş
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Anonim Giriş',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Telefon numarası vermeden anonim olarak giriş yapabilirsiniz.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signInAnonymously,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                          ),
                          child: const Text(
                            'Anonim Olarak Giriş Yap',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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

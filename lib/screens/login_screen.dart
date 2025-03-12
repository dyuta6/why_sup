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
    if (_phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen telefon numaranızı girin')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: '+11234567890', // Test numarası
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            _isLoading = false;
          });
          print('Verification Failed: ${e.message}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Doğrulama başarısız')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _isLoading = false;
          });
          // Test için otomatik kod gösterimi
          _showSMSDialog();
          _smsController.text = '123456'; // Test kodu
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          setState(() {
            _verificationId = verificationId;
            _isLoading = false;
          });
        },
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bir hata oluştu: $e')),
      );
    }
  }

  Future<void> _verifySMSCode(String smsCode) async {
    if (_verificationId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);

      if (mounted) {
        // Kullanıcı adı ekranına yönlendir
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const NicknameScreen(),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'SMS kodu doğrulanamadı')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInAnonymously() async {
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
                          prefixText: '+90 ',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _verifyPhone,
                        child: const Text('Telefon ile Giriş Yap'),
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
                      ElevatedButton(
                        onPressed: _isLoading ? null : _signInAnonymously,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                        ),
                        child: const Text(
                          'Anonim Olarak Giriş Yap',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: CircularProgressIndicator(),
                ),
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

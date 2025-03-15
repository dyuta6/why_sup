import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'dart:convert';
import 'dart:io';
import 'user_activity_screen.dart';

class ProfileImageScreen extends StatefulWidget {
  const ProfileImageScreen({super.key});

  @override
  State<ProfileImageScreen> createState() => _ProfileImageScreenState();
}

class _ProfileImageScreenState extends State<ProfileImageScreen> {
  File? _imageFile;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${AppLocalizations.of(context)!.imagePickError}: $e')),
        );
      }
    }
  }

  Future<void> _saveProfileImage() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context)!.profileImageEmptyError)),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final bytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(bytes);

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'profileImage': base64Image});

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const UserActivityScreen(),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.profileImageSaveError),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.appTitle),
        centerTitle: true,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                localizations.profileImageTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 80,
                backgroundColor: Colors.grey[300],
                backgroundImage:
                    _imageFile != null ? FileImage(_imageFile!) : null,
                child: _imageFile == null
                    ? const Icon(Icons.person, size: 80, color: Colors.grey)
                    : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickImage,
                icon: const Icon(Icons.photo_library),
                label: Text(localizations.selectFromGallery),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveProfileImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(localizations.continueButton),
              ),
              if (_imageFile == null) ...[
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => const UserActivityScreen(),
                      ),
                    );
                  },
                  child: Text(localizations.skipForNow),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'dart:convert';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String username;
  final bool isFollowing;
  final Function(String, String) onToggleFollow;

  const UserProfileScreen({
    Key? key,
    required this.userId,
    required this.username,
    required this.isFollowing,
    required this.onToggleFollow,
  }) : super(key: key);

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Stream<QuerySnapshot>? _activitiesStream;
  String? _profileImage;
  bool _isLoading = true;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _isFollowing = widget.isFollowing;
    _loadUserData();
    _initActivitiesStream();
  }

  Future<void> _loadUserData() async {
    try {
      final userDoc =
          await _firestore.collection('users').doc(widget.userId).get();

      if (userDoc.exists && mounted) {
        setState(() {
          _profileImage = userDoc.data()?['profileImage'] as String?;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Kullanıcı bilgileri yüklenirken hata: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _initActivitiesStream() {
    _activitiesStream = _firestore
        .collection('user_activities')
        .where('userId', isEqualTo: widget.userId)
        .orderBy('startTime', descending: true)
        .snapshots();
  }

  void _handleToggleFollow() {
    widget.onToggleFollow(widget.userId, widget.username);
    setState(() {
      _isFollowing = !_isFollowing;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.username),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Profil bilgileri
          Container(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundImage: _profileImage != null
                      ? MemoryImage(base64Decode(_profileImage!))
                      : null,
                  child: _profileImage == null
                      ? const Icon(Icons.person, size: 40)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.username,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Tüm Aktiviteler',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.userId != FirebaseAuth.instance.currentUser?.uid)
                  IconButton(
                    icon: Icon(
                      _isFollowing ? Icons.person_remove : Icons.person_add,
                      color: _isFollowing ? Colors.red : Colors.green,
                      size: 30,
                    ),
                    onPressed: _handleToggleFollow,
                  ),
              ],
            ),
          ),
          const Divider(),
          // Aktiviteler listesi
          Expanded(
            child: _buildActivitiesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitiesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _activitiesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Bir hata oluştu: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Kendi uygulamamızın paket adı - bu gözükmeyecek
        const String ourAppPackage = "com.example.why_sup";

        final List<Map<String, dynamic>> filteredActivities = [];

        for (var doc in snapshot.data!.docs) {
          final activityData = doc.data() as Map<String, dynamic>;
          final packageName = activityData['packageName'] as String? ?? '';

          // Kendi uygulamamızı filtreleme
          if (packageName == ourAppPackage) {
            continue; // Bu aktiviteyi atla
          }

          filteredActivities.add(activityData);
        }

        if (filteredActivities.isEmpty) {
          return const Center(child: Text('Henüz hiç aktivite paylaşılmamış'));
        }

        return ListView.builder(
          itemCount: filteredActivities.length,
          itemBuilder: (context, index) {
            final activityData = filteredActivities[index];
            final appName =
                activityData['appName'] as String? ?? 'Bilinmeyen Uygulama';
            final packageName = activityData['packageName'] as String? ?? '';
            final timestamp = activityData['startTime'] as Timestamp?;
            final startTime = timestamp?.toDate() ?? DateTime.now();

            return ActivityItem(
              appName: appName,
              packageName: packageName,
              startTime: startTime,
              profileImage: _profileImage,
              username: widget.username,
            );
          },
        );
      },
    );
  }
}

class ActivityItem extends StatefulWidget {
  final String appName;
  final String packageName;
  final DateTime startTime;
  final String? profileImage;
  final String username;

  const ActivityItem({
    Key? key,
    required this.appName,
    required this.packageName,
    required this.startTime,
    this.profileImage,
    required this.username,
  }) : super(key: key);

  @override
  State<ActivityItem> createState() => _ActivityItemState();
}

class _ActivityItemState extends State<ActivityItem> {
  AppInfo? _appInfo;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAppIcon();
  }

  Future<void> _loadAppIcon() async {
    try {
      // Cihazdaki uygulamaları kontrol et
      final isInstalled =
          await InstalledApps.isAppInstalled(widget.packageName) ?? false;
      if (isInstalled) {
        final appInfo = await InstalledApps.getAppInfo(widget.packageName);
        if (mounted) {
          setState(() {
            _appInfo = appInfo;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      }
    } catch (e) {
      print('App icon loading error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget appIconWidget;
    if (_loading) {
      appIconWidget = const CircleAvatar(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_appInfo != null && _appInfo!.icon != null) {
      appIconWidget = CircleAvatar(
        backgroundColor: Colors.transparent,
        backgroundImage: MemoryImage(_appInfo!.icon!),
      );
    } else {
      appIconWidget = CircleAvatar(
        backgroundColor: Colors.grey.shade200,
        child: Icon(Icons.android, color: Colors.grey.shade700),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: appIconWidget,
        title: Text(widget.appName),
        subtitle: Text(_getFormattedDate(widget.startTime)),
        trailing: Text(
          '${_getTimeAgo(widget.startTime)} önce',
          style: const TextStyle(color: Colors.grey),
        ),
      ),
    );
  }

  String _getFormattedDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getTimeAgo(DateTime startTime) {
    final difference = DateTime.now().difference(startTime);
    if (difference.inMinutes < 1) {
      return 'şimdi';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} dakika';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} saat';
    } else {
      return '${difference.inDays} gün';
    }
  }
}

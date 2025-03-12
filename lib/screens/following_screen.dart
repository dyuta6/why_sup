import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_profile_screen.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'dart:convert';

class FollowingScreen extends StatelessWidget {
  final Stream<QuerySnapshot>? activitiesStream;
  final Set<String> followingUsers;
  final Function(String, String) onToggleFollow;

  const FollowingScreen({
    super.key,
    required this.activitiesStream,
    required this.followingUsers,
    required this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    if (followingUsers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'Hiç kimseyi takip etmiyorsunuz',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Diğer kullanıcıları takip etmek için "Herkes" sekmesine göz atın',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: activitiesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Bir hata oluştu: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Kendi uygulamamızın paket adı - bu gözükmeyecek
        const String ourAppPackage = "com.example.why_sup";

        // Her kullanıcının son aktivitesini tut
        final Map<String, ActivityItem> latestActivitiesByUser = {};

        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final userId = data['userId'] as String;
          final timestamp = data['startTime'] as Timestamp?;
          final packageName = data['packageName'] as String? ?? '';

          // Kendi uygulamamızı filtreleme
          if (packageName == ourAppPackage) {
            continue; // Bu aktiviteyi atla
          }

          // Eğer bu kullanıcının aktivitesi daha önce eklenmemişse veya
          // bu aktivite daha yeniyse, map'i güncelle
          if (!latestActivitiesByUser.containsKey(userId) ||
              (timestamp != null &&
                  timestamp
                      .toDate()
                      .isAfter(latestActivitiesByUser[userId]!.startTime))) {
            latestActivitiesByUser[userId] = ActivityItem(
              username: data['username'] ?? 'Anonim',
              appName: data['appName'] ?? 'Bilinmeyen Uygulama',
              packageName: packageName,
              startTime: timestamp?.toDate() ?? DateTime.now(),
              userId: userId,
            );
          }
        }

        // Map'teki değerleri listeye çevir ve zamanına göre sırala
        final activities = latestActivitiesByUser.values.toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));

        if (activities.isEmpty) {
          return const Center(
            child: Text('Henüz hiç aktivite paylaşılmamış'),
          );
        }

        return ListView.builder(
          itemCount: activities.length,
          itemBuilder: (context, index) {
            final activity = activities[index];
            final isFollowing = followingUsers.contains(activity.userId);

            return ActivityCard(
              activity: activity,
              isFollowing: isFollowing,
              onToggleFollow: onToggleFollow,
            );
          },
        );
      },
    );
  }
}

class ActivityCard extends StatefulWidget {
  final ActivityItem activity;
  final bool isFollowing;
  final Function(String, String) onToggleFollow;

  const ActivityCard({
    super.key,
    required this.activity,
    required this.isFollowing,
    required this.onToggleFollow,
  });

  @override
  _ActivityCardState createState() => _ActivityCardState();
}

class _ActivityCardState extends State<ActivityCard> {
  AppInfo? _appInfo;
  bool _loading = true;
  String? _profileImage;

  @override
  void initState() {
    super.initState();
    _loadAppIcon();
    _loadUserProfileImage();
  }

  Future<void> _loadAppIcon() async {
    try {
      // Cihazdaki uygulamaları kontrol et
      final isInstalled =
          await InstalledApps.isAppInstalled(widget.activity.packageName) ??
              false;
      if (isInstalled) {
        final appInfo =
            await InstalledApps.getAppInfo(widget.activity.packageName);
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

  Future<void> _loadUserProfileImage() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.activity.userId)
          .get();

      if (userDoc.exists && mounted) {
        setState(() {
          _profileImage = userDoc.data()?['profileImage'] as String?;
        });
      }
    } catch (e) {
      print('Profil resmi yüklenirken hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // Profil resmi widget'ı
    Widget profileImageWidget = CircleAvatar(
      radius: 25,
      backgroundImage: _profileImage != null
          ? MemoryImage(base64Decode(_profileImage!))
          : null,
      child: _profileImage == null ? const Icon(Icons.person, size: 25) : null,
    );

    // Uygulama simgesi widget'ı
    Widget appIconWidget;
    if (_loading) {
      appIconWidget = const SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_appInfo != null && _appInfo!.icon != null) {
      appIconWidget = SizedBox(
        width: 36,
        height: 36,
        child: Image.memory(_appInfo!.icon!),
      );
    } else {
      appIconWidget =
          Icon(Icons.android, color: Colors.grey.shade700, size: 36);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UserProfileScreen(
                userId: widget.activity.userId,
                username: widget.activity.username,
                isFollowing: widget.isFollowing,
                onToggleFollow: widget.onToggleFollow,
              ),
            ),
          );
        },
        child: ListTile(
          leading: profileImageWidget,
          title: Row(
            children: [
              Expanded(
                child: Text(widget.activity.username),
              ),
              const SizedBox(width: 8),
              appIconWidget,
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kullanılan uygulama: ${widget.activity.appName}'),
              Text(
                '${_getTimeAgo(widget.activity.startTime)} önce',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime startTime) {
    final difference = DateTime.now().difference(startTime);
    if (difference.inMinutes < 1) {
      return 'şimdi';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} dakika';
    } else {
      return '${difference.inHours} saat';
    }
  }
}

class ActivityItem {
  final String username;
  final String appName;
  final String packageName;
  final DateTime startTime;
  final String userId;

  ActivityItem({
    required this.username,
    required this.appName,
    required this.packageName,
    required this.startTime,
    required this.userId,
  });
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_profile_screen.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'dart:convert';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

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
    final localizations = AppLocalizations.of(context)!;

    if (followingUsers.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.person_outline,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                localizations.noFollowing,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                localizations.checkAllTab,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _importContactsAndFollow(context),
          child: const Icon(Icons.contacts),
          tooltip: 'Rehberden takip et',
        ),
      );
    }

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: activitiesStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child:
                    Text('${localizations.genericError}: ${snapshot.error}'));
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
                username: data['username'] ?? localizations.anonymousUser,
                appName: data['appName'] ?? localizations.unknownApp,
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
            return Center(
              child: Text(localizations.noActivities),
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
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _importContactsAndFollow(context),
        child: const Icon(Icons.contacts),
        tooltip: 'Rehberden takip et',
      ),
    );
  }

  // Telefon rehberindeki kişileri içe aktar ve eşleşen kullanıcıları takip et
  Future<void> _importContactsAndFollow(BuildContext context) async {
    final localizations = AppLocalizations.of(context)!;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      // Önce izin durumunu kontrol et
      final status = await Permission.contacts.status;

      // İzin daha önce reddedildiyse veya henüz istenmemişse
      if (status.isDenied || status.isRestricted) {
        // Açıklayıcı bir dialog göster
        final shouldRequest = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Rehber Erişimi'),
                content: const Text(
                    'WhySup, rehberinizden kişileri bulup otomatik olarak takip etmek için '
                    'rehberinize erişmek istiyor. Bu sayede tanıdığınız kişileri kolayca '
                    'bulabilir ve takip edebilirsiniz.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('İptal'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('İzin Ver'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).primaryColor,
                    ),
                  ),
                ],
              ),
            ) ??
            false;

        if (!shouldRequest) {
          return; // Kullanıcı iptal ettiyse işlemi sonlandır
        }

        // Kullanıcı dialog'dan izin vermek istediğini belirttiyse izni iste
        final permissionResult = await Permission.contacts.request();

        if (permissionResult.isDenied || permissionResult.isPermanentlyDenied) {
          if (permissionResult.isPermanentlyDenied) {
            // Kullanıcı izni kalıcı olarak reddettiyse, ayarlara yönlendir
            final openSettings = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('İzin Gerekli'),
                    content: const Text(
                        'Rehber erişimi için izin vermeniz gerekiyor. İzin vermek için '
                        'uygulama ayarlarını açmak ister misiniz?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Hayır'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Ayarları Aç'),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ) ??
                false;

            if (openSettings) {
              await openAppSettings();
            }
          }
          scaffoldMessenger.showSnackBar(
            const SnackBar(
                content:
                    Text('Rehbere erişim izni olmadan kişileriniz bulunamaz')),
          );
          return;
        }
      }
      // İzin zaten verilmiş veya yeni verilmişse
      else if (!status.isGranted) {
        // Son bir kez daha izni kontrol et
        final permissionResult = await Permission.contacts.request();
        if (!permissionResult.isGranted) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
                content:
                    Text('Rehbere erişim izni olmadan kişileriniz bulunamaz')),
          );
          return;
        }
      }

      // İzin alındıysa, devam et
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Rehberdeki kişiler alınıyor...')),
      );

      // Mevcut kullanıcı kontrolü
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
              content: Text('Giriş yapılmış bir kullanıcı bulunamadı')),
        );
        return;
      }

      try {
        // Rehberdeki kişileri al (telefonları ile birlikte)
        final contacts = await FlutterContacts.getContacts(
          withProperties: true,
          withPhoto: false,
        );

        if (contacts.isEmpty) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('Rehberde kayıtlı kişi bulunamadı')),
          );
          return;
        }

        // Rehberdeki telefon numaralarını topla
        final Set<String> contactPhoneNumbers = {};

        for (var contact in contacts) {
          for (var phone in contact.phones) {
            if (phone.number.isNotEmpty) {
              // Telefon numarasını normalize et
              final normalizedNumber = _normalizePhoneNumber(phone.number);
              if (normalizedNumber.isNotEmpty) {
                contactPhoneNumbers.add(normalizedNumber);
              }
            }
          }
        }

        if (contactPhoneNumbers.isEmpty) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
                content: Text('Rehberde telefon numarası bulunamadı')),
          );
          return;
        }

        scaffoldMessenger.showSnackBar(
          SnackBar(
              content: Text(
                  '${contactPhoneNumbers.length} telefon numarası bulundu. Eşleştiriliyor...')),
        );

        // Firebase'den kullanıcıları telefon numaralarına göre sorgula
        final usersRef = FirebaseFirestore.instance.collection('users');
        final followingRef = FirebaseFirestore.instance
            .collection('following')
            .doc(currentUserId);

        // Batch işlemler için sayaç
        int followedCount = 0;
        final List<String> userIdsToFollow = [];

        // Her numarayı sorgula ve eşleşen kullanıcıları bul
        for (final phoneNumber in contactPhoneNumbers) {
          try {
            final querySnapshot = await usersRef
                .where('phoneNumber', isEqualTo: phoneNumber)
                .limit(1)
                .get();

            if (querySnapshot.docs.isNotEmpty) {
              final userId = querySnapshot.docs.first.id;

              // Kendimizi takip etmiyoruz ve zaten takip edilenleri atlıyoruz
              if (userId != currentUserId && !followingUsers.contains(userId)) {
                userIdsToFollow.add(userId);
              }
            }
          } catch (e) {
            print('Telefon numarası sorgulama hatası: $e');
          }
        }

        // Eşleşen kullanıcıları takip et
        if (userIdsToFollow.isNotEmpty) {
          await followingRef.set(
              {'following': FieldValue.arrayUnion(userIdsToFollow)},
              SetOptions(merge: true));

          followedCount = userIdsToFollow.length;

          // Eşleşen kişi varsa sonucu göster
          scaffoldMessenger.showSnackBar(
            SnackBar(
                content: Text(
                    '$followedCount kişi rehberden takip listesine eklendi')),
          );
        } else {
          // Eşleşen kişi yoksa özel mesaj göster
          scaffoldMessenger.showSnackBar(
            const SnackBar(
                content: Text('Rehberinizdeki hiç kimse WhySup kullanmıyor')),
          );
        }
      } catch (e) {
        print('Rehber okuma hatası: $e');
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Rehber okuma sırasında hata: $e')),
        );
      }
    } catch (e) {
      print('Rehber işlemi hatası: $e');
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Rehber işlemi sırasında hata: $e')),
      );
    }
  }

  // Telefon numarasını normalize etme (sadece rakamları al)
  String _normalizePhoneNumber(String phoneNumber) {
    // Tüm boşlukları, parantezleri, tire ve artıları kaldır
    final digitsOnly = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');

    // Eğer Türkiye numarası ise başındaki "0" silip "+90" ekleyebilirsin
    if (digitsOnly.startsWith('0') && digitsOnly.length == 11) {
      return "+90${digitsOnly.substring(1)}";
    }
    // Başında ülke kodu yoksa ve 10 haneliyse Türkiye numarası olarak kabul et
    else if (digitsOnly.length == 10 && !digitsOnly.startsWith('+')) {
      return "+90$digitsOnly";
    }
    // Başında "+" yoksa ekle
    else if (!digitsOnly.startsWith('+')) {
      return "+$digitsOnly";
    }

    return digitsOnly;
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
    final localizations = AppLocalizations.of(context)!;

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
              Text('${localizations.startedUsing}: ${widget.activity.appName}'),
              Text(
                _getTimeAgo(widget.activity.startTime),
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime startTime) {
    final localizations = AppLocalizations.of(context)!;
    final difference = DateTime.now().difference(startTime);

    if (difference.inMinutes < 1) {
      return localizations.justNow;
    } else if (difference.inMinutes < 60) {
      return localizations.minutesAgo(difference.inMinutes);
    } else {
      return localizations.hoursAgo(difference.inHours);
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

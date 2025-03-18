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
import 'package:vibration/vibration.dart';

class FollowingScreen extends StatefulWidget {
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
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  late Future<void> _refreshFuture;
  late Set<String> _currentFollowingUsers;
  bool _needsRefresh = false;

  @override
  void initState() {
    super.initState();
    _currentFollowingUsers = Set<String>.from(widget.followingUsers);
    _refreshFuture = _refreshData();
  }

  @override
  void didUpdateWidget(FollowingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Widget'in followingUsers değeri değiştiyse, _currentFollowingUsers'ı güncelle
    if (oldWidget.followingUsers != widget.followingUsers) {
      setState(() {
        _currentFollowingUsers = Set<String>.from(widget.followingUsers);
        _needsRefresh = false;
      });
    }
  }

  // Listeyi yenile - bu metot her çağrıldığında ekranı yeniler
  Future<void> _refreshData() async {
    if (!mounted) return;

    print("Takip listesi yenileniyor...");

    // Mevcut kullanıcının takip listesini Firestore'dan al
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final followingDoc = await FirebaseFirestore.instance
            .collection('following')
            .doc(user.uid)
            .get();

        if (followingDoc.exists) {
          final followingData = followingDoc.data();
          if (followingData != null && followingData.containsKey('following')) {
            final followingList =
                List<String>.from(followingData['following'] ?? []);

            print("Firestore'dan alınan takip listesi: $followingList");

            if (mounted) {
              setState(() {
                _currentFollowingUsers = Set<String>.from(followingList);
                _needsRefresh = false;
              });
            }
          }
        }
      } catch (e) {
        print('Takip listesi alınırken hata: $e');
      }
    }
  }

  // Yerel takip işlevi - onToggleFollow fonksiyonu çağrılmadan önce yerel durumu günceller
  void _handleToggleFollow(String userId, String username) {
    // Ana widget'taki onToggleFollow fonksiyonunu çağır
    widget.onToggleFollow(userId, username);

    // Aynı zamanda yerel durumu da güncelle
    setState(() {
      if (_currentFollowingUsers.contains(userId)) {
        _currentFollowingUsers.remove(userId);
      } else {
        _currentFollowingUsers.add(userId);
      }

      // Firestore'dan veriyi almak için bir sonraki build'de _refreshData'yı çağır
      _needsRefresh = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    // Eğer yenileme gerekiyorsa, veriyi çek
    if (_needsRefresh) {
      _refreshFuture = _refreshData();
      _needsRefresh = false;
    }

    return FutureBuilder<void>(
      future: _refreshFuture,
      builder: (context, snapshot) {
        // Takip edilen kullanıcı yoksa
        if (_currentFollowingUsers.isEmpty) {
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
              onPressed: () async {
                // Rehber işlemini başlat
                await _importContactsAndFollow(context);

                // İşlem tamamlandığında setState ile yenileme işaretini koy
                if (mounted) {
                  setState(() {
                    _needsRefresh = true;
                  });
                }
              },
              child: const Icon(Icons.contacts),
              tooltip: localizations.contactsTooltip,
            ),
          );
        }

        return Scaffold(
          body: StreamBuilder<QuerySnapshot>(
            stream: widget.activitiesStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: Text(
                        '${localizations.genericError}: ${snapshot.error}'));
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
                        timestamp.toDate().isAfter(
                            latestActivitiesByUser[userId]!.startTime))) {
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

              return RefreshIndicator(
                onRefresh: () {
                  // Kullanıcı aşağı çektiğinde verileri yenile
                  setState(() {
                    _refreshFuture = _refreshData();
                  });
                  return _refreshFuture;
                },
                child: ListView.builder(
                  itemCount: activities.length,
                  itemBuilder: (context, index) {
                    final activity = activities[index];
                    final isFollowing =
                        _currentFollowingUsers.contains(activity.userId);

                    return ActivityCard(
                      activity: activity,
                      isFollowing: isFollowing,
                      onToggleFollow: _handleToggleFollow,
                    );
                  },
                ),
              );
            },
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              // Rehber işlemini başlat
              await _importContactsAndFollow(context);

              // İşlem tamamlandığında setState ile yenileme işaretini koy
              if (mounted) {
                setState(() {
                  _needsRefresh = true;
                });
              }
            },
            child: const Icon(Icons.contacts),
            tooltip: localizations.contactsTooltip,
          ),
        );
      },
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
                title: Text(localizations.contactsAccessTitle),
                content: Text(localizations.contactsAccessDescription),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(localizations.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(localizations.allowAccess),
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
                    title: Text(localizations.accessRequired),
                    content:
                        Text(localizations.contactsAccessSettingsDescription),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(localizations.no),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(localizations.openSettings),
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
            SnackBar(content: Text(localizations.contactsAccessDenied)),
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
            SnackBar(content: Text(localizations.contactsAccessDenied)),
          );
          return;
        }
      }

      // İzin alındıysa, devam et
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(localizations.contactsLoading)),
      );

      // Mevcut kullanıcı kontrolü
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(localizations.userNotFound)),
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
            SnackBar(content: Text(localizations.noContactsFound)),
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
            SnackBar(content: Text(localizations.noPhoneNumbersFound)),
          );
          return;
        }

        // Rehberden çekilen tüm numaraları konsola yazdır
        print('Rehberden çekilen tüm numaralar:');
        print(contactPhoneNumbers.toList().join(', '));

        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              localizations.contactsFoundProcessing(contactPhoneNumbers.length),
            ),
          ),
        );

        // Firebase'den kullanıcıları telefon numaralarına göre sorgula
        final usersRef = FirebaseFirestore.instance.collection('users');
        final followingRef = FirebaseFirestore.instance
            .collection('following')
            .doc(currentUserId);

        // Batch işlemler için sayaç
        int followedCount = 0;
        final List<String> userIdsToFollow = [];

        try {
          // Tüm kullanıcıları çekelim
          final allUsersSnapshot = await usersRef.get();

          // Eşleşen telefon numaralarını konsola yazdıralım
          print(
              '\n=== FIREBASE\'DEN ÇEKİLEN KULLANICILAR VE TELEFON NUMARALARI ===');
          print('Toplam kullanıcı sayısı: ${allUsersSnapshot.docs.length}');

          // Tüm kullanıcıların telefon numaralarını bir map'e koyalım
          Map<String, String> userIdsByPhoneNumber = {};
          Map<String, Map<String, dynamic>> userDataByUserId = {};

          for (var doc in allUsersSnapshot.docs) {
            final userData = doc.data();
            final userId = doc.id;
            final userPhoneNumber = userData['phoneNumber'] as String?;

            if (userPhoneNumber != null && userPhoneNumber.isNotEmpty) {
              print('Kullanıcı ID: $userId');
              print('Telefon: $userPhoneNumber');
              print('Kullanıcı Adı: ${userData['username'] ?? 'İsimsiz'}');
              print('----------------------------------------');
              userIdsByPhoneNumber[userPhoneNumber] = userId;
              userDataByUserId[userId] = userData;
            }
          }

          print('\n=== REHBERDEN ÇEKİLEN NUMARALAR ===');
          print('Toplam numara sayısı: ${contactPhoneNumbers.length}');
          print('Numaralar: ${contactPhoneNumbers.toList().join(', ')}');

          // Rehberdeki numaralar ile Firebase'deki numaraları karşılaştıralım
          print('\n=== EŞLEŞEN NUMARALAR ===');
          for (final phoneNumber in contactPhoneNumbers) {
            if (userIdsByPhoneNumber.containsKey(phoneNumber)) {
              final userId = userIdsByPhoneNumber[phoneNumber]!;
              final userData = userDataByUserId[userId]!;

              // Eşleşen numara ve kullanıcıyı yazdır
              print('Eşleşme bulundu:');
              print('Numara: $phoneNumber');
              print('Kullanıcı ID: $userId');
              print('Kullanıcı Adı: ${userData['username'] ?? 'İsimsiz'}');
              print('----------------------------------------');

              // Kendimizi takip etmiyoruz ve zaten takip edilenleri atlıyoruz
              if (userId != currentUserId &&
                  !_currentFollowingUsers.contains(userId)) {
                userIdsToFollow.add(userId);
              }
            }
          }
        } catch (e) {
          print('Kullanıcı verileri çekilirken hata: $e');
        }

        // Eşleşen kullanıcıları takip et
        if (userIdsToFollow.isNotEmpty) {
          await followingRef.set(
              {'following': FieldValue.arrayUnion(userIdsToFollow)},
              SetOptions(merge: true));

          followedCount = userIdsToFollow.length;

          // Takibe eklenen kullanıcıları konsola yazdır
          print('Takibe eklenen kullanıcılar: $userIdsToFollow');
          print('Toplam eklenen kullanıcı sayısı: $followedCount');

          // Eşleşen kişi varsa sonucu göster
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                localizations.contactsFollowed(followedCount),
              ),
            ),
          );

          // Hafif bir titreşim ekleyelim (isteğe bağlı)
          try {
            if (await Vibration.hasVibrator() ?? false) {
              Vibration.vibrate(duration: 100, amplitude: 128);
            }
          } catch (e) {
            print('Titreşim hatası: $e');
          }

          // Ekranı yenilemek için parent widget'a bildiriyoruz
          if (context.mounted) {
            // _currentFollowingUsers'ı güncelleyelim ki ekran hemen yenilensin
            setState(() {
              // Önce yerel listeyi güncelle
              _currentFollowingUsers.addAll(userIdsToFollow);

              // Firestore verilerimizi yenilemek için işaret koy
              _needsRefresh = true;
            });

            // UserActivityScreen'deki takip listesini de güncelleyelim
            // widget.onToggleFollow metodunu her eklenen kullanıcı için çağıralım
            for (String userId in userIdsToFollow) {
              // Kullanıcı adını bilmediğimiz için boş string gönderiyoruz
              // onToggleFollow metodunda sadece takip etme işlemi için kullanılacak
              widget.onToggleFollow(userId, '');
            }

            // Bilgi amaçlı log
            print('Ana ekrana ${userIdsToFollow.length} kullanıcı eklendi');
          }
        } else {
          // Eşleşen kişi yoksa özel mesaj göster
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text(localizations.noContactsUsingApp)),
          );
        }
      } catch (e) {
        print('Rehber okuma hatası: $e');
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              localizations.contactsReadError(e.toString()),
            ),
          ),
        );
      }
    } catch (e) {
      print('Rehber işlemi hatası: $e');
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            localizations.contactsProcessError(e.toString()),
          ),
        ),
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

  // UserActivityScreen nesnesini bulmak için yardımcı fonksiyon
  dynamic findUserActivityScreen(BuildContext context) {
    // TabBarView içinde olduğumuz için ancestor yerine üst context'i kontrol ediyoruz
    try {
      // DefaultTabController'ı bul
      final tabController = DefaultTabController.of(context);
      if (tabController != null) {
        // Eğer bir TabController bulunduysa, parent widget'ı UserActivityScreen olmalı
        // Ancak doğrudan erişim yapamıyoruz, o yüzden Notification kullanacağız

        // UserActivityScreen'i güncellemek için bir notification gönder
        _RefreshFollowingNotification().dispatch(context);
        return true; // Notification gönderildi
      }
    } catch (e) {
      print('TabController bulunamadı: $e');
    }

    return null; // Bulunamadı
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
                onToggleFollow: (userId, username) {
                  // UserProfileScreen'den gelen onToggleFollow çağrısını yerel durumumuzdaki
                  // handleToggleFollow fonksiyonuna yönlendir
                  if (context.mounted) {
                    final followingScreen = context
                        .findAncestorStateOfType<_FollowingScreenState>();
                    if (followingScreen != null) {
                      followingScreen._handleToggleFollow(userId, username);
                    } else {
                      // Eğer bulamazsak doğrudan widget'a iletelim
                      widget.onToggleFollow(userId, username);
                    }
                  }
                },
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

// Özel notification sınıfı - UserActivityScreen ile iletişim kurmak için
class _RefreshFollowingNotification extends Notification {
  _RefreshFollowingNotification();
}

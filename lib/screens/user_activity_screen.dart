import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'following_screen.dart';
import 'dart:convert';
import 'dart:ui';
import 'login_screen.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'user_profile_screen.dart';

class UserActivityScreen extends StatefulWidget {
  const UserActivityScreen({super.key});

  @override
  State<UserActivityScreen> createState() => _UserActivityScreenState();
}

class _UserActivityScreenState extends State<UserActivityScreen>
    with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Stream<QuerySnapshot>? _allActivitiesStream;
  Stream<QuerySnapshot>? _followingActivitiesStream;
  Set<String> _followingUsers = {};
  Timer? _usageCheckTimer;
  String? _lastTrackedApp;
  String? _userNickname;
  String? _profileImage;
  static const platform = MethodChannel('com.example.why_sup/usage_stats');
  bool _hasShownPermissionDialog = false;
  bool _profileVisibilityEnabled = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchingByPhone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initStreams();
    _loadFollowingUsers();
    _loadUserNickname();
    _loadProfileVisibility();

    // Sayfa yüklendiğinde hemen izin kontrolü yap
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCurrentApp();
    });

    // Her 5 saniyede bir uygulama kullanımını kontrol et
    _usageCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkCurrentApp();
    });
  }

  void _initStreams() {
    // Önce tüm aktiviteleri al ve kullanıcı başına grupla
    _allActivitiesStream = _firestore
        .collection('user_activities')
        .orderBy('startTime', descending: true)
        .snapshots();
  }

  Future<void> _loadFollowingUsers() async {
    if (_auth.currentUser == null) return;

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .get();

      if (userDoc.exists) {
        final following = userDoc.data()?['following'] as List<dynamic>? ?? [];
        setState(() {
          _followingUsers = following.map((e) => e.toString()).toSet();

          // Stream'i güncelle
          _updateFollowingStream();
        });

        print('Takip listesi güncellendi: ${_followingUsers.length} kullanıcı');
      } else {
        // Boş kayıt, boş takip listesi
        setState(() {
          _followingUsers = {};
          _updateFollowingStream();
        });
      }
    } catch (e) {
      print('Takip listesi yüklenirken hata: $e');
    }
  }

  Future<void> _loadUserNickname() async {
    if (_auth.currentUser == null) return;

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .get();

      if (userDoc.exists && mounted) {
        setState(() {
          _userNickname = userDoc.data()?['nickname'] as String?;
          _profileImage = userDoc.data()?['profileImage'] as String?;
        });
      }
    } catch (e) {
      print('Kullanıcı bilgileri yüklenirken hata: $e');
    }
  }

  Future<void> _toggleFollow(String userId, String username) async {
    if (_auth.currentUser == null) return;

    final userDocRef =
        _firestore.collection('users').doc(_auth.currentUser!.uid);

    // Boş username gelirse, kullanıcı ismini Firebase'den almaya çalışalım
    if (username.isEmpty) {
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          username = userDoc.data()?['nickname'] as String? ?? 'Kullanıcı';
        }
      } catch (e) {
        print('Kullanıcı adı alınamadı: $e');
        username = 'Kullanıcı';
      }
    }

    if (_followingUsers.contains(userId)) {
      // Takibi bırak
      await userDocRef.update({
        'following': FieldValue.arrayRemove([userId])
      });
      setState(() {
        _followingUsers.remove(userId);

        // Stream'i güncelle
        _updateFollowingStream();
      });
      if (mounted) {
        final localizations = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$username ${localizations.followStopped}')),
        );
      }
    } else {
      // Takip et
      await userDocRef.update({
        'following': FieldValue.arrayUnion([userId])
      });
      setState(() {
        _followingUsers.add(userId);

        // Stream'i güncelle
        _updateFollowingStream();
      });
      if (mounted) {
        final localizations = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$username ${localizations.followStarted}')),
        );
      }
    }

    // Stream'i güncelle
    _loadFollowingUsers();
  }

  void _toggleProfileVisibility(bool value) async {
    setState(() {
      _profileVisibilityEnabled = value;
    });

    // Profil görünürlük durumunu Firebase'e kaydet
    if (_auth.currentUser != null) {
      try {
        await _firestore
            .collection('users')
            .doc(_auth.currentUser!.uid)
            .update({
          'gorunurluk': value,
        });

        // Kullanıcıya bilgi ver
        if (mounted) {
          final localizations = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_profileVisibilityEnabled
                  ? localizations.profilePublic
                  : localizations.profilePrivate),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        print('Profil görünürlüğü güncellenirken hata: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Profil görünürlüğü güncellenirken bir hata oluştu'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _usageCheckTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Ayarlardan dönüldüğünde küçük bir gecikme ile kontrol et
      Future.delayed(const Duration(milliseconds: 500), () async {
        // İzin durumunu kontrol et
        final bool hasPermission =
            await platform.invokeMethod('checkUsageStatsPermission') ?? false;
        if (hasPermission) {
          // İzin verilmişse ve dialog açıksa kapat
          if (mounted && Navigator.canPop(context)) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          _checkCurrentApp();
        } else {
          _checkCurrentApp();
        }
      });
    }
  }

  Future<void> _checkCurrentApp() async {
    try {
      // Önce izin durumunu kontrol et
      final bool hasPermission =
          await platform.invokeMethod('checkUsageStatsPermission') ?? false;
      if (hasPermission) {
        try {
          // İzin verilmiş, uygulamayı kontrol et
          final result = await platform.invokeMethod('getCurrentApp');

          // Eski API ile uyumluluk için kontrol
          if (result is String) {
            // Eski format - sadece uygulama adı döndürülüyor
            if (result != _lastTrackedApp) {
              _lastTrackedApp = result;
              await _shareActivity(result, "unknown_package");
            }
          } else if (result is Map) {
            // Yeni format - hem uygulama adı hem paket adı döndürülüyor
            final String? appName = result['appName'] as String?;
            final String? packageName = result['packageName'] as String?;

            if (appName != null &&
                packageName != null &&
                appName != _lastTrackedApp) {
              _lastTrackedApp = appName;
              await _shareActivity(appName, packageName);
            }
          }
        } catch (e) {
          print("Method channel error: $e");
        }
        return;
      }

      // İzin yoksa dialog göster
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('İzin Gerekli'),
            content: const Text(
                'Uygulama kullanım verilerini paylaşabilmek için izin gerekiyor. Ayarlara giderek izin vermek ister misiniz?'),
            actions: [
              TextButton(
                onPressed: () {
                  // Dialog'u kapatmıyoruz, sadece yeni bir dialog gösteriyoruz
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => AlertDialog(
                      title: const Text('Uyarı'),
                      content: const Text(
                          'Uygulama kullanım izni olmadan diğer kullanıcıların aktivitelerini göremezsiniz. İzin vermek ister misiniz?'),
                      actions: [
                        TextButton(
                          onPressed: () {
                            // Tekrar hayır derse yine aynı dialog gösterilecek
                          },
                          child: const Text('Hayır'),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            Navigator.pop(context);
                            await platform.invokeMethod('openAppSettings');
                            // Ayarlardan dönüldüğünde sayfayı yenile
                            if (mounted) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const UserActivityScreen(),
                                ),
                              );
                            }
                          },
                          child: const Text('Ayarlara Git'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Hayır'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await platform.invokeMethod('openAppSettings');
                  // Ayarlardan dönüldüğünde sayfayı yenile
                  if (mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UserActivityScreen(),
                      ),
                    );
                  }
                },
                child: const Text('Ayarlara Git'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print("Failed to check app usage: '${e}'.");
    }
  }

  Future<void> _shareActivity(String appName, String packageName) async {
    if (_auth.currentUser == null) {
      return;
    }

    try {
      // Önce kullanıcının nickname'ini al
      final userDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .get();

      final nickname = userDoc.data()?['nickname'] as String? ?? 'Kullanıcı';

      await _firestore.collection('user_activities').add({
        'username': nickname,
        'appName': appName,
        'packageName': packageName,
        'startTime': FieldValue.serverTimestamp(),
        'userId': _auth.currentUser!.uid,
        'isAnonymous': _auth.currentUser!.isAnonymous,
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Aktivite paylaşılırken hata oluştu: $e')),
        );
      }
    }
  }

  Future<void> _logout() async {
    try {
      // Firebase çıkışı yapmadan direkt uygulamayı kapat
      if (mounted) {
        // SystemNavigator.pop() ile uygulamayı kapat
        SystemNavigator.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Çıkış yapılırken hata oluştu: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    // Özel notification'ları dinle - FollowingScreen'den gelecek güncelleme bildirimlerini yakala
    return NotificationListener<Notification>(
      onNotification: (notification) {
        // _RefreshFollowingNotification türünde bir bildirim gelirse takip listesini güncelle
        if (notification is Notification &&
            notification.toString().contains('RefreshFollowing')) {
          print('Takip listesi güncellemesi bildirimi alındı');
          _loadFollowingUsers();
          return true; // Bildirimi işledik
        }
        return false; // Bildirimi işlemedik, üst widget'a iletle
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          drawer: Drawer(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.inversePrimary,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: _profileImage != null
                            ? MemoryImage(base64Decode(_profileImage!))
                            : null,
                        child: _profileImage == null
                            ? const Icon(Icons.person, size: 35)
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _userNickname ?? localizations.welcome,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _auth.currentUser?.isAnonymous ?? false
                            ? localizations.anonymousLoginTitle
                            : localizations.phoneLoginTitle,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(localizations.profile),
                  onTap: () {
                    // Profil sayfasına yönlendirme
                    Navigator.pop(context); // Drawer'ı kapat

                    if (_auth.currentUser != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserProfileScreen(
                            userId: _auth.currentUser!.uid,
                            username: _userNickname ?? localizations.welcome,
                            isFollowing: false, // Kendimizi takip edemeyiz
                            onToggleFollow: _toggleFollow,
                          ),
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.visibility),
                  title: Text(localizations.profileVisibility),
                  trailing: Switch(
                    value: _profileVisibilityEnabled,
                    onChanged: _toggleProfileVisibility,
                    activeColor: Theme.of(context).colorScheme.primary,
                  ),
                  onTap: () {
                    // ListTile'a tıklandığında da switch'i değiştir
                    _toggleProfileVisibility(!_profileVisibilityEnabled);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: Text(localizations.logoutButton,
                      style: const TextStyle(color: Colors.red)),
                  onTap: () async {
                    await _logout();
                  },
                ),
              ],
            ),
          ),
          appBar: AppBar(
            leading: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: Text(localizations.appTitle),
            centerTitle: true,
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            bottom: TabBar(
              tabs: [
                Tab(text: localizations.allActivities),
                Tab(text: localizations.followingActivities),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: _logout,
              ),
            ],
          ),
          body: TabBarView(
            children: [
              // Herkes sekmesi
              _buildActivityList(_allActivitiesStream),
              // Takip edilenler sekmesi
              FollowingScreen(
                activitiesStream: _followingActivitiesStream,
                followingUsers: _followingUsers,
                onToggleFollow: _toggleFollow,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final localizations = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: localizations.searchHint,
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase(); // Küçük harfe çevir
          });
        },
      ),
    );
  }

  Widget _buildActivityList(Stream<QuerySnapshot>? stream) {
    final localizations = AppLocalizations.of(context)!;

    // Eğer kullanıcının görünürlüğü kapalıysa, hiçbir aktivite gösterme
    if (!_profileVisibilityEnabled) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.visibility_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              localizations.hiddenProfileMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                    child: Text('Bir hata oluştu: ${snapshot.error}'));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // Aktiviteleri kullanıcı başına grupla
              final Map<String, ActivityItem> latestActivities = {};

              // Kendi uygulamamızın paket adı - bu gözükmeyecek
              const String ourAppPackage = "com.example.why_sup";

              // Mevcut kullanıcının ID'si - kendi aktivitelerimizi filtrelemek için
              final String? currentUserId = _auth.currentUser?.uid;

              for (var doc in snapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final userId = data['userId'] as String;
                final timestamp = data['startTime'] as Timestamp?;
                final packageName = data['packageName'] as String? ?? '';
                final username = data['username'] as String? ?? 'Anonim';

                // Kendi uygulamamızı veya kendi aktivitelerimizi filtreleme
                if (packageName == ourAppPackage || userId == currentUserId) {
                  continue;
                }

                if (!latestActivities.containsKey(userId) ||
                    (timestamp != null &&
                        timestamp
                            .toDate()
                            .isAfter(latestActivities[userId]!.startTime))) {
                  latestActivities[userId] = ActivityItem(
                    username: username,
                    appName: data['appName'] ?? 'Bilinmeyen Uygulama',
                    packageName: packageName,
                    startTime: timestamp?.toDate() ?? DateTime.now(),
                    userId: userId,
                  );
                }
              }

              final activities = latestActivities.values.toList()
                ..sort((a, b) => b.startTime.compareTo(a.startTime));

              if (activities.isEmpty) {
                return Center(
                  child: Text(localizations.noActivities),
                );
              }

              if (_searchQuery.isEmpty) {
                return _buildActivityListView(activities);
              }

              // Arama yapılıyorsa, telefon numaralarını kontrol et
              return FutureBuilder<List<ActivityItem>>(
                future: _filterActivitiesBySearch(activities),
                builder: (context, searchSnapshot) {
                  if (searchSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (searchSnapshot.hasError) {
                    return Center(
                        child: Text(
                            'Arama sırasında hata oluştu: ${searchSnapshot.error}'));
                  }

                  final filteredActivities = searchSnapshot.data ?? [];

                  if (filteredActivities.isEmpty) {
                    return const Center(child: Text('Arama sonucu bulunamadı'));
                  }

                  return _buildActivityListView(filteredActivities);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActivityListView(List<ActivityItem> activities) {
    return ListView.builder(
      itemCount: activities.length,
      itemBuilder: (context, index) {
        final activity = activities[index];
        final isFollowing = _followingUsers.contains(activity.userId);

        return ActivityCard(
          activity: activity,
          isFollowing: isFollowing,
          onToggleFollow: _toggleFollow,
        );
      },
    );
  }

  Future<List<ActivityItem>> _filterActivitiesBySearch(
      List<ActivityItem> activities) async {
    final List<ActivityItem> filteredActivities = [];

    for (var activity in activities) {
      bool matchesSearch =
          activity.username.toLowerCase().contains(_searchQuery.toLowerCase());

      if (!matchesSearch) {
        try {
          final userDoc =
              await _firestore.collection('users').doc(activity.userId).get();
          if (userDoc.exists) {
            final phoneNumber = userDoc.data()?['phoneNumber'] as String? ?? '';
            matchesSearch =
                phoneNumber.toLowerCase().contains(_searchQuery.toLowerCase());
          }
        } catch (e) {
          print('Telefon numarası kontrolünde hata: $e');
        }
      }

      if (matchesSearch) {
        filteredActivities.add(activity);
      }
    }

    return filteredActivities;
  }

  // Kullanıcıların görünürlük durumlarını toplu olarak sorgula
  Future<Map<String, bool>> _getUserVisibilityMap(
      List<QueryDocumentSnapshot> docs) async {
    // Aktivitelerdeki tüm benzersiz kullanıcı ID'lerini topla
    final Set<String> userIds = {};
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final userId = data['userId'] as String;
      userIds.add(userId);
    }

    // Her kullanıcı için görünürlük durumunu tutan map
    Map<String, bool> visibilityMap = {};

    // Kullanıcıları toplu olarak sorgula
    for (var userId in userIds) {
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          // 'gorunurluk' alanını kontrol et, varsayılan olarak true
          final isVisible = userDoc.data()?['gorunurluk'] as bool? ?? true;
          visibilityMap[userId] = isVisible;
        } else {
          // Kullanıcı bulunamadıysa varsayılan olarak görünür kabul et
          visibilityMap[userId] = true;
        }
      } catch (e) {
        print('Kullanıcı görünürlük durumu sorgulanırken hata: $e');
        // Hata durumunda varsayılan olarak görünür kabul et
        visibilityMap[userId] = true;
      }
    }

    return visibilityMap;
  }

  Future<void> _loadProfileVisibility() async {
    if (_auth.currentUser == null) return;

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .get();

      if (userDoc.exists && mounted) {
        final bool visibility = userDoc.data()?['gorunurluk'] as bool? ?? true;
        setState(() {
          _profileVisibilityEnabled = visibility;
        });
      }
    } catch (e) {
      print('Profil görünürlük bilgisi yüklenirken hata: $e');
    }
  }

  void _updateFollowingStream() {
    // _followingActivitiesStream'i güncellemek için gerekli işlemler burada yapılabilir
    // Bu örnekte, _followingActivitiesStream'i yeniden oluşturmak yeterlidir
    _followingActivitiesStream = _firestore
        .collection('user_activities')
        .where('userId',
            whereIn: _followingUsers.isEmpty ? [''] : _followingUsers.toList())
        .orderBy('startTime', descending: true)
        .snapshots();
  }

  // Kullanıcı araması için yeni fonksiyon
  Future<List<String>> _searchUsers(String query) async {
    if (query.isEmpty) return [];

    try {
      QuerySnapshot querySnapshot;
      if (query.startsWith('phonenumber:')) {
        // Telefon numarasına göre ara
        String phoneQuery = query.substring('phonenumber:'.length).trim();
        if (phoneQuery.isEmpty) return [];

        querySnapshot = await _firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: phoneQuery)
            .get();
      } else if (query.startsWith('nickname:')) {
        // Kullanıcı adına göre ara
        String nicknameQuery =
            query.substring('nickname:'.length).trim().toLowerCase();
        if (nicknameQuery.isEmpty) return [];

        querySnapshot = await _firestore
            .collection('users')
            .orderBy('nickname')
            .startAt([nicknameQuery]).endAt([nicknameQuery + '\uf8ff']).get();
      } else {
        // Varsayılan olarak kullanıcı adına göre ara
        querySnapshot = await _firestore
            .collection('users')
            .orderBy('nickname')
            .startAt([query]).endAt([query + '\uf8ff']).get();
      }

      print('Arama sonucu: ${querySnapshot.docs.length} kullanıcı bulundu');
      for (var doc in querySnapshot.docs) {
        print('Bulunan kullanıcı: ${doc.data()}');
      }

      return querySnapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      print('Kullanıcı araması sırasında hata: $e');
      return [];
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

class ActivityCard extends StatefulWidget {
  final ActivityItem activity;
  final bool isFollowing;
  final Function(String, String) onToggleFollow;

  const ActivityCard({
    Key? key,
    required this.activity,
    required this.isFollowing,
    required this.onToggleFollow,
  }) : super(key: key);

  @override
  State<ActivityCard> createState() => _ActivityCardState();
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
      print('Kullanıcı bilgileri yüklenirken hata: $e');
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
      // Dakika formatı için doğru fonksiyon çağrısı
      return localizations.minutesAgo(difference.inMinutes);
    } else {
      // Saat formatı için doğru fonksiyon çağrısı
      return localizations.hoursAgo(difference.inHours);
    }
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/user_profile.dart';
import '../../models/leaderboard_entry.dart';
import '../../services/supabase_service.dart';
import '../../services/pedometer_service.dart';
import '../admin/admin_screen.dart';
import '../auth/login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  UserProfile? _profile;
  int _todaySteps = 0;
  bool _isLoading = true;
  bool _isSyncing = false;

  List<LeaderboardEntry> _dailyRankings = [];
  List<LeaderboardEntry> _weeklyRankings = [];
  List<LeaderboardEntry> _totalRankings = [];

  StreamSubscription<int>? _stepSubscription;
  Timer? _countdownTimer;
  String _timeUntilNextHour = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });

    _initData();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final nextHour = DateTime(now.year, now.month, now.day, now.hour + 1);
      final diff = nextHour.difference(now);
      final minutes = diff.inMinutes;
      final seconds = diff.inSeconds % 60;
      if (mounted) {
        setState(() {
          _timeUntilNextHour = '${minutes}분 ${seconds}초 후 랭킹 갱신';
        });
      }
    });
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    try {
      _profile = await SupabaseService.instance.fetchMyProfile();
      await PedometerService.instance.initialize();

      _todaySteps = PedometerService.instance.todaySteps;
      _stepSubscription = PedometerService.instance.stepStream.listen((steps) {
        if (mounted) {
          setState(() => _todaySteps = steps);
        }
      });

      // 서버와 내 걸음수 동기화 및 랭킹 데이터 로드
      await _syncAndRefresh();
    } catch (e) {
      debugPrint('Initialization error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _syncAndRefresh() async {
    setState(() => _isSyncing = true);
    try {
      await SupabaseService.instance.syncTodaySteps(_todaySteps);

      final daily = await SupabaseService.instance.fetchLeaderboard(LeaderboardPeriod.daily);
      final weekly = await SupabaseService.instance.fetchLeaderboard(LeaderboardPeriod.weekly);
      final total = await SupabaseService.instance.fetchLeaderboard(LeaderboardPeriod.total);

      if (mounted) {
        setState(() {
          _dailyRankings = daily;
          _weeklyRankings = weekly;
          _totalRankings = total;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('동기화 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _stepSubscription?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  LeaderboardPeriod get _currentPeriod {
    switch (_tabController.index) {
      case 1:
        return LeaderboardPeriod.weekly;
      case 2:
        return LeaderboardPeriod.total;
      default:
        return LeaderboardPeriod.daily;
    }
  }

  List<LeaderboardEntry> get _currentRankingList {
    switch (_tabController.index) {
      case 1:
        return _weeklyRankings;
      case 2:
        return _totalRankings;
      default:
        return _dailyRankings;
    }
  }

  LeaderboardEntry? get _myCurrentRankEntry {
    return _currentRankingList.where((e) => e.isCurrentUser).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat('#,###');

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.directions_walk_rounded, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Text(
              '스쿨 워크온',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          if (_profile?.role == UserRole.admin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: '관리자 포털',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminScreen()),
                );
              },
            ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: '걸음수 동기화',
            onPressed: _isSyncing ? null : _syncAndRefresh,
          ),
          PopupMenuButton<String>(
            onSelected: (val) async {
              if (val == 'logout') {
                await SupabaseService.instance.signOut();
                if (mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: const [
                    Icon(Icons.logout, size: 20, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('로그아웃'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blueAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blueAccent,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: '일간 걸음수'),
            Tab(text: '주간 누적'),
            Tab(text: '총 누적'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1시간 업데이트 알림 & 리셋 정책 띠배너
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: const Color(0xFFE0E7FF),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF4338CA)),
                      const SizedBox(width: 6),
                      Text(
                        _timeUntilNextHour,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4338CA),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _tabController.index == 0
                            ? '매일 00:00 리셋'
                            : (_tabController.index == 1 ? '일요일 23:59 리셋' : '전체 누적'),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF4338CA)),
                      ),
                    ],
                  ),
                ),

                // 오늘 내 걸음수 요약 카드
                _buildMyDailySummaryCard(numberFormat),

                // 랭킹 리스트 및 1~3위 포디움
                Expanded(
                  child: _currentRankingList.isEmpty
                      ? const Center(
                          child: Text(
                            '아직 등록된 랭킹 데이터가 없습니다.\n첫 걸음을 걷고 동기화해보세요!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _currentRankingList.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              // 상단 1~3위 포디움 시각화
                              return _buildPodiumWidget(numberFormat);
                            }
                            final entry = _currentRankingList[index - 1];
                            return _buildRankingItem(entry, numberFormat);
                          },
                        ),
                ),
              ],
            ),
      // 하단 내 순위 스티키 바
      bottomSheet: _buildStickyMyRankBar(numberFormat),
    );
  }

  Widget _buildMyDailySummaryCard(NumberFormat format) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_profile?.nickname ?? "참여자"} 님의 오늘 걸음수',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    format.format(_todaySteps),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('걸음', style: TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '1일 유효 상한: 35,000보',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          // 디버그/테스트용 걸음수 증가 버튼 (+500보)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.blueAccent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              await PedometerService.instance.addSimulatedSteps(500);
              await _syncAndRefresh();
            },
            child: const Text('+500보 테스트'),
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumWidget(NumberFormat format) {
    if (_currentRankingList.length < 3) return const SizedBox.shrink();

    final first = _currentRankingList[0];
    final second = _currentRankingList[1];
    final third = _currentRankingList[2];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2위 은메달
          _buildPodiumColumn(second, 2, Colors.blueGrey.shade300, 80, format),
          // 1위 금메달
          _buildPodiumColumn(first, 1, Colors.amber.shade400, 110, format),
          // 3위 동메달
          _buildPodiumColumn(third, 3, Colors.brown.shade300, 65, format),
        ],
      ),
    );
  }

  Widget _buildPodiumColumn(
      LeaderboardEntry entry, int rank, Color color, double height, NumberFormat format) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.emoji_events_rounded,
          color: color,
          size: rank == 1 ? 32 : 24,
        ),
        const SizedBox(height: 4),
        Text(
          entry.nickname,
          style: TextStyle(
            fontWeight: rank == 1 ? FontWeight.bold : FontWeight.w600,
            fontSize: rank == 1 ? 14 : 12,
          ),
        ),
        Text(
          '${format.format(entry.steps)}보',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        Container(
          width: 70,
          height: height,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            '$rank위',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: color.withOpacity(0.9),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRankingItem(LeaderboardEntry entry, NumberFormat format) {
    final isMe = entry.isCurrentUser;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isMe ? Border.all(color: Colors.blueAccent, width: 1.5) : null,
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: entry.rank <= 3 ? Colors.amber.shade50 : Colors.grey.shade100,
          ),
          alignment: Alignment.center,
          child: Text(
            '${entry.rank}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: entry.rank <= 3 ? Colors.amber.shade800 : Colors.black800,
            ),
          ),
        ),
        title: Text(
          entry.nickname,
          style: TextStyle(
            fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
            color: isMe ? Colors.blueAccent : Colors.black87,
          ),
        ),
        trailing: Text(
          '${format.format(entry.steps)} 보',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isMe ? Colors.blueAccent : const Color(0xFF1E293B),
          ),
        ),
      ),
    );
  }

  Widget? _buildStickyMyRankBar(NumberFormat format) {
    final myEntry = _myCurrentRankEntry;
    if (myEntry == null) return null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blueAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${myEntry.rank}위',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${myEntry.nickname} (나)',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            Text(
              '${format.format(myEntry.steps)} 보',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

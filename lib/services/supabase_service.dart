import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../models/leaderboard_entry.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  // 1. 회원가입 (실명, 학번, 구분, 닉네임)
  Future<void> registerUser({
    required String email,
    required String password,
    required String nickname,
    required String realName,
    required String studentId,
    required UserRole role,
  }) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw Exception('회원가입에 실패했습니다.');
    }

    final roleStr = role == UserRole.staff ? 'STAFF' : 'STUDENT';

    // profiles 테이블에 민감정보 및 기본 PENDING 상태로 레코드 생성
    await client.from('profiles').insert({
      'id': user.id,
      'nickname': nickname.trim(),
      'real_name': realName.trim(),
      'student_id': studentId.trim(),
      'role': roleStr,
      'status': 'PENDING',
    });
  }

  // 2. 로그인
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // 3. 로그아웃
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  // 4. 내 프로필 조회
  Future<UserProfile?> fetchMyProfile() async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null) return null;

    final data = await client
        .from('profiles')
        .select()
        .eq('id', currentUser.id)
        .maybeSingle();

    if (data == null) return null;
    return UserProfile.fromJson(data);
  }

  // 5. 걸음수 서버 동기화 (최대 35,000보 제한 및 UPSERT)
  Future<void> syncTodaySteps(int steps) async {
    final currentUser = client.auth.currentUser;
    if (currentUser == null) return;

    // 치팅 방지 상한선
    final validSteps = steps.clamp(0, 35000);
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);

    await client.from('daily_steps').upsert({
      'user_id': currentUser.id,
      'date': todayStr,
      'steps': validSteps,
      'synced_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,date');
  }

  // 6. 1시간 단위 캐시된 랭킹 스냅샷 조회
  Future<List<LeaderboardEntry>> fetchLeaderboard(LeaderboardPeriod period) async {
    final typeStr = period == LeaderboardPeriod.daily
        ? 'DAILY'
        : (period == LeaderboardPeriod.weekly ? 'WEEKLY' : 'TOTAL');

    final currentUserId = client.auth.currentUser?.id;

    // 최신 스냅샷 시점 조회
    final latestSnap = await client
        .from('leaderboard_snapshots')
        .select('snapshot_time')
        .eq('type', typeStr)
        .order('snapshot_time', ascending: false)
        .limit(1)
        .maybeSingle();

    if (latestSnap == null) {
      // 스냅샷이 아직 생성되지 않은 초기 상태인 경우 view에서 직접 집계
      return _fetchDirectLeaderboard(period, currentUserId);
    }

    final String snapshotTime = latestSnap['snapshot_time'];

    final List<dynamic> data = await client
        .from('leaderboard_snapshots')
        .select('rank, user_id, nickname, steps')
        .eq('type', typeStr)
        .eq('snapshot_time', snapshotTime)
        .order('rank', ascending: true);

    return data
        .map((e) => LeaderboardEntry.fromJson(e, currentUserId: currentUserId))
        .toList();
  }

  // 초기 스냅샷이 없을 때 실시간 뷰 조회
  Future<List<LeaderboardEntry>> _fetchDirectLeaderboard(
      LeaderboardPeriod period, String? currentUserId) async {
    final col = period == LeaderboardPeriod.daily
        ? 'today_steps'
        : (period == LeaderboardPeriod.weekly ? 'weekly_steps' : 'total_steps');

    final List<dynamic> data = await client
        .from('public_leaderboard_view')
        .select('user_id, nickname, $col')
        .order(col, ascending: false);

    int currentRank = 1;
    return data.map((e) {
      return LeaderboardEntry(
        rank: currentRank++,
        userId: e['user_id'],
        nickname: e['nickname'],
        steps: e[col] as int? ?? 0,
        isCurrentUser: currentUserId != null && currentUserId == e['user_id'],
      );
    }).toList();
  }

  // ----------------------------------------------------
  // 관리자 전용 기능 (Admin Portal)
  // ----------------------------------------------------

  // 승인 대기자 목록 조회
  Future<List<UserProfile>> fetchPendingUsers() async {
    final List<dynamic> data = await client
        .from('profiles')
        .select()
        .eq('status', 'PENDING')
        .order('created_at', ascending: true);

    return data.map((e) => UserProfile.fromJson(e)).toList();
  }

  // 전체 회원 목록 조회 (관리자용: 실명, 학번, 소속 확인)
  Future<List<UserProfile>> fetchAllUsersForAdmin() async {
    final List<dynamic> data = await client
        .from('profiles')
        .select()
        .order('created_at', ascending: false);

    return data.map((e) => UserProfile.fromJson(e)).toList();
  }

  // 사용자 승인
  Future<void> approveUser(String userId) async {
    await client
        .from('profiles')
        .update({'status': 'APPROVED'})
        .eq('id', userId);
  }

  // 사용자 반려
  Future<void> rejectUser(String userId) async {
    await client
        .from('profiles')
        .update({'status': 'REJECTED'})
        .eq('id', userId);
  }
}

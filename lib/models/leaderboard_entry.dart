enum LeaderboardPeriod { daily, weekly, total }

class LeaderboardEntry {
  final int rank;
  final String userId;
  final String nickname;
  final int steps;
  final bool isCurrentUser;

  LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.nickname,
    required this.steps,
    this.isCurrentUser = false,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json, {String? currentUserId}) {
    final uid = json['user_id'] as String? ?? '';
    return LeaderboardEntry(
      rank: json['rank'] as int? ?? 0,
      userId: uid,
      nickname: json['nickname'] as String? ?? '익명',
      steps: json['steps'] as int? ?? 0,
      isCurrentUser: currentUserId != null && currentUserId == uid,
    );
  }
}

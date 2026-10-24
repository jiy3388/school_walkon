enum UserRole { student, staff, admin }
enum ApprovalStatus { pending, approved, rejected }

class UserProfile {
  final String id;
  final String nickname;
  final String? realName;     // 관리자 및 본인만 열람 가능
  final String? studentId;    // 관리자 및 본인만 열람 가능
  final UserRole role;
  final ApprovalStatus status;
  final DateTime createdAt;

  UserProfile({
    required this.id,
    required this.nickname,
    this.realName,
    this.studentId,
    required this.role,
    required this.status,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      nickname: json['nickname'] as String? ?? '익명',
      realName: json['real_name'] as String?,
      studentId: json['student_id'] as String?,
      role: _parseRole(json['role'] as String?),
      status: _parseStatus(json['status'] as String?),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : DateTime.now(),
    );
  }

  static UserRole _parseRole(String? role) {
    switch (role?.toUpperCase()) {
      case 'STAFF':
        return UserRole.staff;
      case 'ADMIN':
        return UserRole.admin;
      default:
        return UserRole.student;
    }
  }

  static ApprovalStatus _parseStatus(String? status) {
    switch (status?.toUpperCase()) {
      case 'APPROVED':
        return ApprovalStatus.approved;
      case 'REJECTED':
        return ApprovalStatus.rejected;
      default:
        return ApprovalStatus.pending;
    }
  }

  String get roleLabel {
    switch (role) {
      case UserRole.student:
        return '학생';
      case UserRole.staff:
        return '교직원';
      case UserRole.admin:
        return '관리자';
    }
  }
}

import 'package:flutter/material.dart';
import '../../models/user_profile.dart';
import '../../services/supabase_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<UserProfile> _pendingUsers = [];
  List<UserProfile> _allUsers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  UserRole? _filterRole;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
    setState(() => _isLoading = true);
    try {
      final pending = await SupabaseService.instance.fetchPendingUsers();
      final all = await SupabaseService.instance.fetchAllUsersForAdmin();

      if (mounted) {
        setState(() {
          _pendingUsers = pending;
          _allUsers = all;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로드 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approveUser(String userId, String nickname) async {
    try {
      await SupabaseService.instance.approveUser(userId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nickname 님의 가입이 승인되었습니다.')),
      );
      _loadAdminData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('승인 실패: $e')),
      );
    }
  }

  Future<void> _rejectUser(String userId, String nickname) async {
    try {
      await SupabaseService.instance.rejectUser(userId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$nickname 님의 가입이 반려되었습니다.')),
      );
      _loadAdminData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('반려 실패: $e')),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<UserProfile> get _filteredAllUsers {
    return _allUsers.where((u) {
      final matchesRole = _filterRole == null || u.role == _filterRole;
      final q = _searchQuery.toLowerCase();
      final matchesQuery = q.isEmpty ||
          (u.realName?.toLowerCase().contains(q) ?? false) ||
          (u.studentId?.toLowerCase().contains(q) ?? false) ||
          u.nickname.toLowerCase().contains(q);
      return matchesRole && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('관리자 포털 (학생/교직원 신원 관리)'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _loadAdminData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.amberAccent,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amberAccent,
          tabs: [
            Tab(text: '승인 대기 (${_pendingUsers.length})'),
            Tab(text: '전체 회원 (${_allUsers.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPendingTab(),
                _buildAllUsersTab(),
              ],
            ),
    );
  }

  Widget _buildPendingTab() {
    if (_pendingUsers.isEmpty) {
      return const Center(
        child: Text(
          '승인 대기 중인 회원이 없습니다.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingUsers.length,
      itemBuilder: (context, index) {
        final user = _pendingUsers[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: user.role == UserRole.student
                            ? Colors.blue.shade100
                            : Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        user.roleLabel,
                        style: TextStyle(
                          color: user.role == UserRole.student
                              ? Colors.blue.shade900
                              : Colors.purple.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '닉네임: ${user.nickname}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    const Icon(Icons.person, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text('실명: ${user.realName ?? "-"}'),
                    const SizedBox(width: 24),
                    const Icon(Icons.badge, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text('${user.role == UserRole.student ? "학번" : "사번"}: ${user.studentId ?? "-"}'),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                      onPressed: () => _rejectUser(user.id, user.nickname),
                      child: const Text('반려'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _approveUser(user.id, user.nickname),
                      child: const Text('승인'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAllUsersTab() {
    return Column(
      children: [
        // 필터 및 검색 바
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: '실명, 학번, 닉네임 검색',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('전체'),
                    selected: _filterRole == null,
                    onSelected: (sel) => setState(() => _filterRole = null),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('학생'),
                    selected: _filterRole == UserRole.student,
                    onSelected: (sel) => setState(() => _filterRole = UserRole.student),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('교직원'),
                    selected: _filterRole == UserRole.staff,
                    onSelected: (sel) => setState(() => _filterRole = UserRole.staff),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _filteredAllUsers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = _filteredAllUsers[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: user.role == UserRole.student
                      ? Colors.blue.shade100
                      : Colors.purple.shade100,
                  child: Text(
                    user.role == UserRole.student ? '학' : '교',
                    style: TextStyle(
                      color: user.role == UserRole.student
                          ? Colors.blue.shade800
                          : Colors.purple.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text('${user.realName} (${user.nickname})'),
                subtitle: Text('${user.roleLabel} · 학번/사번: ${user.studentId}'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: user.status == ApprovalStatus.approved
                        ? Colors.green.shade50
                        : (user.status == ApprovalStatus.pending
                            ? Colors.amber.shade50
                            : Colors.red.shade50),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: user.status == ApprovalStatus.approved
                          ? Colors.green
                          : (user.status == ApprovalStatus.pending
                              ? Colors.amber
                              : Colors.red),
                    ),
                  ),
                  child: Text(
                    user.status == ApprovalStatus.approved
                        ? '승인됨'
                        : (user.status == ApprovalStatus.pending ? '대기중' : '반려됨'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: user.status == ApprovalStatus.approved
                          ? Colors.green.shade800
                          : (user.status == ApprovalStatus.pending
                              ? Colors.amber.shade800
                              : Colors.red.shade800),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';
import 'models/user_profile.dart';
import 'views/auth/login_screen.dart';
import 'views/auth/pending_screen.dart';
import 'views/home/home_screen.dart';
import 'views/admin/admin_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 실제 Supabase 프로젝트의 URL과 anon key를 입력해주세요.
  // 로컬 테스트용 기본 mock/dummy 값이 들어있습니다.
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://your-supabase-project.supabase.co'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'your-anon-key'),
  );

  runApp(const SchoolWalkOnApp());
}

class SchoolWalkOnApp extends StatelessWidget {
  const SchoolWalkOnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '스쿨 워크온',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
        fontFamily: 'Pretendard',
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      return const LoginScreen();
    }

    return FutureBuilder<UserProfile?>(
      future: SupabaseService.instance.fetchMyProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final profile = snapshot.data;
        if (profile == null) {
          return const LoginScreen();
        }

        if (profile.role == UserRole.admin) {
          return const AdminScreen();
        }

        if (profile.status == ApprovalStatus.pending) {
          return const PendingScreen();
        }

        return const HomeScreen();
      },
    );
  }
}

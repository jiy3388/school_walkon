# 🏆 스쿨 워크온 (School WalkOn)

학교 학생 및 교직원 300명을 위한 실시간 만보기 경쟁 플랫폼입니다.

---

## 📌 주요 기능 및 정책

1. **3개 랭킹 차트 지원**
   - **일간 걸음수 랭킹**: 매일 자정(00:00:00 KST) 리셋
   - **주간 누적 걸음수 랭킹**: 매주 일요일 23:59:59 KST 리셋
   - **총 누적 걸음수 랭킹**: 전체 누적 순위
2. **1시간 단위 랭킹 스냅샷 갱신**
   - 매시 00분마다 전체 300명의 순위를 서버가 자동 집계하여 스냅샷 캐시
   - 앱 상단에 다음 랭킹 갱신까지 남은 카운트다운 타이머 노출
3. **철저한 개인정보 보호 & 익명 경쟁**
   - 일반 참여자에게는 오직 **닉네임**과 **걸음수/순위**만 공개
   - **실명, 학번/사번, 소속 구분(학생/교직원)**은 관리자만 열람 가능 (PostgreSQL Row-Level Security 적용)
4. **관리자 승인 시스템**
   - 가입 즉시 대기(`PENDING`) 상태 부여
   - 관리자가 실명/학번 검증 후 원클릭 승인/반려
5. **치팅 방지 정책**
   - 1일 유효 최대 걸음수 35,000보 상한선 적용 (기계 흔들기 등 어뷰징 차단)
6. **명예의 전당**
   - 매일 자정 및 매주 일요일 마감 시 TOP 3를 명예의 전당에 영구 보관

---

## 📁 프로젝트 구조

```
school_walkon/
├── lib/
│   ├── main.dart                       # 엔트리포인트 및 AuthGate 라우팅
│   ├── models/
│   │   ├── user_profile.dart           # 사용자 모델 (역할, 승인상태)
│   │   └── leaderboard_entry.dart      # 랭킹 모델
│   ├── services/
│   │   ├── supabase_service.dart       # Supabase 연동 & RLS 안전 쿼리
│   │   └── pedometer_service.dart      # 기기 만보기 센서 측정
│   └── views/
│       ├── auth/
│       │   ├── login_screen.dart       # 로그인 화면
│       │   ├── register_screen.dart    # 회원가입 (실명, 학번, 닉네임)
│       │   └── pending_screen.dart     # 관리자 승인 대기 화면
│       ├── home/
│       │   └── home_screen.dart        # 3대 랭킹 탭, 포디움, 내 순위 바
│       └── admin/
│           └── admin_screen.dart       # 관리자 포털 (승인/반려, 명단 검색)
├── supabase/
│   └── migrations/
│       └── 001_initial_schema.sql      # DB 스키마, RLS 보안 규칙, 배치 함수
├── backend/
│   ├── cron_worker.js                  # 1시간 랭킹 스냅샷 & 자정/주간 리셋 배치
│   ├── package.json
│   └── .env.example
├── android/                            # Android 피트니스 권한 설정
└── ios/                                # iOS Motion & Fitness 권한 설정
```

---

## 🚀 빠른 시작 가이드

### 1. Supabase 데이터베이스 설정
1. [Supabase](https://supabase.com)에서 무료 프로젝트를 생성합니다.
2. Supabase 대시보드의 **SQL Editor**로 이동합니다.
3. `supabase/migrations/001_initial_schema.sql` 파일의 내용을 붙여넣고 실행(`RUN`)합니다.
4. **Project Settings > API**에서 `Project URL`과 `anon public key`를 복사합니다.

### 2. 1시간 배치 워커 실행 (Backend)
```bash
cd backend
npm install
cp .env.example .env
# .env 파일에 SUPABASE_URL 과 SUPABASE_SERVICE_ROLE_KEY 입력

# 1회 즉시 스냅샷 계산 테스트
npm run test-batch

# 1시간 주기 스케줄러 상시 가동
npm start
```

### 3. Flutter 앱 실행 (Mobile Client)
```bash
# 의존성 설치
flutter pub get

# 앱 실행 (Supabase 접속 환경변수 지정)
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

### 4. 관리자 계정 부여 방법
- 첫 계정으로 가입 후 Supabase Table Editor의 `profiles` 테이블에서 해당 사용자의 `role`을 `'ADMIN'`으로 변경하고 `status`를 `'APPROVED'`로 업데이트하면 즉시 관리자 포털에 접근할 수 있습니다.

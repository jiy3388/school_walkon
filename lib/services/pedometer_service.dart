import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PedometerService {
  static final PedometerService instance = PedometerService._internal();
  PedometerService._internal();

  StreamSubscription<StepCount>? _stepCountSubscription;
  int _todayBaseSteps = 0;
  int _currentSensorSteps = 0;
  int _todayCalculatedSteps = 0;

  final _stepStreamController = StreamController<int>.broadcast();
  Stream<int> get stepStream => _stepStreamController.stream;
  int get todaySteps => _todayCalculatedSteps;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = prefs.getString('step_date');

    if (savedDate != todayStr) {
      // 새로운 날짜 (자정 리셋)
      _todayBaseSteps = 0;
      await prefs.setString('step_date', todayStr);
      await prefs.setInt('base_sensor_steps', 0);
      await prefs.setInt('today_steps', 0);
    } else {
      _todayBaseSteps = prefs.getInt('base_sensor_steps') ?? 0;
      _todayCalculatedSteps = prefs.getInt('today_steps') ?? 0;
      _stepStreamController.add(_todayCalculatedSteps);
    }

    await _requestPermissions();
    _startListening();
  }

  Future<bool> _requestPermissions() async {
    if (kIsWeb) return false;
    final status = await Permission.activityRecognition.request();
    final sensorStatus = await Permission.sensors.request();
    return status.isGranted || sensorStatus.isGranted;
  }

  void _startListening() {
    try {
      _stepCountSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onStepCountError,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('Pedometer sensor not available on this platform/device: $e');
    }
  }

  void _onStepCount(StepCount event) async {
    _currentSensorSteps = event.steps;
    final prefs = await SharedPreferences.getInstance();

    if (_todayBaseSteps == 0) {
      _todayBaseSteps = _currentSensorSteps;
      await prefs.setInt('base_sensor_steps', _todayBaseSteps);
    }

    int stepsToday = _currentSensorSteps - _todayBaseSteps;
    if (stepsToday < 0) {
      // 기기 재부팅 등으로 센서 카운트가 리셋된 경우
      _todayBaseSteps = _currentSensorSteps;
      await prefs.setInt('base_sensor_steps', _todayBaseSteps);
      stepsToday = 0;
    }

    // 35,000보 상한선 적용
    _todayCalculatedSteps = stepsToday.clamp(0, 35000);
    await prefs.setInt('today_steps', _todayCalculatedSteps);
    _stepStreamController.add(_todayCalculatedSteps);
  }

  void _onStepCountError(dynamic error) {
    debugPrint('Pedometer Stream Error: $error');
  }

  // 디버깅/시뮬레이터 테스트용 수동 걸음수 추가 메서드
  Future<void> addSimulatedSteps(int count) async {
    _todayCalculatedSteps = (_todayCalculatedSteps + count).clamp(0, 35000);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('today_steps', _todayCalculatedSteps);
    _stepStreamController.add(_todayCalculatedSteps);
  }

  void dispose() {
    _stepCountSubscription?.cancel();
    _stepStreamController.close();
  }
}

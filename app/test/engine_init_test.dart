// 第二十七批（人類拍板 2026-11-10）：Rust 引擎初始化防禦 helper 的單元測試。
// 全程假件注入（init／recordFailure／recordRecovered／delay），不觸
// sqflite／AppSettings；記錄語意＝「每次失敗都印、只有最終仍失敗才落 kv」。
import 'package:flutter_test/flutter_test.dart';

import 'package:homing/engine_init.dart';

void main() {
  test('①首次即成功 → true＋清旗標 1 次；不落失敗記錄、不 delay、只 init 1 次',
      () async {
    final failures = <String>[];
    var recovered = 0;
    var delays = 0;
    var inits = 0;
    final ok = await initRustEngine(
      init: () async => inits++,
      delay: (d) async => delays++,
      recordFailure: (e) async => failures.add(e),
      recordRecovered: () async => recovered++,
    );
    expect(ok, isTrue);
    expect(inits, 1);
    expect(recovered, 1);
    expect(failures, isEmpty); // 成功路徑不得有任何記錄副作用
    expect(delays, 0); // 一次成功＝不該等待重試
  });

  test('②失敗一次後重試成功 → delay 1 次（預設 2s）；清旗標；不落 kv 失敗記錄',
      () async {
    final failures = <String>[];
    final delayArgs = <Duration>[];
    var recovered = 0;
    var inits = 0;
    final ok = await initRustEngine(
      init: () async {
        inits++;
        if (inits == 1) {
          throw StateError('第一次引爆炸彈');
        }
      },
      delay: (d) async => delayArgs.add(d),
      recordFailure: (e) async => failures.add(e),
      recordRecovered: () async => recovered++,
    );
    expect(ok, isTrue);
    expect(inits, 2);
    expect(delayArgs, <Duration>[const Duration(seconds: 2)]);
    expect(recovered, 1);
    // 語意：僅 print 每次失敗；fall 到 kv 旗標的只有「最終仍失敗」。
    expect(failures, isEmpty);
  });

  test('③兩次皆失敗 → false＋最後一次原因落記錄（僅 1 筆）＋不清旗標', () async {
    final failures = <String>[];
    var recovered = 0;
    var delays = 0;
    final ok = await initRustEngine(
      init: () async => throw StateError('boom'),
      delay: (d) async => delays++,
      recordFailure: (e) async => failures.add(e),
      recordRecovered: () async => recovered++,
    );
    expect(ok, isFalse);
    expect(failures.length, 1); // 記錄端只在終局寫入（最後原因）
    expect(failures.single, contains('boom'));
    expect(recovered, 0); // 未成功不得清旗標
    expect(delays, 1); // 重試間隔僅發生一次（2 次嘗試）
  });

  test('④清旗標（recordRecovered）擲例外 ≠ 引擎失敗：判定不變、不重試、不記錄',
      () async {
    final failures = <String>[];
    var delays = 0;
    var inits = 0;
    final ok = await initRustEngine(
      init: () async => inits++,
      delay: (d) async => delays++,
      recordFailure: (e) async => failures.add(e),
      recordRecovered: () async => throw StateError('kv 掛了'),
    );
    expect(ok, isTrue); // 引擎已就緒；kv 清除失敗不誤報
    expect(inits, 1);
    expect(failures, isEmpty);
    expect(delays, 0);
  });
}

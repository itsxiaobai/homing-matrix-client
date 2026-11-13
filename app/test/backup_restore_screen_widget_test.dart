// 金鑰備份診斷與還原頁測試（解密案修法 #1）。
// 全部用注入 fake（不打網路、不碰真實金鑰）；驗證三種判決與錯誤透明化。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:homing/ui/backup_restore_screen.dart';

GetRoomKeysVersionCurrentResponse _fakeInfo() =>
    GetRoomKeysVersionCurrentResponse(
      algorithm: BackupAlgorithm.mMegolmBackupV1Curve25519AesSha2,
      authData: <String, Object?>{'public_key': 'PKSERVER'},
      count: 2,
      etag: 'etag-1',
      version: 'v1',
    );

RoomKeys _fakeKeys({int sessions = 2}) => RoomKeys.fromJson(<String, Object?>{
      'rooms': {
        '!room:a': {
          'sessions': {
            for (var i = 0; i < sessions; i++)
              'session$i': <String, Object?>{
                'first_message_index': 0,
                'forwarded_count': 0,
                'is_verified': false,
                'session_data': <String, Object?>{
                  'ephemeral': 'E',
                  'ciphertext': 'C',
                  'mac': 'M',
                },
              },
          },
        },
      },
    });

void main() {
  testWidgets('查詢備份狀態：顯示版本／演算法／數量／伺服器公鑰', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackupRestoreScreen(
          deps: BackupRestoreDeps(
            loadInfo: () async => _fakeInfo(),
            fetchKeys: (_) async => _fakeKeys(),
            restore: (_) async {},
            probeSession: (_, _) => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查詢備份狀態'));
    await tester.pumpAndSettle();

    expect(find.textContaining('備份版本：v1'), findsOneWidget);
    expect(find.textContaining('m.megolm_backup.v1.curve25519-aes-sha2'),
        findsOneWidget);
    expect(find.textContaining('session 數：2'), findsOneWidget);
    expect(find.textContaining('PKSERVER'), findsOneWidget);
  });

  testWidgets('還原成功判決：抽樣全部存入', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackupRestoreScreen(
          deps: BackupRestoreDeps(
            loadInfo: () async => _fakeInfo(),
            fetchKeys: (_) async => _fakeKeys(),
            restore: (_) async {},
            probeSession: (_, _) => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('從備份還原並判決'));
    await tester.pumpAndSettle();

    expect(find.textContaining('還原成功'), findsOneWidget);
    expect(find.textContaining('2/2'), findsOneWidget);
  });

  testWidgets('還原未生效判決：官方流程無錯但 session 未存入', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackupRestoreScreen(
          deps: BackupRestoreDeps(
            loadInfo: () async => _fakeInfo(),
            fetchKeys: (_) async => _fakeKeys(),
            restore: (_) async {},
            probeSession: (_, _) => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('從備份還原並判決'));
    await tester.pumpAndSettle();

    expect(find.textContaining('還原未生效'), findsOneWidget);
    expect(find.textContaining('0/2'), findsOneWidget);
    expect(find.textContaining('SSSS'), findsOneWidget);
  });

  testWidgets('錯誤透明化：顯示真實例外內容，不再遮蔽', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackupRestoreScreen(
          deps: BackupRestoreDeps(
            loadInfo: () async => _fakeInfo(),
            fetchKeys: (_) async => throw Exception('boom-real-message'),
            restore: (_) async {},
            probeSession: (_, _) => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('從備份還原並判決'));
    await tester.pumpAndSettle();

    expect(find.textContaining('診斷失敗'), findsOneWidget);
    expect(find.textContaining('boom-real-message'), findsOneWidget);
  });

  testWidgets('備份內無 session 時顯示明確說明', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BackupRestoreScreen(
          deps: BackupRestoreDeps(
            loadInfo: () async => _fakeInfo(),
            fetchKeys: (_) async => _fakeKeys(sessions: 0),
            restore: (_) async {},
            probeSession: (_, _) => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('從備份還原並判決'));
    await tester.pumpAndSettle();

    expect(find.textContaining('沒有任何 session'), findsOneWidget);
  });
}

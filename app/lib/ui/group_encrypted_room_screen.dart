// 2.3 group Megolm E2EE — UI skeleton only
// Agent does NOT author encryption algorithm; through CryptoBridge only.
// 全部 cryptographic procedure delegated to matrix SDK official APIs.
import 'package:flutter/material.dart';

class GroupEncryptedRoomScreen extends StatelessWidget {
  const GroupEncryptedRoomScreen({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('加密群組 skeleton')),
      body: Center(child: Text('Room: $roomId（SDK official E2EE, no agent crypto）')),
    );
  }
}

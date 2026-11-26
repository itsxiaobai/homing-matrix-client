// 第七十批 c：Compound Icons（Element 官方設計系統，AGPL-3.0）——
// 直接渲染 compound-design-tokens 的官方 SVG（assets/icons/compound/），
// 以 colorFilter 著色（SVG 用 fill="currentColor"）。
//
// 來源：github.com/element-hq/compound-design-tokens（AGPL-3.0；與 Homing
// 授權相容）。僅取圖示 SVG，不取 Element 品牌／logo／角色素材。
// **第七十批 c 覆蓋第六十八批的 LINE 自繪圖示**（人類 2026-11-19 裁決）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Compound icon 名稱（對應 assets/icons/compound/ 下的 .svg 檔）。
class CompoundIcons {
  static const String search = 'search';
  static const String home = 'home';
  static const String homeSolid = 'home-solid';
  static const String chat = 'chat';
  static const String chatSolid = 'chat-solid';
  static const String user = 'user';
  static const String userAdd = 'user-add';
  static const String notifications = 'notifications';
  static const String notificationsOff = 'notifications-off';
  static const String plus = 'plus';
  static const String menu = 'menu';
  static const String chevronDown = 'chevron-down';
  static const String chevronLeft = 'chevron-left';
  static const String chevronRight = 'chevron-right';
  static const String arrowLeft = 'arrow-left';
  static const String camera = 'camera';
  static const String image = 'image';
  static const String reaction = 'reaction-add';
  static const String micOn = 'mic-on';
  static const String micOff = 'mic-off';
  static const String send = 'send';
  static const String sendSolid = 'send-solid';
  static const String play = 'play-solid';
  static const String pause = 'pause-solid';
  static const String stop = 'stop-solid';
  static const String document = 'document';
  static const String files = 'files';
  static const String close = 'close';
  static const String share = 'share';
  static const String pin = 'pin';
  static const String settings = 'settings';
  static const String edit = 'edit';
  static const String check = 'check';
  static const String visibilityOff = 'visibility-off';
  static const String visibilityOn = 'visibility-on';
  static const String delete = 'delete';
  static const String markRead = 'mark-as-read';
  static const String markUnread = 'mark-as-unread';
  static const String reply = 'reply';
  static const String forward = 'forward';
  static const String copy = 'copy';
  static const String block = 'block';
  static const String poll = 'polls';
  static const String group = 'group';
  static const String info = 'info';
  static const String key = 'key';
  static const String locationPin = 'location-pin';
  static const String folder = 'folder';
  static const String chevronUp = 'chevron-up';
  static const String expand = 'expand';
  static const String expandAll = 'expand-all';
  static const String error = 'error';
  static const String warning = 'warning';

  // 2026-11-20：補齊官方 icon（先前僅匯入 57/247，造成近似替代）。
  static const String voiceCall = 'voice-call';
  static const String voiceCallSolid = 'voice-call-solid';
  static const String videoCall = 'video-call';
  static const String translate = 'translate';
  static const String calendar = 'calendar';
  static const String time = 'time';
  static const String signOut = 'sign-out';
  static const String devices = 'devices';
  static const String devicePasskey = 'device-passkey';
  static const String computer = 'computer';
  static const String verified = 'verified';
  static const String bug = 'bug';
  static const String code = 'code';
  static const String download = 'download';
  static const String offline = 'offline';
  static const String collapse = 'collapse';
  static const String theme = 'theme';
  static const String takePhoto = 'take-photo';
  static const String qrCode = 'qr-code';
  static const String restart = 'restart';
  static const String leave = 'leave';
  static const String attachment = 'attachment';

  // 2026-11-20 第二輪：文字格式／通話控制圖示。
  static const String textFormatting = 'text-formatting';
  static const String videoCallOff = 'video-call-off';
  static const String volumeOn = 'volume-on';
  static const String volumeOff = 'volume-off';
  static const String endCall = 'end-call';
  static const String shareScreen = 'share-screen';
  static const String popOut = 'pop-out';
  static const String record = 'record';
  static const String switchCamera = 'switch-camera-solid';
  static const String earpiece = 'earpiece';
  static const String windows = 'windows'; // PiP（官方無專用圖，取重疊視窗）
}

/// 渲染一個 Compound SVG icon（著色＋尺寸）。
class CompoundIcon extends StatelessWidget {
  const CompoundIcon(
    this.name, {
    required this.size,
    required this.color,
    super.key,
  });

  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/compound/$name.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

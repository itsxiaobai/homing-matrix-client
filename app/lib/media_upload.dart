// 2.8 上傳輔助：背景 isolate 預處理（SDK 官方 API 前置）
// - 圖片縮圖（MatrixImageFile.resizeImplementation）與檔案加密
//   （MatrixFile.encrypt / MatrixFile.encryptFile）皆改於背景 isolate 執行，
//   避免主 isolate 因 CPU 密集作業卡住 UI（Android ANR）。
// - EXIF 摘除（人類批准 2026-11-06 方案 C）：JPEG 上傳／縮圖一律先走
//   官方 image 套件 decode→清空 EXIF→重編碼——SDK resizeImplementation
//   的 encode 會把 EXIF 寫回（含 GPS），故僅走 resize 不足保護；
//   詳見 _cleanJpegResize 檔註。App 端不寫任何演算法（decode/encode/
//   copyResize 皆官方 image 套件 API）。
// - 加密仍完全透過 SDK 官方函式：SDK `encryptFile` 內部做 AES-CTR + SHA-256；
//   App 端不寫任何演算法、金鑰或雜湊邏輯，只預先取得 SDK 回傳的 EncryptedFile 再注入。
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as iimg;
import 'package:matrix/matrix.dart';

import 'engine_init.dart';

/// 官方縮圖尺寸（Client.defaultThumbnailSize）。大於此尺寸才產生縮圖。
const int kRingMaxThumbnailDimension = 800;

/// 上傳前下採樣上限（人類批准 2026-11-06「圖片傳送慢」修復；同日批次
/// 「速度再加速」批准改 1280）：
/// * 相機／相簿原圖常為 12MP（數 MB），全尺寸直接上傳造成
///   ①上傳量大（Element X 快的主因之一）②matrix.org 429 限流失敗率上升。
/// * 1280 與 Element X 對齊（AndroidMediaPreProcessor.kt `IMAGE_SCALE_REF_SIZE = 1280`
/// ＋ JPEG quality 78——Homing 淨化路徑 _cleanJpegResize 亦為 78）：
///   同場景 bytes 約再降 40%+，速度直接受益；解析度上限同步降低（人類取捨決定）。
const int kRingMaxImageSendDimension = 1280;

/// EXIF 摘除（人類批准 2026-11-06 方案 C）：JPEG 的檔首簽名（FF D8）。
bool _isJpegBytes(Uint8List data) =>
    data.lengthInBytes >= 2 && data[0] == 0xFF && data[1] == 0xD8;

/// EXIF 淨化重編碼（僅 JPEG；isolate 內執行，純官方 image 套件 API）。
///
/// 背景查證定案（2026-11-06，SDK 原始碼直讀）：
/// * matrix 14.2.0 `MatrixImageFile.resizeImplementation`（matrix_file.dart
///   L230-255）＝ decodeImage→copyResize→encodeNamedImage；其輸出**仍含
///   EXIF**——image-4.3.0 的 JpegEncoder（jpeg_encoder.dart L59
///   `_writeAPP1(fp, image.exif)`）會把 decode 保留的 EXIF（含 GPS）寫回
///   輸出檔。故走官方 resize 不解決隱私洩漏。
/// * decode 時 image 套件已把 EXIF orientation 烤進像素
///   （jpeg/_jpeg_quantize_io.dart L209-266，直式照片不會側躺），
///   並自動清除 orientation tag——清空 exif 不影響顯示方向。
///
/// 行為：decode→清空 EXIF→copyResize（cap=min(長邊,maxDimension)，
/// **不放大**小圖）→ encodeJpg(quality 78)。decode/編碼失敗回 null
/// （呼叫端退回原檔——避免把「可用照片」變成「送不出」；此為隱私保護
/// 的能力限制 ⚠️標註，與 Element X 失敗即擲錯的取捨不同）。
ResizedImage? _cleanJpegResize(Uint8List data, int maxDimension) {
  try {
    final decoded = iimg.decodeImage(data);
    if (decoded == null) {
      return null;
    }
    decoded.exif = iimg.ExifData(); // 摘除 GPS／註解等全部 EXIF。
    final cap =
        math.min(math.max(decoded.width, decoded.height), maxDimension);
    final resized = iimg.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? cap : null,
      height: decoded.height > decoded.width ? cap : null,
    );
    final encoded = iimg.encodeJpg(resized, quality: 78);
    return ResizedImage(
      bytes: Uint8List.fromList(encoded),
      width: resized.width,
      height: resized.height,
      mimeType: 'image/jpeg',
    );
  } catch (_) {
    return null;
  }
}

/// 下採樣後的上傳資料（純資料，可在任何 isolate 傳遞）。
class ResizedImage {
  const ResizedImage({
    required this.bytes,
    required this.width,
    required this.height,
    this.mimeType,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final String? mimeType;
}

class ImagePreparation {
  const ImagePreparation({
    required this.width,
    required this.height,
    this.blurhash,
    this.thumbnailBytes,
    this.thumbnailWidth,
    this.thumbnailHeight,
    this.thumbnailBlurhash,
    this.thumbnailMimeType,
    this.upload,
  });

  final int width;
  final int height;
  final String? blurhash;

  /// 上傳用下採樣資料；null＝原檔小於 [kRingMaxImageSendDimension]，直接送原檔。
  final ResizedImage? upload;

  final Uint8List? thumbnailBytes;
  final int? thumbnailWidth;
  final int? thumbnailHeight;
  final String? thumbnailBlurhash;
  final String? thumbnailMimeType;

  MatrixImageFile? get thumbnail {
    final bytes = thumbnailBytes;
    if (bytes == null) {
      return null;
    }
    return MatrixImageFile(
      bytes: bytes,
      name: 'ring_thumb_${width}x$height',
      mimeType: thumbnailMimeType,
      width: thumbnailWidth,
      height: thumbnailHeight,
      blurhash: thumbnailBlurhash,
    );
  }
}

/// isolate 內（純資料）預處理結果：圖片 metadata＋上傳下採樣＋必要時縮圖。
class _ImageWorkResult {
  const _ImageWorkResult({
    required this.width,
    required this.height,
    this.blurhash,
    this.upload,
    this.thumb,
    this.thumbWidth,
    this.thumbHeight,
    this.thumbBlurhash,
    this.thumbMimeType,
  });

  final int width;
  final int height;
  final String? blurhash;
  final ResizedImage? upload;
  final Uint8List? thumb;
  final int? thumbWidth;
  final int? thumbHeight;
  final String? thumbBlurhash;
  final String? thumbMimeType;
}

/// 於背景 isolate 內做圖片 metadata／縮圖預處理，回傳主 isolate 可用的結果。
Future<ImagePreparation?> prepareImageInBackground({
  required Uint8List bytes,
  required String name,
}) async {
  final bytesTransfer = TransferableTypedData.fromList([bytes]);
  final work = await Isolate.run<_ImageWorkResult?>((() async {
    final buf = bytesTransfer.materialize();
    final data = buf.asUint8List();
    final meta = MatrixImageFile.calcMetadataImplementation(data);
    if (meta == null) {
      return null;
    }
    final width = meta.width;
    final height = meta.height;
    final isJpeg = _isJpegBytes(data);
    // 上傳用下採樣（慢傳修復）＋EXIF 摘除（隱私修復）。
    // JPEG：一律走淨化重編碼（decode 清 EXIF 再編碼；cap 不放大小圖）——
    // 起點是「GPS 座標會隨照片送出」，比檔案大小優先。
    // 非 JPEG：維持原行為（大於上限才縮，且縮出來更小才採用）。
    ResizedImage? upload;
    if (isJpeg) {
      upload = _cleanJpegResize(data, kRingMaxImageSendDimension);
    } else if (width > kRingMaxImageSendDimension ||
        height > kRingMaxImageSendDimension) {
      final resized = MatrixImageFile.resizeImplementation(
        MatrixImageFileResizeArguments(
          bytes: data,
          maxDimension: kRingMaxImageSendDimension,
          fileName: name,
          calcBlurhash: false,
        ),
      );
      if (resized != null && resized.bytes.lengthInBytes < data.lengthInBytes) {
        upload = ResizedImage(
          bytes: resized.bytes,
          width: resized.width,
          height: resized.height,
          mimeType: resized.mimeType,
        );
      }
    }
    final needsThumb = width > kRingMaxThumbnailDimension || height > kRingMaxThumbnailDimension;
    Uint8List? thumb;
    int? thumbWidth;
    int? thumbHeight;
    String? thumbBlurhash;
    String? thumbMimeType;
    if (needsThumb) {
      if (isJpeg) {
        // JPEG 縮圖同走淨化路徑（縮圖檔也是獨立上傳的媒體，不能留 GPS）；
        // blurhash 以官方 calcMetadataImplementation 在淨化後 bytes 上計算。
        final cleaned = _cleanJpegResize(data, kRingMaxThumbnailDimension);
        if (cleaned != null) {
          thumb = cleaned.bytes;
          thumbWidth = cleaned.width;
          thumbHeight = cleaned.height;
          thumbMimeType = 'image/jpeg';
          final thumbMeta = MatrixImageFile.calcMetadataImplementation(thumb);
          thumbBlurhash = thumbMeta?.blurhash;
        }
      } else {
        final resized = MatrixImageFile.resizeImplementation(
          MatrixImageFileResizeArguments(
            bytes: data,
            maxDimension: kRingMaxThumbnailDimension,
            fileName: name,
            calcBlurhash: true,
          ),
        );
        if (resized != null) {
          thumb = resized.bytes;
          thumbWidth = resized.width;
          thumbHeight = resized.height;
          thumbBlurhash = resized.blurhash;
          thumbMimeType = resized.mimeType;
        }
      }
    }
    return _ImageWorkResult(
      width: width,
      height: height,
      blurhash: meta.blurhash,
      upload: upload,
      thumb: thumb,
      thumbWidth: thumbWidth,
      thumbHeight: thumbHeight,
      thumbBlurhash: thumbBlurhash,
      thumbMimeType: thumbMimeType,
    );
  }));

  if (work == null) {
    return null;
  }
  return ImagePreparation(
    width: work.width,
    height: work.height,
    blurhash: work.blurhash,
    upload: work.upload,
    thumbnailBytes: work.thumb,
    thumbnailWidth: work.thumbWidth,
    thumbnailHeight: work.thumbHeight,
    thumbnailBlurhash: work.thumbBlurhash,
    thumbnailMimeType: work.thumbMimeType,
  );
}

/// 於背景 isolate 內執行 SDK 官方檔案加密（AES-CTR + SHA-256），
/// 回傳 SDK 官方 `EncryptedFile`（加密結果僅含純資料，App 端不介入演算法）。
///
/// ⚠️ **第五十一批（2026-11-16）修正：背景 isolate 內必須先初始化加密引擎。**
/// 根因（SDK 原始碼查證）：
/// * matrix SDK 14.2.0 `encryptFile` → `CryptoUtils.aesCtr`／`CryptoUtils.sha256`
///   （`lib/src/utils/crypto/encrypted_file.dart`）→ 這兩個方法**不在** SDK 的
///   純 Dart `crypto.dart`，而是 **vodozemac（rust）** 匯出的
///   `CryptoUtils`（vodozemac-0.9.1 `lib/src/api.dart` L631-652）。
/// * rust 狀態是 **isolate 區域**的：`flutter_rust_bridge` 2.13.0 的
///   `RustLib.instance` 未初始化時**拋** StateError
///   「flutter_rust_bridge has not been initialized. Did you forget to call
///   `await RustLib.init();`? …」。
/// * 因此在**未初始化引擎的背景 isolate** 內呼叫 SDK 官方 `encryptFile`
///   必然拋上述錯誤——人類 2026-11-16 實機回報的正是這則（圖片上傳
///   「已送出 0 個附件，1 個失敗（最後原因： Bad state: flutter_rust_bridge
///   has not been initialized…）」）。
/// * 官方 SDK 既有同一模式：`NativeImplementationsIsolate(compute,
///   vodozemacInit: …)` 在 isolate 內先 `await vodozemacInit?.call()`
///   （matrix-14.2.0 `lib/src/utils/native_implementations.dart` L198-281）
///   → 本函式沿用同一做法（`initRustEngineInIsolate()`）。
///
/// [initEngine]＝isolate 內的引擎初始化（預設官方
/// `initRustEngineInIsolate()`）；測試可注入假實作以驗證失敗路徑。
Future<EncryptedFile?> encryptFileInBackground(
  Uint8List bytes, {
  Future<bool> Function()? initEngine,
}) async {
  final bytesTransfer = TransferableTypedData.fromList([bytes]);
  final encrypted = await Isolate.run<EncryptedFile?>((() async {
    // 引擎必須在**本 isolate** 內初始化（rust 狀態不跨 isolate）。
    final ready = await (initEngine ?? initRustEngineInIsolate)();
    if (!ready) {
      throw StateError('加密引擎未就緒（背景 isolate 內 vodozemac 初始化失敗）');
    }
    final buf = bytesTransfer.materialize();
    final data = buf.asUint8List();
    return await encryptFile(data);
  }));
  if (encrypted == null) {
    throw StateError('SDK encryptFile 在背景 isolate 執行失敗');
  }
  return encrypted;
}

/// 預先加密（於背景執行）後注入給 `sendFileEvent` 使用的 SDK 檔案 subclass。
mixin PreEncryptedUpload on MatrixFile {
  EncryptedFile? get preEncrypted;

  @override
  Future<EncryptedFile> encrypt() {
    final pre = preEncrypted;
    if (pre != null) {
      return Future<EncryptedFile>.value(pre);
    }
    return super.encrypt();
  }
}

class UploadImageFile extends MatrixImageFile with PreEncryptedUpload {
  UploadImageFile({
    required super.bytes,
    required super.name,
    super.mimeType,
    int? width,
    int? height,
    String? blurhash,
    this.preEncrypted,
  });

  @override
  final EncryptedFile? preEncrypted;

  @override
  Future<MatrixImageFile?> generateThumbnail({
    int dimension = Client.defaultThumbnailSize,
    Future<MatrixImageFileResizedResponse?> Function(MatrixImageFileResizeArguments)? customImageResizer,
    NativeImplementations nativeImplementations = NativeImplementations.dummy,
  }) async {
    // 若沒有預先產生 thumbnail，跳過產生，避免主 isolate 再做一次重大的解碼／縮圖。
    return null;
  }
}

class UploadVideoFile extends MatrixVideoFile with PreEncryptedUpload {
  UploadVideoFile({
    required super.bytes,
    required super.name,
    super.mimeType,
    int? width,
    int? height,
    int? duration,
    this.preEncrypted,
  });

  @override
  final EncryptedFile? preEncrypted;
}

class UploadPlainFile extends MatrixFile with PreEncryptedUpload {
  UploadPlainFile({
    required super.bytes,
    required super.name,
    super.mimeType,
    this.preEncrypted,
  });

  @override
  final EncryptedFile? preEncrypted;
}

bool isImageFileName(String name) {
  final ext = name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
  const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'};
  return imageExts.contains(ext);
}

bool isVideoFileName(String name) {
  final ext = name.contains('.')
      ? name.split('.').last.toLowerCase()
      : '';
  const videoExts = {'mp4', 'mov', 'mkv', 'webm', '3gp', 'm4v', 'avi'};
  return videoExts.contains(ext);
}

/// 組裝送出用檔案（加密已預先在背景完成，注入 preEncrypted）。
/// `imageWidth/Height/MimeType`＝上傳資料下採樣後的尺寸／型別覆寫
/// （慢傳修復 2026-11-06）；null 時退回原始 metadata。
MatrixFile buildUploadFile({
  required Uint8List bytes,
  required String name,
  required bool isImage,
  required bool isVideo,
  ImagePreparation? image,
  int? imageWidth,
  int? imageHeight,
  String? imageMimeType,
  EncryptedFile? encrypted,
}) {
  if (isImage) {
    // m.image 需要 width／height／blurhash；預處理失敗則退回 plain（m.file）。
    return UploadImageFile(
      bytes: bytes,
      name: name,
      mimeType: imageMimeType,
      width: imageWidth ?? image?.width,
      height: imageHeight ?? image?.height,
      blurhash: image?.blurhash,
      preEncrypted: encrypted,
    );
  }
  if (isVideo) {
    return UploadVideoFile(
      bytes: bytes,
      name: name,
      preEncrypted: encrypted,
    );
  }
  return UploadPlainFile(
    bytes: bytes,
    name: name,
    preEncrypted: encrypted,
  );
}

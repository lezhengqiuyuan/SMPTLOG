/// 凭据保管与端到端加密。
///
/// 安全铁律：
/// - API Token 与同步密码**绝不写入 SQLite 数据库**（数据库会被同步/导出）。
/// - Windows 用 DPAPI（CryptProtectData，当前用户范围）加密后落盘。
/// - Android 用 Keystore 包裹（原生通道），密文落 noBackupFilesDir。
/// - 导出的任何备份文件都不含 token 与密码。
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:ffi/ffi.dart' as pffi;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// PBKDF2-HMAC-SHA256（手写实现，避免额外依赖）。
class Pbkdf2 {
  /// [iterations] 默认 12 万轮：桌面约 0.6 秒、手机约 1.5 秒，仅在上手时算一次。
  static Uint8List derive(
    String password,
    List<int> salt, {
    int iterations = 120000,
    int length = 32,
  }) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final blocks = (length / 32).ceil();
    final out = BytesBuilder();

    for (var block = 1; block <= blocks; block++) {
      final blockBytes = <int>[
        ...salt,
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ];
      var u = hmac.convert(blockBytes).bytes;
      final acc = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < acc.length; j++) {
          acc[j] ^= u[j];
        }
      }
      out.add(acc);
    }
    return Uint8List.fromList(out.toBytes().sublist(0, length));
  }
}

/// AES-256-GCM 加解密。
///
/// 格式：`SLG1` + 盐(16) + IV(12) + 密文（含 16 字节认证标签）。
class CipherBox {
  static const _magic = 'SLG1';

  /// 由密码派生密钥（带随机盐）。
  static ({Uint8List key, Uint8List salt}) deriveKey(String password) {
    final salt = _randomBytes(16);
    final key = Pbkdf2.derive(password, salt);
    return (key: key, salt: salt);
  }

  /// 用已派生的密钥加密。
  static Uint8List encryptWithKey(Uint8List key, Uint8List salt, List<int> data) {
    final iv = enc.IV(_randomBytes(12));
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(key), mode: enc.AESMode.gcm),
    );
    final encrypted = encrypter.encryptBytes(data, iv: iv);
    return Uint8List.fromList([
      ...utf8.encode(_magic),
      ...salt,
      ...iv.bytes,
      ...encrypted.bytes,
    ]);
  }

  /// 用密码解密（内部重新派生密钥）。
  static Uint8List decryptWithPassword(String password, Uint8List blob) {
    if (blob.length < 4 + 16 + 12 + 16) {
      throw const FormatException('密文长度异常');
    }
    final magic = utf8.decode(blob.sublist(0, 4));
    if (magic != _magic) throw const FormatException('密文标识不匹配');
    final salt = blob.sublist(4, 20);
    final iv = blob.sublist(20, 32);
    final body = blob.sublist(32);
    final key = Pbkdf2.derive(password, salt);
    return decryptWithKey(key, iv, body);
  }

  static Uint8List decryptWithKey(
    Uint8List key,
    List<int> iv,
    List<int> body,
  ) {
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(key), mode: enc.AESMode.gcm),
    );
    final plain = encrypter.decryptBytes(
      enc.Encrypted(Uint8List.fromList(body)),
      iv: enc.IV(Uint8List.fromList(iv)),
    );
    return Uint8List.fromList(plain);
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }
}

// ---------------------------------------------------------------- DPAPI

final class _DataBlob extends ffi.Struct {
  @ffi.Uint32()
  external int cbData;

  external ffi.Pointer<ffi.Uint8> pbData;
}

typedef _CryptProtectDataNative = ffi.Int32 Function(
  ffi.Pointer<_DataBlob> pDataIn,
  ffi.Pointer<ffi.Uint16> szDataDescr,
  ffi.Pointer<_DataBlob> pOptionalEntropy,
  ffi.Pointer<ffi.Void> pvReserved,
  ffi.Pointer<ffi.Void> pPromptStruct,
  ffi.Uint32 dwFlags,
  ffi.Pointer<_DataBlob> pDataOut,
);

typedef _CryptUnprotectDataNative = ffi.Int32 Function(
  ffi.Pointer<_DataBlob> pDataIn,
  ffi.Pointer<ffi.Pointer<ffi.Uint16>> ppszDataDescr,
  ffi.Pointer<_DataBlob> pOptionalEntropy,
  ffi.Pointer<ffi.Void> pvReserved,
  ffi.Pointer<ffi.Void> pPromptStruct,
  ffi.Uint32 dwFlags,
  ffi.Pointer<_DataBlob> pDataOut,
);

typedef _CryptProtectDataDart = int Function(
  ffi.Pointer<_DataBlob> pDataIn,
  ffi.Pointer<ffi.Uint16> szDataDescr,
  ffi.Pointer<_DataBlob> pOptionalEntropy,
  ffi.Pointer<ffi.Void> pvReserved,
  ffi.Pointer<ffi.Void> pPromptStruct,
  int dwFlags,
  ffi.Pointer<_DataBlob> pDataOut,
);

typedef _CryptUnprotectDataDart = int Function(
  ffi.Pointer<_DataBlob> pDataIn,
  ffi.Pointer<ffi.Pointer<ffi.Uint16>> ppszDataDescr,
  ffi.Pointer<_DataBlob> pOptionalEntropy,
  ffi.Pointer<ffi.Void> pvReserved,
  ffi.Pointer<ffi.Void> pPromptStruct,
  int dwFlags,
  ffi.Pointer<_DataBlob> pDataOut,
);

typedef _LocalFreeNative = ffi.Pointer<ffi.Void> Function(
  ffi.Pointer<ffi.Void> hMem,
);

/// Windows DPAPI 封装（当前用户范围）。
class _Dpapi {
  _Dpapi()
      : _crypt32 = ffi.DynamicLibrary.open('crypt32.dll'),
        _kernel32 = ffi.DynamicLibrary.open('kernel32.dll');

  final ffi.DynamicLibrary _crypt32;
  final ffi.DynamicLibrary _kernel32;

  static const int _uiForbidden = 0x1;

  Uint8List protect(Uint8List data) {
    final protectFn =
        _crypt32.lookupFunction<_CryptProtectDataNative, _CryptProtectDataDart>(
      'CryptProtectData',
    );
    final freeFn =
        _kernel32.lookupFunction<_LocalFreeNative, _LocalFreeNative>('LocalFree');

    final inPtr = pffi.malloc<ffi.Uint8>(data.length);
    inPtr.asTypedList(data.length).setAll(0, data);

    final blobIn = pffi.malloc<_DataBlob>();
    blobIn.ref.cbData = data.length;
    blobIn.ref.pbData = inPtr;

    final blobOut = pffi.malloc<_DataBlob>();
    final ok = protectFn(
      blobIn,
      ffi.nullptr,
      ffi.nullptr,
      ffi.nullptr,
      ffi.nullptr,
      _uiForbidden,
      blobOut,
    );

    if (ok == 0) {
      pffi.malloc.free(inPtr);
      pffi.malloc.free(blobIn);
      pffi.malloc.free(blobOut);
      throw StateError('DPAPI 加密失败');
    }

    final len = blobOut.ref.cbData;
    final out = Uint8List.fromList(
      blobOut.ref.pbData.asTypedList(len),
    );
    freeFn(blobOut.ref.pbData.cast<ffi.Void>());
    pffi.malloc.free(inPtr);
    pffi.malloc.free(blobIn);
    pffi.malloc.free(blobOut);
    return out;
  }

  Uint8List unprotect(Uint8List data) {
    final unprotectFn = _crypt32
        .lookupFunction<_CryptUnprotectDataNative, _CryptUnprotectDataDart>(
      'CryptUnprotectData',
    );
    final freeFn =
        _kernel32.lookupFunction<_LocalFreeNative, _LocalFreeNative>('LocalFree');

    final inPtr = pffi.malloc<ffi.Uint8>(data.length);
    inPtr.asTypedList(data.length).setAll(0, data);

    final blobIn = pffi.malloc<_DataBlob>();
    blobIn.ref.cbData = data.length;
    blobIn.ref.pbData = inPtr;

    final blobOut = pffi.malloc<_DataBlob>();
    final ok = unprotectFn(
      blobIn,
      ffi.nullptr,
      ffi.nullptr,
      ffi.nullptr,
      ffi.nullptr,
      _uiForbidden,
      blobOut,
    );

    if (ok == 0) {
      pffi.malloc.free(inPtr);
      pffi.malloc.free(blobIn);
      pffi.malloc.free(blobOut);
      throw StateError('DPAPI 解密失败（可能换了 Windows 账户或机器）');
    }

    final len = blobOut.ref.cbData;
    final out = Uint8List.fromList(blobOut.ref.pbData.asTypedList(len));
    freeFn(blobOut.ref.pbData.cast<ffi.Void>());
    pffi.malloc.free(inPtr);
    pffi.malloc.free(blobIn);
    pffi.malloc.free(blobOut);
    return out;
  }
}

/// 凭据保管器。
///
/// 存的是一个小 JSON：`{projectId, apiToken, deviceId, syncHash, syncSalt, syncKey}`。
class SecretsVault {
  SecretsVault._();

  static const _channel = MethodChannel('smptlog/vault');

  static Directory? _configDir;
  static _Dpapi? _dpapi;

  static Future<Directory> _dir() async {
    final cached = _configDir;
    if (cached != null) return cached;

    Directory dir;
    if (Platform.isWindows) {
      final base = Platform.environment['LOCALAPPDATA'] ??
          (await getApplicationSupportDirectory()).path;
      dir = Directory('$base\\SMPTLOG\\config');
    } else {
      final base = await getApplicationSupportDirectory();
      dir = Directory('${base.path}/config');
    }
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _configDir = dir;
    return dir;
  }

  static Future<File> _file() async {
    final d = await _dir();
    return File('${d.path}${Platform.pathSeparator}secrets.bin');
  }

  /// 读取全部凭据；不存在或无法解密返回空表。
  static Future<Map<String, dynamic>> read() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return <String, dynamic>{};

      if (Platform.isWindows) {
        _dpapi ??= _Dpapi();
        final raw = _dpapi!.unprotect(f.readAsBytesSync());
        return jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      }

      if (Platform.isAndroid) {
        final b64 = f.readAsStringSync();
        final plain = await _channel.invokeMethod<String>('decrypt', {'data': b64});
        if (plain == null || plain.isEmpty) return <String, dynamic>{};
        return jsonDecode(plain) as Map<String, dynamic>;
      }

      // 其他平台（理论上不出现）退化为明文，仅用于开发调试。
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// 写入全部凭据（覆盖）。
  static Future<void> write(Map<String, dynamic> data) async {
    final f = await _file();
    final plain = jsonEncode(data);

    if (Platform.isWindows) {
      _dpapi ??= _Dpapi();
      final cipher = _dpapi!.protect(Uint8List.fromList(utf8.encode(plain)));
      f.writeAsBytesSync(cipher, flush: true);
      return;
    }

    if (Platform.isAndroid) {
      final b64 = await _channel.invokeMethod<String>('encrypt', {'data': plain});
      f.writeAsStringSync(b64 ?? '', flush: true);
      return;
    }

    f.writeAsStringSync(plain, flush: true);
  }

  static Future<void> clear() async {
    final f = await _file();
    if (f.existsSync()) f.deleteSync();
  }

  /// 读取单个键。
  static Future<String> get(String key) async {
    final m = await read();
    return (m[key] ?? '').toString();
  }

  /// 写入单个键。
  static Future<void> set(String key, String value) async {
    final m = await read();
    m[key] = value;
    await write(m);
  }
}

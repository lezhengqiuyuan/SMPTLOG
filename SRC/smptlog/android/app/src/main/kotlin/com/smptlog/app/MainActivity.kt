package com.smptlog.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android 侧凭据保管：用 Android Keystore 里的 AES-256-GCM 密钥加密，
 * 密文（Base64）由 Dart 侧写入 config/secrets.bin。
 *
 * 安全要点：密钥永不离开 Keystore，导出文件与数据库都不含 token。
 */
class MainActivity : FlutterActivity() {

    private val vaultChannel = "smptlog/vault"
    private val keyAlias = "smptlog_vault_key"
    private val gcmTagBits = 128
    private val ivLength = 12

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, vaultChannel)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "encrypt" -> {
                            val data = call.argument<String>("data") ?: ""
                            result.success(encrypt(data))
                        }
                        "decrypt" -> {
                            val data = call.argument<String>("data") ?: ""
                            if (data.isEmpty()) {
                                result.success("")
                            } else {
                                result.success(decrypt(data))
                            }
                        }
                        "openUrl" -> {
                            val url = call.argument<String>("url") ?: ""
                            if (url.isEmpty()) {
                                result.error("BAD_URL", "url is empty", null)
                            } else {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("VAULT_ERROR", e.message ?: "keystore error", null)
                }
            }
    }

    private fun secretKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore")
        ks.load(null)
        val existing = ks.getEntry(keyAlias, null)
        if (existing is KeyStore.SecretKeyEntry) {
            return existing.secretKey
        }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore"
        )
        val builder = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setUnlockedDeviceRequired(false)
        }
        generator.init(builder.build())
        return generator.generateKey()
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val iv = cipher.iv
        val body = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        val combined = ByteArray(iv.size + body.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(body, 0, combined, iv.size, body.size)
        return Base64.encodeToString(combined, Base64.NO_WRAP)
    }

    private fun decrypt(payload: String): String {
        val combined = Base64.decode(payload, Base64.NO_WRAP)
        if (combined.size <= ivLength) {
            throw IllegalStateException("密文长度异常")
        }
        val iv = combined.copyOfRange(0, ivLength)
        val body = combined.copyOfRange(ivLength, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            secretKey(),
            GCMParameterSpec(gcmTagBits, iv)
        )
        return String(cipher.doFinal(body), Charsets.UTF_8)
    }
}

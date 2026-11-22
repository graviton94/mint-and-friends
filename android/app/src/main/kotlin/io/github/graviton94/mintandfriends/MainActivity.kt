package io.github.graviton94.mintandfriends

import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Play 설치 추천인 (초대 링크의 친구 코드, D-045): 첫 실행 때 한 번 읽는다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mint/referrer")
            .setMethodCallHandler { call, result ->
                if (call.method != "get") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                var answered = false
                fun reply(v: String?) {
                    if (answered) return
                    answered = true
                    result.success(v)
                }
                val client = InstallReferrerClient.newBuilder(this).build()
                try {
                    client.startConnection(object : InstallReferrerStateListener {
                        override fun onInstallReferrerSetupFinished(code: Int) {
                            val v = if (code == InstallReferrerClient.InstallReferrerResponse.OK) {
                                try { client.installReferrer.installReferrer } catch (e: Exception) { null }
                            } else null
                            try { client.endConnection() } catch (_: Exception) {}
                            reply(v)
                        }

                        override fun onInstallReferrerServiceDisconnected() {
                            reply(null)
                        }
                    })
                } catch (e: Exception) {
                    reply(null)
                }
            }
    }
}

package io.github.graviton94.mintandfriends

import com.android.installreferrer.api.InstallReferrerClient
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.plugin.common.EventChannel
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val updateRequest = 7301
    private var updates: AppUpdateManager? = null
    private var updateSink: EventChannel.EventSink? = null
    private val installListener = InstallStateUpdatedListener { st ->
        updateSink?.success(
            mapOf(
                "status" to st.installStatus(),
                "bytes" to st.bytesDownloaded(),
                "total" to st.totalBytesToDownload(),
            ),
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureUpdates(flutterEngine)
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

    // ---- Play 인앱 업데이트 (D-049)
    private fun configureUpdates(engine: FlutterEngine) {
        val m = AppUpdateManagerFactory.create(this)
        updates = m
        EventChannel(engine.dartExecutor.binaryMessenger, "mint/update/progress")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    updateSink = sink
                    m.registerListener(installListener)
                }

                override fun onCancel(args: Any?) {
                    m.unregisterListener(installListener)
                    updateSink = null
                }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, "mint/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "check" -> m.appUpdateInfo
                        .addOnSuccessListener { info ->
                            result.success(
                                mapOf(
                                    "available" to (info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE),
                                    "inProgress" to (info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS),
                                    "versionCode" to info.availableVersionCode(),
                                    "flexible" to info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
                                    "immediate" to info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
                                    "status" to info.installStatus(),
                                    "staleDays" to (info.clientVersionStalenessDays() ?: -1),
                                    "priority" to info.updatePriority(),
                                ),
                            )
                        }
                        .addOnFailureListener { e -> result.error("check", e.message, null) }
                    "start" -> {
                        val immediate = call.argument<Boolean>("immediate") ?: false
                        val type = if (immediate) AppUpdateType.IMMEDIATE else AppUpdateType.FLEXIBLE
                        m.appUpdateInfo
                            .addOnSuccessListener { info ->
                                try {
                                    val ok = m.startUpdateFlowForResult(
                                        info,
                                        this,
                                        AppUpdateOptions.newBuilder(type).build(),
                                        updateRequest,
                                    )
                                    result.success(ok)
                                } catch (e: Exception) {
                                    result.error("start", e.message, null)
                                }
                            }
                            .addOnFailureListener { e -> result.error("start", e.message, null) }
                    }
                    "complete" -> {
                        m.completeUpdate()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == updateRequest) {
            // 사용자가 업데이트 창을 닫았으면 알려 준다 (RESULT_OK 가 아니면 취소)
            updateSink?.success(mapOf("status" to if (resultCode == RESULT_OK) -1 else -2, "bytes" to 0L, "total" to 0L))
        }
    }

    override fun onResume() {
        super.onResume()
        // 필수(전체 화면) 업데이트가 진행 중이었다면 이어서 보여 준다 · 다 받은 업데이트는 알려 준다
        updates?.appUpdateInfo?.addOnSuccessListener { info ->
            if (info.updateAvailability() == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS &&
                info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE) &&
                info.installStatus() != InstallStatus.DOWNLOADED
            ) {
                try {
                    updates?.startUpdateFlowForResult(
                        info,
                        this,
                        AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build(),
                        updateRequest,
                    )
                } catch (_: Exception) {}
            }
            if (info.installStatus() == InstallStatus.DOWNLOADED) {
                updateSink?.success(mapOf("status" to InstallStatus.DOWNLOADED, "bytes" to 0L, "total" to 0L))
            }
        }
    }
}

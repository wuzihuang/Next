package com.nextbody.hoop.band

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.inuker.bluetooth.library.Code
import com.inuker.bluetooth.library.Constants
import com.inuker.bluetooth.library.connect.response.BleNotifyResponse
import com.inuker.bluetooth.library.connect.response.BleReadRssiResponse
import com.inuker.bluetooth.library.connect.response.BleWriteResponse
import com.inuker.bluetooth.library.jieli.dial.JLWatchFaceManager
import com.inuker.bluetooth.library.jieli.ota.JLOTAHolder
import com.inuker.bluetooth.library.jieli.response.RcspAuthResponse
import com.inuker.bluetooth.library.model.BleGattProfile
import com.inuker.bluetooth.library.search.SearchResult
import com.inuker.bluetooth.library.search.response.SearchResponse
import com.nextbody.hoop.app.NextBodyApplication
import com.nextbody.hoop.services.ConsentStore
import com.nextbody.hoop.services.SupabaseClient
import com.veepoo.protocol.VPOperateManager
import com.veepoo.protocol.listener.IMiniCheckupOptListener
import com.veepoo.protocol.listener.base.IABleConnectStatusListener
import com.veepoo.protocol.listener.base.IBleWriteResponse
import com.veepoo.protocol.listener.base.IConnectResponse
import com.veepoo.protocol.listener.base.INotifyResponse
import com.veepoo.protocol.listener.data.IAlarm2DataListListener
import com.veepoo.protocol.listener.data.IAllSetDataListener
import com.veepoo.protocol.listener.data.IAutoMeasureSettingDataListener
import com.veepoo.protocol.listener.data.IBatteryDataListener
import com.veepoo.protocol.listener.data.IBodyComponentDetectListener
import com.veepoo.protocol.listener.data.ICustomSettingDataListener
import com.veepoo.protocol.listener.data.IDeviceFuctionDataListener
import com.veepoo.protocol.listener.data.IDeviceManualDetectDataListener
import com.veepoo.protocol.listener.data.IDeviceSportReportListener
import com.veepoo.protocol.listener.data.IECGDetectListener
import com.veepoo.protocol.listener.data.IFindDevicelistener
import com.veepoo.protocol.listener.data.IFunSwitchListener
import com.veepoo.protocol.listener.data.IHRVOriginDataListener
import com.veepoo.protocol.listener.data.IHealthLightListener
import com.veepoo.protocol.listener.data.IHeartDataListener
import com.veepoo.protocol.listener.data.IHeartWaringDataListener
import com.veepoo.protocol.listener.data.IHrvDetectListener
import com.veepoo.protocol.listener.data.IOriginData3Listener
import com.veepoo.protocol.listener.data.IOriginDataListener
import com.veepoo.protocol.listener.data.IPersonInfoDataListener
import com.veepoo.protocol.listener.data.IPressureDetectListener
import com.veepoo.protocol.listener.data.IPwdDataListener
import com.veepoo.protocol.listener.data.ISleepDataListener
import com.veepoo.protocol.listener.data.ISocialMsgDataListener
import com.veepoo.protocol.listener.data.ISpo2hOriginDataListener
import com.veepoo.protocol.listener.data.ISportControlOptListener
import com.veepoo.protocol.listener.data.ISportModelStateListener
import com.veepoo.protocol.listener.data.ITemptureDataListener
import com.veepoo.protocol.listener.data.ITextAlarmDataListener
import com.veepoo.protocol.listener.data.IMtuChangeListener
import com.veepoo.protocol.listener.oad.OnGetOadVersionListener
import com.veepoo.protocol.model.OadFileBean
import com.veepoo.protocol.model.datas.AlarmData2
import com.veepoo.protocol.model.datas.AllSetData
import com.veepoo.protocol.model.datas.AutoMeasureData
import com.veepoo.protocol.model.datas.BatteryData
import com.veepoo.protocol.model.datas.BloodComponentManualData
import com.veepoo.protocol.model.datas.BloodGlucoseManualData
import com.veepoo.protocol.model.datas.BloodOxygenManualData
import com.veepoo.protocol.model.datas.BloodPressureManualData
import com.veepoo.protocol.model.datas.BodyComponent
import com.veepoo.protocol.model.datas.BodyTemperatureManualData
import com.veepoo.protocol.model.datas.DeviceFunctionPackage1
import com.veepoo.protocol.model.datas.DeviceFunctionPackage2
import com.veepoo.protocol.model.datas.DeviceFunctionPackage3
import com.veepoo.protocol.model.datas.DeviceFunctionPackage4
import com.veepoo.protocol.model.datas.DeviceFunctionPackage5
import com.veepoo.protocol.model.datas.EcgDetectInfo
import com.veepoo.protocol.model.datas.EcgDetectResult
import com.veepoo.protocol.model.datas.EcgDetectState
import com.veepoo.protocol.model.datas.EcgDiagnosis
import com.veepoo.protocol.model.datas.EmotionManualData
import com.veepoo.protocol.model.datas.FatigueManualData
import com.veepoo.protocol.model.datas.FunctionDeviceSupportData
import com.veepoo.protocol.model.datas.FunctionSocailMsgData
import com.veepoo.protocol.model.datas.HRVOriginData
import com.veepoo.protocol.model.datas.HeartData
import com.veepoo.protocol.model.datas.HeartRateManualData
import com.veepoo.protocol.model.datas.HeartWaringData
import com.veepoo.protocol.model.datas.HrvManualData
import com.veepoo.protocol.model.datas.MetoManualData
import com.veepoo.protocol.model.datas.MiniCheckupDetailData
import com.veepoo.protocol.model.datas.MiniCheckupManualData
import com.veepoo.protocol.model.datas.MiniCheckupResultData
import com.veepoo.protocol.model.datas.OriginData
import com.veepoo.protocol.model.datas.OriginData3
import com.veepoo.protocol.model.datas.OriginHalfHourData
import com.veepoo.protocol.model.datas.PersonInfoData
import com.veepoo.protocol.model.datas.PressureManualData
import com.veepoo.protocol.model.datas.PwdData
import com.veepoo.protocol.model.datas.SkinConductanceManualData
import com.veepoo.protocol.model.datas.SleepData
import com.veepoo.protocol.model.datas.SleepPrecisionData
import com.veepoo.protocol.model.datas.Spo2hOriginData
import com.veepoo.protocol.model.datas.SportControlDataInfo
import com.veepoo.protocol.model.datas.SportModelStateData
import com.veepoo.protocol.model.datas.TemptureData
import com.veepoo.protocol.model.datas.TextAlarmData
import com.veepoo.protocol.model.datas.TimeData
import com.veepoo.protocol.model.enums.DetectState
import com.veepoo.protocol.model.enums.DeviceManualDataType
import com.veepoo.protocol.model.enums.EAllSetType
import com.veepoo.protocol.model.enums.ECheckWear
import com.veepoo.protocol.model.enums.EFunctionStatus
import com.veepoo.protocol.model.enums.EHealthLightStatus
import com.veepoo.protocol.model.enums.EHeartStatus
import com.veepoo.protocol.model.enums.EHeartWaringStatus
import com.veepoo.protocol.model.enums.EMiniCheckupTestErrorCode
import com.veepoo.protocol.model.enums.EMultiAlarmOprate
import com.veepoo.protocol.model.enums.EOprateStauts
import com.veepoo.protocol.model.enums.EPwdStatus
import com.veepoo.protocol.model.enums.ESex
import com.veepoo.protocol.model.enums.ESportControlType
import com.veepoo.protocol.model.enums.ESportModelStateStauts
import com.veepoo.protocol.model.enums.ESportType
import com.veepoo.protocol.model.enums.HrvDetectState
import com.veepoo.protocol.model.enums.PressureDetectState
import com.veepoo.protocol.model.settings.Alarm2Setting
import com.veepoo.protocol.model.settings.AllSetSetting
import com.veepoo.protocol.model.settings.CustomSetting
import com.veepoo.protocol.model.settings.CustomSettingData
import com.veepoo.protocol.model.settings.HeartWaringSetting
import com.veepoo.protocol.model.settings.OadSetting
import com.veepoo.protocol.model.settings.ReadOriginSetting
import com.veepoo.protocol.model.settings.TextAlarm2Setting
import com.veepoo.protocol.nordic.OnMcuMgrOtaListener
import com.veepoo.protocol.shareprence.VpSpGetUtil
import com.veepoo.protocol.zk.IZkOtaUpgradeListener
import io.runtime.mcumgr.dfu.FirmwareUpgradeController
import io.runtime.mcumgr.dfu.mcuboot.FirmwareUpgradeManager
import io.runtime.mcumgr.exception.McuMgrException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The real band, against Veepoo's Android SDK (`vpprotocol` + `vpbluetooth`, `VPOperateManager`).
 * A 1:1 port of iOS `VeepooBand.swift`; the iOS SDK's `VPBleCentralManage` / `VPPeripheralManage`
 * map onto the single `VPOperateManager`.
 *
 * ⚠️ One architectural difference: the iOS SDK persists every history day into its own database
 * (`VPDataBaseOperation`) and is queried by date afterwards. The Android SDK has no such store —
 * it hands each record to a callback while the dump runs. [HistoryStore] is that database for
 * this process: the dump fills it, and every per-day read is a lookup, exactly as on iOS.
 *
 * Every SDK entry point is called on the main thread (the SDK keeps its own timers there) and
 * answers exactly once, or throws after its deadline — see [sdk].
 */
@SuppressLint("MissingPermission")
class VeepooBand(private val context: Context? = runCatching { NextBodyApplication.context }.getOrNull()) : BandService {
    override var state: BandConnectionState = BandConnectionState.idle
        private set(value) {
            val changed = field != value
            field = value
            if (changed) {
                historyReads.invalidate()
                BandTrace.record("band.connection", mapOf("state" to value.name))
                hub.send(BandEvent.State(value))
            }
        }
    private val hub = BandEventHub()
    override val events: Flow<BandEvent> get() = hub.stream()
    private val queue = HoopQueue()
    private val historyReads = BandHistoryReadCache()
    private val history = HistoryStore()
    private val main = Handler(Looper.getMainLooper())
    private val work = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val vp: VPOperateManager get() = VPOperateManager.getInstance()
    private val sp: VpSpGetUtil? get() = context?.let { runCatching { VpSpGetUtil.getVpSpVariInstance(it) }.getOrNull() }

    /** Heart-rate tests share one SDK listener; a late stop from the previous stream must not
     *  clear the test a newer stream just started. */
    @Volatile private var heartTestGeneration = 0
    /** Find-the-wrist callbacks keep firing after start; a newer start/stop ignores the old ones. */
    @Volatile private var findGeneration = 0
    /** Stale connected-RSSI replies must not overwrite a frozen LAST reading. */
    @Volatile private var rssiEpoch = 0

    /** What the last scan reported, by BLE address. */
    private val scanned = ConcurrentHashMap<String, SearchResult>()
    @Volatile private var address: String? = null
    @Volatile private var pwdData: PwdData? = null
    @Volatile private var functions: FunctionDeviceSupportData? = null
    @Volatile private var customSetting: CustomSettingData? = null
    @Volatile private var reconnectJob: Job? = null
    @Volatile private var connectStatusListener: IABleConnectStatusListener? = null

    /** F2 §05 · what we last pushed down. The band's BIA multiplies by this. */
    @Volatile private var pushedWeightKg: Double? = null
    @Volatile private var pushedAt: Instant? = null

    /** The sport the band is running, for the control protocol's reads and stop. */
    @Volatile private var runningSport: ESportType = ESportType.NONE
    private val sportSubscription = BandSportSubscription()
    private val sportReaders = ConcurrentHashMap<UUID, (SportLiveInfo) -> Unit>()
    private val sportClosers = ConcurrentHashMap<UUID, () -> Unit>()
    @Volatile private var sportPoll: Job? = null
    @Volatile private var sportLastReceipt: Instant = BandTime.distantPast

    /** The offer the update server last made, kept for `updateFirmware`. */
    @Volatile private var lastOffer: OadFileBean? = null

    private val writeResponse = IBleWriteResponse { code ->
        if (code != Code.REQUEST_SUCCESS) BandTrace.error("command write failed · ${Code.toString(code)}")
    }
    private val bleWriteResponse = BleWriteResponse { code ->
        if (code != Code.REQUEST_SUCCESS) BandTrace.error("command write failed · ${Code.toString(code)}")
    }

    init {
        context?.let { ctx ->
            runCatching {
                vp.init(ctx.applicationContext)
                // The app owns reconnection; the SDK's own BT auto-connect stays off.
                vp.setAutoConnectBTBySdk(false)
                // A reconnect and an app pairing connect straight away, as the iOS SDK does.
                vp.setDeviceShowConfirm(false)
                // The band reports its own light changes. Nothing acts on them — this is the trace
                // that tells whether the firmware flips the side light by itself (ADR 0023).
                vp.addHealthLightListener(healthLightListener)
            }.onFailure { BandTrace.error("sdk init: ${it.localizedDescription}") }
        }
    }

    private val isConnected: Boolean get() = state == BandConnectionState.connected && address != null

    private fun hasPermission(permission: String): Boolean {
        val ctx = context ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ctx.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block)
    }

    // MARK: the one command shape

    /**
     * Every peripheral command goes to the SDK on the main thread and answers exactly once, or
     * throws after `seconds`. A command the band never answers is a STOPPED edge on screen,
     * never a bar frozen at 100 %. With a progress deadline the watchdog follows the band's own
     * progress, and on expiry ends the link — the SDK has no history cancel.
     */
    private suspend fun <T> sdk(
        name: String, seconds: Double = 12.0, progressDeadline: BandSyncDeadline? = null,
        body: (done: (Result<T>) -> Unit) -> Unit,
    ): T {
        val once = AtomicBoolean(false)
        val commandID = UUID.randomUUID().toString()
        val started = Instant.now()
        BandTrace.record("sdk.command_start", mapOf("command" to name, "commandID" to commandID))
        BandTrace.notice("$name →")
        fun end(outcome: String) = BandTrace.record("sdk.command_end", mapOf(
            "command" to name, "commandID" to commandID, "outcome" to outcome,
            "durationSeconds" to BandTime.interval(Instant.now(), started).toString()))
        return suspendCancellableCoroutine { c ->
            val watchdog = work.launch {
                if (progressDeadline != null) {
                    while (!progressDeadline.expired()) delay(1_000)
                } else {
                    delay((seconds * 1000).toLong())
                }
                if (!once.compareAndSet(false, true)) return@launch
                if (progressDeadline != null) {
                    onMain { runCatching { vp.disconnectWatch(writeResponse) } }
                    state = BandConnectionState.disconnected
                }
                BandTrace.error("$name: command deadline exceeded")
                end("timeout")
                if (c.isActive) c.resumeWithException(BandError.Timeout(name))
            }
            c.invokeOnCancellation { watchdog.cancel(); once.set(true) }
            onMain {
                try {
                    body { result ->
                        if (!once.compareAndSet(false, true)) return@body
                        watchdog.cancel()
                        result.onSuccess { BandTrace.notice("$name ← ok") }
                            .onFailure { BandTrace.error("$name ← ${it.localizedDescription}") }
                        end(if (result.isSuccess) "success" else diagnosticError(result.exceptionOrNull()))
                        if (c.isActive) c.resumeWith(result)
                    }
                } catch (e: Throwable) {
                    if (once.compareAndSet(false, true)) {
                        watchdog.cancel()
                        end(diagnosticError(e))
                        if (c.isActive) c.resumeWithException(e)
                    }
                }
            }
        }
    }

    private fun diagnosticError(error: Throwable?): String = when (error) {
        is BandError.NotConnected -> "not_connected"
        is BandError.Unsupported -> "unsupported"
        is BandError.Busy -> "busy"
        is BandError.Timeout -> "timeout"
        is BandError.Rejected -> "rejected"
        is CancellationException -> "cancelled"
        else -> "other_failure"
    }

    // MARK: connection

    override suspend fun startScan() = startScan(auto = false)

    /** `auto` mirrors the iOS SDK's automaticConnection; the app never lets the SDK connect on
     *  its own (the pairing chain then ran twice and the band answered nothing after). */
    @Suppress("UNUSED_PARAMETER")
    private suspend fun startScan(auto: Boolean) {
        // Discovery can run while the survivor is connected. Do not turn that verified
        // link into .idle at stopScan (or invalidate a history read still draining).
        if (state != BandConnectionState.connected) state = BandConnectionState.scanning
        scanned.clear()
        // Up to 5 s for the radio to report on; 02 edge 2 covers the radio being off.
        val adapter = BluetoothAdapter.getDefaultAdapter()
        for (i in 0 until 50) {
            if (!currentCoroutineContext().isActive) return
            if (adapter?.isEnabled == true) break
            delay(100)
        }
        if (adapter?.isEnabled != true || !hasPermission("android.permission.BLUETOOTH_SCAN")) {
            BandTrace.error("scan: radio off, missing permission or no BLE (adapter ${adapter != null})")
            return
        }
        BandTrace.notice("scan start")
        onMain {
            runCatching {
                vp.startScanDevice(object : SearchResponse {
                    override fun onSearchStarted() {}
                    override fun onDeviceFounded(result: SearchResult?) {
                        val found = result ?: return
                        val id = found.address ?: return
                        val name = found.name?.takeIf { it.isNotBlank() } ?: "NEXTBODY"
                        val matches = BandSyncPolicy.matchesBoundDevice(discovered = id, sdkAddress = id,
                            bound = BoundBand.identifier, boundPeripheral = BoundBand.peripheralIdentifier)
                        BandTrace.notice("scan found device · rssi ${found.rssi} · boundMatch $matches")
                        scanned[id] = found
                        hub.send(BandEvent.Discovered(DiscoveredBand(id = id, name = name, rssi = found.rssi, batteryPercent = null)))
                    }
                    override fun onSearchStopped() {}
                    override fun onSearchCanceled() {}
                })
            }.onFailure { BandTrace.error("scan: ${it.localizedDescription}") }
        }
    }

    override suspend fun stopScan() {
        BandTrace.notice("scan stop")
        onMain { runCatching { vp.stopScanDevice() } }
        if (state == BandConnectionState.scanning) state = BandConnectionState.idle
    }

    override suspend fun connect(device: DiscoveredBand, progress: (Double) -> Unit) {
        // The SDK may already hold a verified link to this very band. Pairing it a second time
        // is what left the band silent to every command after — a verified link is kept.
        if (state == BandConnectionState.connected && address == device.id) {
            BandTrace.notice("connect: already verified")
            BoundBand.remember(peripheralIdentifier = device.id)
            progress(1.0)
            return
        }
        if (!scanned.containsKey(device.id) && !BluetoothAdapter.checkBluetoothAddress(device.id)) {
            state = BandConnectionState.disconnected
            BandTrace.error("connect: requested device was not in the last scan")
            throw BandError.NotConnected
        }
        if (!hasPermission("android.permission.BLUETOOTH_CONNECT")) {
            state = BandConnectionState.disconnected
            throw BandError.NotConnected
        }
        state = BandConnectionState.connecting
        var verified = false
        try {
            BandTrace.notice("connect start")
            progress(0.0)
            // 02 edge 4 · STOPPED. 30 s is the app's last line: the bar stops where it was.
            try {
                sdk<Unit>("connect", seconds = 30.0) { done -> link(device.id, progress, done) }
            } catch (e: BandError.Timeout) {
                onMain { runCatching { vp.disconnectWatch(writeResponse) } }
                throw e
            }
            currentCoroutineContext().ensureActive()
            verified = true
            address = device.id
            watchConnection(device.id)
            state = BandConnectionState.connected
            BoundBand.remember(peripheralIdentifier = device.id)
        } finally {
            if (!verified) state = BandConnectionState.disconnected
        }
    }

    /** connect → notify → password. Each step is the SDK's own callback; only the verified
     *  password (and the device's function tables that ride with it) is a usable link. */
    private fun link(mac: String, progress: (Double) -> Unit, done: (Result<Unit>) -> Unit) {
        hub.send(BandEvent.ConnectionStep(BandSyncProgress.Stage.connecting))
        progress(0.25)
        vp.connectDevice(mac, object : IConnectResponse {
            override fun connectState(code: Int, profile: BleGattProfile?, isOadModel: Boolean) {
                BandTrace.record("sdk.connect_step", mapOf("state" to "connect", "code" to code.toString(), "oad" to isOadModel.toString()))
                if (code != Code.REQUEST_SUCCESS) done(Result.failure(BandError.Rejected("connect step $code")))
            }
        }, object : INotifyResponse {
            override fun notifyState(state: Int) {
                BandTrace.record("sdk.connect_step", mapOf("state" to "notify", "code" to state.toString()))
                if (state != Code.REQUEST_SUCCESS) { done(Result.failure(BandError.Rejected("connect step notify $state"))); return }
                hub.send(BandEvent.ConnectionStep(BandSyncProgress.Stage.verifying))
                progress(0.7)
                confirmPassword(progress, done)
            }
        })
    }

    private fun confirmPassword(progress: (Double) -> Unit, done: (Result<Unit>) -> Unit) {
        val is24 = runCatching { android.text.format.DateFormat.is24HourFormat(context) }.getOrDefault(true)
        vp.confirmDevicePwd(writeResponse, object : IPwdDataListener {
            override fun onPwdDataChange(data: PwdData?) {
                val pwd = data ?: return
                BandTrace.record("sdk.connect_step", mapOf("state" to "password", "status" to pwd.getmStatus().toString()))
                when (pwd.getmStatus()) {
                    EPwdStatus.CHECK_SUCCESS, EPwdStatus.CHECK_AND_TIME_SUCCESS -> {
                        pwdData = pwd
                        // The function tables arrive with the password; give them a moment so
                        // the first capability read is the band's, not a blank.
                        main.postDelayed({
                            progress(1.0)
                            done(Result.success(Unit))
                        }, if (functions == null) 1_500L else 0L)
                    }
                    EPwdStatus.CHECK_FAIL -> {
                        runCatching { vp.disconnectWatch(writeResponse) }
                        done(Result.failure(BandError.Rejected("connect step password")))
                    }
                    else -> {}
                }
            }
            override fun onConnectionConfirmTimeout() {
                runCatching { vp.disconnectWatch(writeResponse) }
                done(Result.failure(BandError.Timeout("connect")))
            }
        }, object : IDeviceFuctionDataListener {
            override fun onFunctionSupportDataChange(data: FunctionDeviceSupportData?) { if (data != null) functions = data }
            override fun onDeviceFunctionPackage1Report(p: DeviceFunctionPackage1?) {}
            override fun onDeviceFunctionPackage2Report(p: DeviceFunctionPackage2?) {}
            override fun onDeviceFunctionPackage3Report(p: DeviceFunctionPackage3?) {}
            override fun onDeviceFunctionPackage4Report(p: DeviceFunctionPackage4?) {}
            override fun onDeviceFunctionPackage5Report(p: DeviceFunctionPackage5?) {}
        }, object : ISocialMsgDataListener {
            override fun onSocialMsgSupportDataChange(data: FunctionSocailMsgData?) {}
            override fun onSocialMsgSupportDataChange2(data: FunctionSocailMsgData?) {}
        }, object : ICustomSettingDataListener {
            override fun OnSettingDataChange(data: CustomSettingData?) { if (data != null) customSetting = data }
        }, "0000", is24)
    }

    /** The link's own drop is the band going away; the SDK reports it per address. */
    private fun watchConnection(mac: String) {
        onMain {
            connectStatusListener?.let { runCatching { vp.unregisterConnectStatusListener(mac, it) } }
            val listener = object : IABleConnectStatusListener() {
                override fun onConnectStatusChanged(device: String?, status: Int) {
                    BandTrace.record("sdk.connection", mapOf("state" to status.toString()))
                    if (status == Constants.STATUS_DISCONNECTED && device == address) {
                        state = BandConnectionState.disconnected
                    }
                }
            }
            connectStatusListener = listener
            runCatching { vp.registerConnectStatusListener(mac, listener) }
        }
    }

    override suspend fun reconnectIfBound() {
        if (BoundBand.identifier == null || state == BandConnectionState.connected) return
        reconnectJob?.let { it.join(); return }
        val job = BandMain.scope.launch {
            for (attempt in 1..BandSyncPolicy.connectionAttempts) {
                if (!isActive || state == BandConnectionState.connected) break
                // The SDK's remembered peripheral can differ from our durable binding.
                // Scan explicitly, then connect only the bound device through the verified path.
                hub.send(BandEvent.ConnectionStep(BandSyncProgress.Stage.searching))
                startScan(auto = false)
                for (i in 0 until 200) {
                    if (state == BandConnectionState.connected || !isActive) break
                    val target = scanned.keys.firstOrNull {
                        BandSyncPolicy.matchesBoundDevice(discovered = it, sdkAddress = it,
                            bound = BoundBand.identifier, boundPeripheral = BoundBand.peripheralIdentifier)
                    }
                    if (target != null) {
                        stopScan()
                        try {
                            connect(DiscoveredBand(id = target, name = scanned[target]?.name ?: "NEXTBODY",
                                rssi = scanned[target]?.rssi ?: -99, batteryPercent = null)) {}
                        } catch (e: Throwable) {
                            if (e is CancellationException) throw e
                            BandTrace.error("bound reconnect failed: ${e.localizedDescription}")
                        }
                        break
                    }
                    delay(100)
                }
                onMain { runCatching { vp.stopScanDevice() } }
                if (state == BandConnectionState.connected) break
                BandTrace.notice("reconnect attempt $attempt failed")
                onMain { runCatching { vp.disconnectWatch(writeResponse) } }
                if (attempt < BandSyncPolicy.connectionAttempts) delay(1_000)
            }
            if (state != BandConnectionState.connected) state = BandConnectionState.disconnected
        }
        reconnectJob = job
        try { job.join() } finally { reconnectJob = null }
    }

    /** The sport lifetime owns this attempt and cancels it before handing the sensor back. */
    override suspend fun reconnectForSport() {
        if (state == BandConnectionState.connected || !currentCoroutineContext().isActive || !ConsentStore.granted) return
        SupabaseClient.currentUserIdSnapshot() ?: return
        BoundBand.identifier ?: return
        // A normal readiness flight may still be winding down when the workout takes over.
        while (reconnectJob != null) {
            if (!currentCoroutineContext().isActive) return
            delay(100)
        }
        reconnectIfBound()
    }

    override suspend fun prepareFreshSync() { historyReads.beginRefresh(scope = historyReadScope) }
    override suspend fun finishFreshSync() { historyReads.endRefresh() }

    override suspend fun auxiliaryCompletedAt(domain: BandAuxiliaryDomain): Instant? =
        historyReads.receipt(cacheDomain(domain), scope = historyReadScope)?.completedAt

    override suspend fun invalidateAuxiliary(domain: BandAuxiliaryDomain) { historyReads.drop(cacheDomain(domain)) }

    override suspend fun disconnect() {
        BandTrace.record("band.disconnect_requested")
        reconnectJob?.cancel()
        onMain { runCatching { vp.disconnectWatch(writeResponse) } }
        reconnectJob?.join()
        address = null
        state = BandConnectionState.disconnected
    }

    // MARK: identity and capability

    override suspend fun readIdentity(): BandIdentity {
        val pwd = pwdData ?: throw BandError.NotConnected
        val mac = address ?: throw BandError.NotConnected
        val f = functions
        val util = sp
        BandTrace.notice("identity · light=${util?.isSupportHealthLight} days=${f?.wathcDay}")
        return BandIdentity(
            name = scanned[mac]?.name?.takeIf { it.isNotBlank() } ?: util?.deviceName?.takeIf { it.isNotBlank() } ?: "NEXTBODY",
            model = pwd.deviceVersion ?: "—",
            hardware = pwd.deviceTestVersion ?: "—",
            firmware = pwd.deviceVersion ?: "—",
            // ⚠️ DeviceVersion.deviceNumber. There is no serial number in this SDK.
            deviceNumber = "HB-${pwd.deviceNumber}",
            bleIdentifier = mac,
            watchDataDayNumber = watchDay,
            // No sport mode, the single generic mode, or the multi-sport set — the same two
            // packet bytes iOS reads. Which sports those are, only the band's own workout
            // list can say.
            sportMode = VeepooMapping.sportModeLabel(saveTimes = f?.sportmodelday, type = f?.sportModelType))
    }

    private val watchDay: Int get() = functions?.wathcDay?.takeIf { it > 0 } ?: 3

    override suspend fun readCapabilities(): BandCapabilities {
        if (!isConnected) throw BandError.NotConnected
        val f = functions
        val util = sp
        fun status(s: EFunctionStatus?) = VeepooMapping.functionStatus(s?.name)
        val heartDetect = status(f?.heartDetect)
        return BandCapabilities(
            hrv = if (util?.hrvType?.let { it != 0 } == true) FunctionStatus.support else status(f?.hrvFunction),
            stress = status(f?.stress),
            ecg = status(f?.ecg),
            bodyComponent = status(f?.bodyComponent),
            // isSupportAutoMeasure is the explicit capability for the auto-measure sheet.
            autoMeasure = if (util?.isSupportAutoMeasure == true) FunctionStatus.support else FunctionStatus.unsupported,
            wearDetection = status(pwdData?.wearDetectFunction),
            functions = mapOf(
                "heart" to if (heartDetect == FunctionStatus.unsupported) FunctionStatus.unsupported else FunctionStatus.support,
                "temperature" to if (util?.isSupportReadTempture == true) FunctionStatus.support else FunctionStatus.unsupported,
            ),
        )
    }

    // MARK: health light

    private val lightReplies = ConcurrentHashMap<String, (Boolean, EHealthLightStatus?) -> Unit>()

    private val healthLightListener = object : IHealthLightListener {
        override fun onHealthLightStatusSetting(isSuccess: Boolean, status: EHealthLightStatus?) {
            lightReplies.remove("write")?.invoke(isSuccess, status)
        }
        override fun onHealthLightStatusRead(isSuccess: Boolean, status: EHealthLightStatus?) {
            lightReplies.remove("read")?.invoke(isSuccess, status)
        }
        override fun onHealthLightStatusReport(status: EHealthLightStatus?) {
            BandTrace.notice("health light changed by the band → ${status?.name}")
            BandTrace.record("band.health_light_changed", mapOf("state" to (status?.name ?: "unknown")))
        }
    }

    override suspend fun readHealthLight(): BandHealthLightState = healthLightCommand(null)
    override suspend fun writeHealthLight(state: BandHealthLightState): BandHealthLightState = healthLightCommand(state)

    /** Keep status reads and writes on the same queue as all other configuration commands. */
    private suspend fun healthLightCommand(requested: BandHealthLightState?): BandHealthLightState {
        val binding = BoundBand.identifier
        val name = if (requested == null) "readHealthLight" else "writeHealthLight"
        return queue.run(name, priority = if (requested == null) HoopQueue.Priority.p1 else HoopQueue.Priority.p0) {
            currentCoroutineContext().ensureActive()
            sdk<BandHealthLightState>(name) { done ->
                if (state != BandConnectionState.connected || binding != BoundBand.identifier) {
                    done(Result.failure(BandError.NotConnected)); return@sdk
                }
                if (sp?.isSupportHealthLight != true) {
                    // ⚠️ The firmware saying it has no addressable light: no setting reaches it.
                    BandTrace.record("band.health_light_unsupported", mapOf("supported" to "false"))
                    done(Result.failure(BandError.Unsupported("Health light"))); return@sdk
                }
                val reply: (Boolean, EHealthLightStatus?) -> Unit = { success, status ->
                    done(runCatching {
                        val confirmed = VeepooMapping.healthLight(status?.name)
                        BandHealthLightState.confirmedState(success = success, rawValue = confirmed?.raw ?: -1)
                    })
                }
                if (requested != null) {
                    lightReplies["write"] = reply
                    vp.setHealthLightStatus(EHealthLightStatus.valueOf(VeepooMapping.healthLightVendorName(requested)), writeResponse)
                } else {
                    lightReplies["read"] = reply
                    vp.readHealthLightStatus(writeResponse)
                }
            }
        }
    }

    // MARK: switches read through the personalization table

    private suspend fun readCustomSettingNow(): CustomSettingData = sdk("readCustomSetting", seconds = 8.0) { done ->
        vp.readCustomSetting(writeResponse) { data ->
            if (data == null) done(Result.failure(BandError.Rejected("SETTINGS READ FAILED")))
            else { customSetting = data; done(Result.success(data)) }
        }
    }

    private suspend fun writeCustomSetting(name: String, change: (CustomSetting) -> Unit): CustomSettingData {
        val current = readCustomSettingNow()
        val setting = CustomSetting(current)
        change(setting)
        return sdk(name, seconds = 8.0) { done ->
            vp.changeCustomSetting(writeResponse, { data ->
                if (data == null) done(Result.failure(BandError.Rejected("SETTINGS WRITE FAILED")))
                else { customSetting = data; done(Result.success(data)) }
            }, setting)
        }
    }

    private fun isOn(status: EFunctionStatus?): Boolean? = when (status) {
        EFunctionStatus.SUPPORT_OPEN -> true
        EFunctionStatus.SUPPORT_CLOSE, EFunctionStatus.SUPPORT -> false
        else -> null
    }

    /** 断链提醒 · the firmware's own "the phone is gone" signal. null means this NEXTBODY has no
     *  such switch; the sheet draws nothing for it. */
    override suspend fun readDisconnectReminder(): Boolean? {
        val binding = BoundBand.identifier
        return queue.run("readDisconnectReminder", priority = HoopQueue.Priority.p1) {
            currentCoroutineContext().ensureActive()
            if (!isConnected || binding != BoundBand.identifier) throw BandError.NotConnected
            isOn(readCustomSettingNow().disconnectRemind)
        }
    }

    override suspend fun writeDisconnectReminder(on: Boolean): Boolean {
        val binding = BoundBand.identifier
        return queue.run("writeDisconnectReminder", priority = HoopQueue.Priority.p0) {
            currentCoroutineContext().ensureActive()
            if (!isConnected || binding != BoundBand.identifier) throw BandError.NotConnected
            if (readCustomSettingNow().disconnectRemind == EFunctionStatus.UNSUPPORT) throw BandError.Unsupported("Disconnect reminder")
            val back = writeCustomSetting("writeDisconnectReminder") {
                it.isOpenDisconnectRemind = if (on) EFunctionStatus.SUPPORT_OPEN else EFunctionStatus.SUPPORT_CLOSE
            }
            isOn(back.disconnectRemind) ?: throw BandError.Rejected("DISCONNECT REMINDER REFUSED")
        }
    }

    // MARK: battery

    override suspend fun readBattery(): BandBattery {
        if (!isConnected) throw BandError.NotConnected
        return queue.run("readBattery", priority = HoopQueue.Priority.p1) {
            sdk("readBattery") { done ->
                vp.readBattery(writeResponse, IBatteryDataListener { data: BatteryData? ->
                    val d = data ?: return@IBatteryDataListener
                    // ⚠️ Firmware with isPercent = false gives 0–4 bars, never rendered with %.
                    // The SDK fires this again when the charge changes — 12 rule 07 · bind the
                    // event, do not poll. Later fires still publish.
                    val battery = BandBattery(
                        isPercent = d.isPercent,
                        percent = if (d.isPercent) d.batteryPercent else null,
                        level = if (d.isPercent) null else d.batteryLevel,
                        chargeState = VeepooMapping.chargeState(d.powerModel)).settled
                    hub.send(BandEvent.Battery(battery))
                    done(Result.success(battery))
                })
            }
        }
    }

    // MARK: personal info

    override suspend fun syncPersonalInfo(info: PersonalInfo) {
        if (!isConnected) throw BandError.NotConnected
        val account = SupabaseClient.currentUserIdSnapshot()
        val binding = BoundBand.identifier
        val ownsRequest: (Boolean) -> Boolean = { consent ->
            state == BandConnectionState.connected && BandPersonalInfoPolicy.owns(
                expectedAccount = account, expectedBinding = binding,
                account = SupabaseClient.currentUserIdSnapshot(), binding = BoundBand.identifier, consent = consent)
        }
        if (!ownsRequest(ConsentStore.granted)) throw CancellationException()
        val year = java.time.LocalDate.now().year
        if (info.heightCm <= 0 || info.weightKg <= 0 || info.birthYear <= 0 || info.birthYear > year ||
            info.targetStep !in 0..60000) throw BandError.Rejected("INVALID PERSONAL INFORMATION")
        queue.run("syncPersonalInfo", priority = HoopQueue.Priority.p0) {
            sdk<Unit>("syncPersonalInfo") { done ->
                // Recheck when the queued command actually reaches the native API.
                if (!ownsRequest(ConsentStore.granted)) { done(Result.failure(CancellationException())); return@sdk }
                val data = PersonInfoData(if (info.sexIsMale) ESex.MAN else ESex.WOMEN,
                    info.heightCm, info.weightKg, max(1, year - info.birthYear), info.targetStep)
                vp.syncPersonInfo(writeResponse, IPersonInfoDataListener { status: EOprateStauts? ->
                    if (BandPersonalInfoPolicy.acknowledged(if (status == EOprateStauts.OPRATE_SUCCESS) 1L else 0L)) done(Result.success(Unit))
                    else done(Result.failure(BandError.Rejected("PERSONAL INFORMATION SYNC FAILED")))
                }, data)
            }
        }
        if (!ownsRequest(ConsentStore.granted)) throw CancellationException()
        pushedWeightKg = info.weightKg.toDouble()
        pushedAt = Instant.now()
    }

    // MARK: reading a day

    private val historyReadScope: BandHistoryReadCache.Scope
        get() {
            val session = SupabaseClient.currentRequestSessionSnapshot()
            return BandHistoryReadCache.Scope(account = session.owner, binding = BoundBand.identifier,
                device = address, sessionGeneration = runCatching { UUID.fromString(session.generation) }.getOrNull())
        }

    private val dumpCarriesHrvAndOxygen: Boolean
        get() = sp?.originProtocolVersion?.let { it == 3 || it == 5 } == true

    /**
     * The SDK reads every day the band still holds — sleep, then the five-minute data with its
     * HRV and oxygen lists (protocol 3/5) — and reports progress. One command, and until it
     * completes nothing else may be sent, which the serial queue already guarantees.
     */
    private suspend fun readAllDataIfStale(): BandHistoryReadCache.Receipt {
        val scope = historyReadScope
        historyReads.receipt(BandHistoryReadCache.Domain.all, scope = scope)?.let {
            if (it.status == BandDomainReadStatus.complete) {
                BandTrace.record("sdk.read_all_reused")
                return it
            }
        }
        if (!isConnected) throw BandError.NotConnected
        val generation = historyReads.generation(scope)
        val startedAt = Instant.now()
        val days = watchDay
        val batch = HistoryStore.Batch()
        // Sleep first, on its own command.
        val sleepDeadline = BandSyncDeadline()
        sdk<Unit>("readSleep", seconds = 300.0, progressDeadline = sleepDeadline) { done ->
            vp.readSleepData(writeResponse, object : ISleepDataListener {
                override fun onSleepDataChange(day: String?, data: SleepData?) {
                    data?.let { batch.sleep.add(sleepInput(it)) }
                    sleepDeadline.advance("sleep:${batch.sleep.size}")
                }
                override fun onSleepProgress(progress: Float) {
                    sleepDeadline.advance("sleepProgress:$progress")
                }
                override fun onSleepProgressDetail(day: String?, packageNumber: Int) {
                    sleepDeadline.advance("sleepDetail:$day:$packageNumber")
                }
                override fun onReadSleepComplete() { done(Result.success(Unit)) }
            }, days)
        }
        // Then the five-minute data, day by day: today, yesterday, …
        val deadline = BandSyncDeadline()
        val readID = UUID.randomUUID().toString()
        sdk<Unit>("readAllData", seconds = 300.0, progressDeadline = deadline) { done ->
            val progress = object {
                fun detail(day: Int, date: String?, all: Int, current: Int) {
                    if (state != BandConnectionState.connected || historyReadScope != scope ||
                        historyReads.generation(scope) != generation) return
                    deadline.advance("$day:$current")
                    val percent = if (all > 0) current * 100 / all else 0
                    BandTrace.record("sdk.read_all_progress", mapOf("readID" to readID, "day" to day.toString(),
                        "date" to (date ?: ""), "progress" to percent.toString()))
                    noteHistoryRead(day = day + 1, of = days, percent = percent)
                }
            }
            if (dumpCarriesHrvAndOxygen) {
                vp.readOriginData(writeResponse, object : IOriginData3Listener {
                    override fun onOriginFiveMinuteListDataChange(list: MutableList<OriginData3>?) {
                        list?.forEach { batch.addOrigin(it, it.date) }
                    }
                    override fun onOriginHalfHourDataChange(data: OriginHalfHourData?) {}
                    override fun onOriginHRVOriginListDataChange(list: MutableList<HRVOriginData>?) {
                        list?.forEach { batch.addHrv(it) }
                    }
                    override fun onOriginSpo2OriginListDataChange(list: MutableList<Spo2hOriginData>?) {
                        list?.forEach { batch.addOxygen(it) }
                    }
                    override fun onReadOriginProgressDetail(day: Int, date: String?, all: Int, current: Int) = progress.detail(day, date, all, current)
                    override fun onReadOriginProgress(p: Float) { deadline.advance("p:$p") }
                    override fun onReadOriginComplete() { done(Result.success(Unit)) }
                    override fun onReadTimeout(day: Int) { done(Result.failure(BandError.Timeout("readAllData day $day"))) }
                }, days)
            } else {
                vp.readOriginData(writeResponse, object : IOriginDataListener {
                    override fun onOringinFiveMinuteDataChange(data: OriginData?) { data?.let { batch.addOrigin(it, it.date) } }
                    override fun onOringinHalfHourDataChange(data: OriginHalfHourData?) {}
                    override fun onReadOriginProgressDetail(day: Int, date: String?, all: Int, current: Int) = progress.detail(day, date, all, current)
                    override fun onReadOriginProgress(p: Float) { deadline.advance("p:$p") }
                    override fun onReadOriginComplete() { done(Result.success(Unit)) }
                    override fun onReadTimeout(day: Int) { done(Result.failure(BandError.Timeout("readAllData day $day"))) }
                }, days)
            }
        }
        val completedAt = Instant.now()
        if (historyReadScope != scope || historyReads.generation(scope) != generation ||
            state != BandConnectionState.connected || startedAt > completedAt) throw CancellationException()
        noteHistoryRead(day = days, of = days, percent = 100)
        history.adopt(batch)
        historyReads.record(BandDomainReadStatus.complete, BandHistoryReadCache.Domain.all, generation = generation,
            startedAt = startedAt, at = completedAt)
        BandTrace.record("sdk.command_duration", mapOf("command" to "readAllData",
            "durationSeconds" to BandTime.interval(completedAt, startedAt).toString(), "totalDays" to days.toString()))
        return BandHistoryReadCache.Receipt(status = BandDomainReadStatus.complete, startedAt = startedAt, completedAt = completedAt)
    }

    /** The dump's own day/percent is the only honest bar during a pull. */
    private fun noteHistoryRead(day: Int, of: Int, percent: Int) {
        val days = max(of, 1)
        hub.send(BandEvent.HistoryRead(day = min(max(day, 1), days), of = days, percent = percent.coerceIn(0, 100)))
    }

    /** ⚠️ dayOffset is the SDK's paging parameter and nothing else. */
    override suspend fun readOriginData(dayOffset: Int): List<OriginPoint> {
        val day = Instant.now().atZone(ZoneId.systemDefault()).minusDays(dayOffset.toLong()).toInstant()
        return readOriginPage(day).points
    }

    override suspend fun readOriginPage(calendarDay: Instant): OriginDataPage {
        if (!isConnected) throw BandError.NotConnected
        val date = BandTime.dayKey(calendarDay)
        return queue.run("readOriginData($date)", priority = HoopQueue.Priority.p2) {
            val snapshot = readAllDataIfStale()
            val points = history.originSlots(date).map { VeepooMapping.point(it) }.sortedBy { it.time }
            BandTrace.notice("readOriginData $date · ${points.size} points · heart ${points.count { it.heart != null }} · stress ${points.count { it.stress != null }}")
            OriginDataPage(points = points, readStartedAt = snapshot.startedAt ?: snapshot.completedAt,
                readCompletedAt = snapshot.completedAt)
        }
    }

    /** The in-process store holds the days the last dump returned; probe at most seven pages. */
    override suspend fun cachedHistoryDayOffsets(limit: Int): List<Int> {
        if (!isConnected) throw BandError.NotConnected
        val lastOffset = min(max(limit, 0), 6)
        if (lastOffset <= 0) return emptyList()
        return (1..lastOffset).filter { history.hasData(dayString(it)) }
    }

    /**
     * HRV, temperature and oxygen are separate domains. On protocol 3/5 firmware HRV and SpO2
     * ride the five-minute dump; older firmware has dedicated commands. Temperature type 5 is
     * in the five-minute data; other temperature types need their own command.
     */
    override suspend fun readHealthData(dayOffset: Int): BandHealthData {
        if (!isConnected) throw BandError.NotConnected
        val util = sp
        return queue.run("readHealthData($dayOffset)", priority = HoopQueue.Priority.p2) {
            readAllDataIfStale()
            val scope = historyReadScope
            val generation = historyReads.generation(scope)
            val hrvReceipt = historyReads.receipt(BandHistoryReadCache.Domain.hrv, scope)
            val temperatureReceipt = historyReads.receipt(BandHistoryReadCache.Domain.temperature, scope)
            val oxygenReceipt = historyReads.receipt(BandHistoryReadCache.Domain.oxygen, scope)
            val cachedHRV = hrvReceipt?.status
            val cachedTemperature = temperatureReceipt?.status
            val cachedOxygen = oxygenReceipt?.status
            val hrvSupported = util?.isSupportHRV == true
            val oxygenSupported = util?.isSupportSpo2h == true
            val temperatureSupported = util?.isSupportReadTempture == true
            val temperatureType = util?.temperatureType ?: 0
            var hrvStatus = cachedHRV ?: if (hrvSupported) BandDomainReadStatus.complete else BandDomainReadStatus.unsupported
            var temperatureStatus = cachedTemperature ?: if (temperatureSupported) BandDomainReadStatus.complete else BandDomainReadStatus.unsupported
            var oxygenStatus = cachedOxygen ?: if (oxygenSupported) BandDomainReadStatus.complete else BandDomainReadStatus.unsupported
            val opticalStatus = if (util?.isSupportBloodGlucose == true) BandDomainReadStatus.complete else BandDomainReadStatus.unsupported

            suspend fun dedicated(name: String, domain: BandHistoryReadCache.Domain,
                                  run: (BandSyncDeadline, (Result<Unit>) -> Unit) -> Unit): BandDomainReadStatus {
                if (state != BandConnectionState.connected) throw BandError.NotConnected
                val deadline = BandSyncDeadline()
                val started = Instant.now()
                val status = try {
                    sdk<Unit>(name, seconds = 300.0, progressDeadline = deadline) { done -> run(deadline, done) }
                    BandDomainReadStatus.complete
                } catch (e: Throwable) {
                    if (e is CancellationException) throw e
                    BandLog.shared.record(name, error = e)
                    if (state != BandConnectionState.connected) throw e
                    if (e is BandError.Unsupported) BandDomainReadStatus.unsupported else BandDomainReadStatus.failed
                }
                BandTrace.record("sdk.command_duration", mapOf("command" to name,
                    "durationSeconds" to BandTime.interval(Instant.now(), started).toString()))
                historyReads.record(status, domain, generation = generation)
                return status
            }

            if (hrvSupported && cachedHRV == null) {
                hrvStatus = if (dumpCarriesHrvAndOxygen) BandDomainReadStatus.complete.also {
                    historyReads.record(it, BandHistoryReadCache.Domain.hrv, generation = generation)
                } else dedicated("readHRV", BandHistoryReadCache.Domain.hrv) { deadline, done ->
                    val rows = mutableListOf<HRVOriginData>()
                    vp.readHRVOrigin(writeResponse, object : IHRVOriginDataListener {
                        override fun onReadOriginProgress(p: Float) { deadline.advance("p:$p") }
                        override fun onReadOriginProgressDetail(day: Int, date: String?, all: Int, current: Int) {
                            deadline.advance("$day:$current")
                            noteHistoryRead(day + 1, watchDay, if (all > 0) current * 100 / all else 0)
                        }
                        override fun onHRVOriginListener(data: HRVOriginData?) { data?.let { rows.add(it) } }
                        override fun onDayHrvScore(day: Int, date: String?, score: Int) {}
                        override fun onReadOriginComplete() {
                            history.adoptHrv(rows)
                            done(Result.success(Unit))
                        }
                    }, watchDay)
                }
            }
            if (temperatureSupported && temperatureType != 5 && cachedTemperature == null) {
                temperatureStatus = dedicated("readTemperature", BandHistoryReadCache.Domain.temperature) { deadline, done ->
                    val rows = mutableListOf<TemptureData>()
                    vp.readTemptureDataBySetting(writeResponse, object : ITemptureDataListener {
                        override fun onTemptureDataListDataChange(list: MutableList<TemptureData>?) { list?.let { rows.addAll(it) } }
                        override fun onReadOriginProgressDetail(day: Int, date: String?, all: Int, current: Int) {
                            deadline.advance("$day:$current")
                            noteHistoryRead(day + 1, watchDay, if (all > 0) current * 100 / all else 0)
                        }
                        override fun onReadOriginProgress(p: Float) { deadline.advance("p:$p") }
                        override fun onReadOriginComplete() {
                            history.adoptTemperature(rows)
                            done(Result.success(Unit))
                        }
                        override fun onReadTimeout(day: Int) { done(Result.failure(BandError.Timeout("readTemperature day $day"))) }
                    }, ReadOriginSetting(0, 1, false, watchDay))
                }
            }
            if (oxygenSupported && cachedOxygen == null) {
                oxygenStatus = if (dumpCarriesHrvAndOxygen) BandDomainReadStatus.complete.also {
                    historyReads.record(it, BandHistoryReadCache.Domain.oxygen, generation = generation)
                } else dedicated("readOxygen", BandHistoryReadCache.Domain.oxygen) { deadline, done ->
                    val rows = mutableListOf<Spo2hOriginData>()
                    vp.readSpo2hOrigin(writeResponse, object : ISpo2hOriginDataListener {
                        override fun onReadOriginProgress(p: Float) { deadline.advance("p:$p") }
                        override fun onReadOriginProgressDetail(day: Int, date: String?, all: Int, current: Int) {
                            deadline.advance("$day:$current")
                            noteHistoryRead(day + 1, watchDay, if (all > 0) current * 100 / all else 0)
                        }
                        override fun onSpo2hOriginListener(data: Spo2hOriginData?) { data?.let { rows.add(it) } }
                        override fun onReadOriginComplete() {
                            history.adoptOxygen(rows)
                            done(Result.success(Unit))
                        }
                    }, watchDay)
                }
            }
            val now = Instant.now()
            fun covers(receipt: BandHistoryReadCache.Receipt?) =
                BandSyncPolicy.reusedDumpCoversDay(dayOffset = dayOffset, completedAt = receipt?.completedAt, now = now)
            val date = dayString(dayOffset)
            val slots = history.originSlots(date)
            val temperatures = if (temperatureType == 5) {
                slots.mapNotNull { s -> s.temperature?.takeIf { it > 0 }?.let { TemperatureSample(s.time, it) } }
            } else history.temperatureRows(date).mapNotNull { HealthSampleMapping.temperature(it) }
            val hrv = history.hrvRows(date).mapNotNull { HealthSampleMapping.hrv(it) }
            val oxygenRows = history.oxygenRows(date)
            val oxygen = oxygenRows.mapNotNull { HealthSampleMapping.oxygen(it) }
            val respiration = oxygenRows.mapNotNull { HealthSampleMapping.respiration(it) }
                .ifEmpty { slots.mapNotNull { VeepooMapping.respiration(it) } }
            val optical = if (opticalStatus == BandDomainReadStatus.complete) slots.mapNotNull { VeepooMapping.optical(it) } else emptyList()
            val droppedZeros = if (opticalStatus == BandDomainReadStatus.complete) slots.count { it.bloodGlucose != null } - optical.size else 0
            BandTrace.notice("readHealthData($dayOffset) $date · hrv ${hrv.size} · temp ${temperatures.size} · spo2 ${oxygen.size} · optical ${optical.size}")
            BandTrace.record("sdk.cache_health", mapOf("date" to date, "hrvRows" to hrv.size.toString(),
                "temperatureRows" to temperatures.size.toString(), "oxygenRows" to oxygen.size.toString(),
                "respirationRows" to respiration.size.toString(), "hrvStatus" to hrvStatus.raw))
            BandHealthData(
                temperatures = temperatures, hrv = hrv, oxygen = oxygen,
                optical = optical, opticalDroppedZeros = max(0, droppedZeros),
                temperatureStatus = temperatureStatus, hrvStatus = hrvStatus,
                oxygenStatus = oxygenStatus, opticalStatus = opticalStatus,
                respiration = respiration,
                respirationStatus = if (respiration.isEmpty()) BandDomainReadStatus.notCollected else BandDomainReadStatus.complete,
                publishesHRV = cachedHRV == null || covers(hrvReceipt),
                publishesTemperature = temperatureType == 5 || cachedTemperature == null || covers(temperatureReceipt),
                publishesOxygen = cachedOxygen == null || covers(oxygenReceipt))
        }
    }

    /** The sleep that ends on the calendar day `dayOffset` back. Records are kept by their wake
     *  time; accurate (precision) records first, plain ones second — the claim is logged,
     *  never trusted on its own. */
    override suspend fun readSleep(dayOffset: Int): SleepNight? {
        if (!isConnected) throw BandError.NotConnected
        return queue.run("readSleep($dayOffset)", priority = HoopQueue.Priority.p2) {
            readAllDataIfStale()
            val morning = dayString(dayOffset)
            val records = history.sleepInputs()
            val result = VeepooMapping.night(records, morning)
            BandTrace.notice("readSleep($dayOffset) $morning · ${result?.totalMinutes ?: 0} min · line ${result?.line?.size ?: 0} runs · ${records.size} record(s) held")
            BandTrace.record("sdk.cache_sleep", mapOf("date" to morning, "rows" to records.size.toString(),
                "sleepStart" to (result?.sleepStart?.toString() ?: "unavailable"),
                "wakeAt" to (result?.wakeAt?.toString() ?: "unavailable"),
                "intervalCount" to (result?.intervals?.size ?: 0).toString()))
            result
        }
    }

    private fun sleepInput(data: SleepData): VeepooMapping.SleepInput {
        fun stamp(t: TimeData?) = t?.let { VeepooMapping.stamp(it.year, it.month, it.day, it.hour, it.minute) }
        val precise = data is SleepPrecisionData
        return VeepooMapping.SleepInput(
            sleepStamp = stamp(data.sleepDown), wakeStamp = stamp(data.sleepUp),
            total = data.allSleepTime, deep = data.deepSleepTime, light = data.lowSleepTime,
            other = (data as? SleepPrecisionData)?.otherDuration ?: 0,
            wakes = data.wakeCount, line = data.sleepLine ?: "", precise = precise)
    }

    // MARK: measurement

    override fun measureHeartRate(): Flow<MeasurementProgress> = callbackFlow {
        if (!isConnected) { close(BandError.NotConnected); return@callbackFlow }
        trySend(MeasurementProgress.WaitingForContact)
        heartTestGeneration += 1
        val gen = heartTestGeneration
        var started = false
        var finished = false
        BandTrace.notice("heart test start gen $gen")
        onMain {
            // Clear any leftover LiveReadout test before ours starts.
            runCatching { vp.stopDetectHeart(writeResponse) }
            if (heartTestGeneration != gen) return@onMain
            BandTrace.record("sdk.active_measurement", mapOf("kind" to "heart", "action" to "start_submitted"))
            vp.startDetectHeart(writeResponse, IHeartDataListener { data: HeartData? ->
                if (heartTestGeneration != gen || finished || data == null) return@IHeartDataListener
                val value = data.data
                BandTrace.record("sdk.active_callback", mapOf("kind" to "heart", "state" to data.heartStatus.toString(), "hasValue" to (value > 0).toString()))
                when (data.heartStatus) {
                    EHeartStatus.STATE_HEART_DETECT, EHeartStatus.STATE_HEART_NORMAL, EHeartStatus.STATE_INIT -> {
                        // The band's own answer that the sensor is on — not the echo of our start.
                        if (!started) { started = true; trySend(MeasurementProgress.Contact) }
                        // ⚠️ No progress fraction: the SDK only reports a rate. The phone's clock
                        // owns the minute; partial carries the beat.
                        trySend(MeasurementProgress.Measuring(fraction = 0.0,
                            partial = if (value > 0) PartialReading(heartRate = value) else null))
                    }
                    EHeartStatus.STATE_HEART_WEAR_ERROR -> {
                        // The test is dead. Yield the lift, then finish.
                        finished = true
                        trySend(MeasurementProgress.LostContact)
                        close()
                    }
                    EHeartStatus.STATE_HEART_BUSY -> { finished = true; close(BandError.Busy) }
                    EHeartStatus.STATE_LOW_BATTERY -> {
                        finished = true
                        trySend(MeasurementProgress.Failed(reason = "BAND BATTERY LOW"))
                        close()
                    }
                    else -> {}
                }
            })
        }
        // F1 rule 05 · stop before the screen goes. Only this generation may stop.
        awaitClose {
            onMain {
                if (heartTestGeneration != gen) return@onMain
                BandTrace.record("sdk.active_measurement", mapOf("kind" to "heart", "action" to "stop_submitted", "reason" to "stream_termination"))
                runCatching { vp.stopDetectHeart(writeResponse) }
            }
        }
    }

    override fun measureBodyComposition(): Flow<MeasurementProgress> = callbackFlow {
        if (!isConnected) { close(BandError.NotConnected); return@callbackFlow }
        // F2 §05 · a sample taken without a fresh syncPersonalInfo is thrown away rather than
        // stored, because the BIA multiplied by a stale weight.
        val weight = pushedWeightKg
        val at = pushedAt
        if (weight == null || at == null || BandTime.interval(Instant.now(), at) >= 300) {
            close(BandError.Rejected("SYNC YOUR WEIGHT FIRST")); return@callbackFlow
        }
        trySend(MeasurementProgress.WaitingForContact)
        BandTrace.notice("body scan start")
        var hadContact = false
        onMain {
            vp.startDetectBodyComponent(bleWriteResponse, object : IBodyComponentDetectListener {
                override fun onDetecting(progress: Int, leadState: Int) {
                    BandTrace.notice("body scan lead $leadState progress $progress")
                    // leadState 0 is the hand on the electrode — but only once the band's own
                    // count advances; the first callback says 0 before any finger is there.
                    val fraction = VeepooMapping.percentFraction(progress)
                    if (leadState == 0 && progress > 0) {
                        if (!hadContact) { hadContact = true; trySend(MeasurementProgress.Contact) }
                        trySend(MeasurementProgress.Measuring(fraction = fraction, partial = null,
                            secondsLeft = max(0, ((1 - fraction) * 30).roundToInt())))
                    } else if (leadState != 0 && hadContact) {
                        // ⚠️ Body composition has no resume: lifting off restarts the 30 seconds.
                        hadContact = false
                        trySend(MeasurementProgress.LostContact)
                    }
                }
                override fun onDetectSuccess(bodyComponent: BodyComponent) {
                    val b = bodyComponent
                    trySend(MeasurementProgress.Finished(MeasurementResult.BodyComposition(VeepooMapping.bodyComposition(
                        bmi = b.BMI, bodyFatRate = b.bodyFatRate, fatMass = b.fatRate, ffm = b.FFM,
                        muscleRate = b.muscleRate, muscleMass = b.muscleMass, subcutaneousFat = b.subcutaneousFat,
                        bodyWater = b.bodyWater, waterContent = b.waterContent, skeletalMuscleRate = b.skeletalMuscleRate,
                        boneMass = b.boneMass, proteinProportion = b.proteinProportion, proteinMass = b.proteinMass,
                        bmr = b.basalMetabolicRate, inputWeightKg = weight))))
                    close()
                }
                override fun onDetectFailed(detectState: DetectState) {
                    BandTrace.notice("body scan result state $detectState")
                    trySend(MeasurementProgress.Failed(reason = when (detectState) {
                        DetectState.BUSY -> "DEVICE BUSY"
                        DetectState.LOW_POWER -> "BAND BATTERY LOW"
                        else -> "SCAN DID NOT COMPLETE"
                    }))
                    close()
                }
                override fun onDetectStop() {}
            })
        }
        // F1 rule 05 · a body scan left running holds the electrodes and the queue.
        awaitClose {
            BandTrace.notice("body scan stop")
            onMain { runCatching { vp.stopDetectBodyComponent(bleWriteResponse) } }
        }
    }

    /** 04 · the band's own stress test. Progress while it runs and a single value at the end. */
    override suspend fun measureStress(progress: (Int) -> Unit): Int {
        if (!isConnected) throw BandError.NotConnected
        if (sp?.isSupportStress == false) throw BandError.Unsupported("STRESS")
        val reply = BandMeasurementReply<Int>()
        try {
            // The measured test is ~19 seconds; 90 seconds remains the firmware ceiling.
            return reply.wait(seconds = 90.0, start = { done ->
                onMain {
                    vp.startDetectPressure(bleWriteResponse, object : IPressureDetectListener {
                        override fun onDetecting(p: Int) {
                            if (!reply.isPending) return
                            BandTrace.notice("stress progress $p")
                            progress(p)
                        }
                        override fun onDetectSuccess(pressure: Int) {
                            if (!reply.isPending) return
                            // A complete with zero is not a reading.
                            if (pressure > 0) done(Result.success(pressure))
                        }
                        override fun onDetectFailed(detectState: PressureDetectState) {
                            if (!reply.isPending) return
                            done(Result.failure(when (detectState) {
                                PressureDetectState.BUSY -> BandError.Busy
                                PressureDetectState.LOW_POWER -> BandError.Rejected("BAND BATTERY LOW")
                                PressureDetectState.WEAR_OFF -> BandError.Rejected("NOT ON THE WRIST")
                                else -> BandError.Rejected("STRESS TEST FAILED")
                            }))
                        }
                        override fun onDetectStop() {}
                    })
                }
            }, stop = {
                // Exactly once and before the waiter is released: no trailing stop reaches a
                // new heart/stress session.
                onMain { runCatching { vp.stopDetectPressure(bleWriteResponse) } }
            })
        } catch (e: BandMeasurementReply.Timeout) {
            throw BandError.Timeout("stressTest")
        }
    }

    /** 06 · Battery Check's HRV leg. The first positive value, or a timeout — never invented. */
    override suspend fun measureHRV(timeout: Double): Int {
        if (!isConnected) throw BandError.NotConnected
        val listener = object : IHrvDetectListener {
            var done: ((Result<Int>) -> Unit)? = null
            override fun onHrvDetect(hrv: Int) {
                if (hrv > 0) done?.invoke(Result.success(hrv))
            }
            override fun onDetectFailed(detectState: HrvDetectState) {
                done?.invoke(Result.failure(when (detectState) {
                    HrvDetectState.BUSY -> BandError.Busy
                    HrvDetectState.LOW_POWER -> BandError.Rejected("BAND BATTERY LOW")
                    HrvDetectState.WEAR_OFF -> BandError.Rejected("NOT ON THE WRIST")
                    else -> BandError.Rejected("HRV TEST FAILED")
                }))
            }
            override fun onDetectStop() {}
        }
        val stop = {
            onMain {
                BandTrace.record("sdk.active_measurement", mapOf("kind" to "hrv", "action" to "stop_submitted"))
                runCatching { vp.stopDetectHrv(bleWriteResponse, listener) }
            }
        }
        try {
            return sdk("hrvTest", seconds = timeout) { done ->
                listener.done = { result -> stop(); done(result) }
                BandTrace.record("sdk.active_measurement", mapOf("kind" to "hrv", "action" to "start_submitted"))
                vp.startDetectHrv(bleWriteResponse, listener)
            }
        } catch (e: Throwable) {
            stop()
            throw e
        }
    }

    // MARK: firmware

    /** Ask Veepoo's update server about the connected band. An offer only when the server's
     *  build is newer; "up to date" is null, "could not ask" a throw. Nothing touches the band. */
    override suspend fun checkFirmwareUpdate(): FirmwareOffer? {
        val pwd = pwdData ?: throw BandError.NotConnected
        val mac = address ?: throw BandError.NotConnected
        val testServer = com.nextbody.hoop.app.DebugLaunch["NB_DEBUG_EDGE"] == "otatest"
        return sdk("checkOTA", seconds = 60.0) { done ->
            var info: Triple<String?, String?, Boolean>? = null
            vp.getOadVersion(OadSetting(mac, pwd.deviceVersion ?: "", pwd.deviceTestVersion ?: "", pwd.deviceNumber, false, testServer),
                object : OnGetOadVersionListener {
                    override fun onNetOadInfo(deviceNumber: Int, deviceVersion: String?, des: String?, netIsNew: Boolean) {
                        info = Triple(deviceVersion, des, netIsNew)
                        BandTrace.notice("ota server: version ${deviceVersion ?: "none"} · new $netIsNew")
                        if (!netIsNew || deviceVersion.isNullOrEmpty()) { done(Result.success(null)) }
                    }
                    override fun onNetOadDetailInfo(bean: OadFileBean?, netIsNew: Boolean) {
                        if (!netIsNew || bean == null) { done(Result.success(null)); return }
                        lastOffer = bean
                        val version = bean.deviceVersion ?: info?.first
                        if (version.isNullOrEmpty()) { done(Result.success(null)); return }
                        done(Result.success(FirmwareOffer(version = version, notes = VeepooMapping.firmwareNotes(bean.des ?: info?.second))))
                    }
                })
        }
    }

    /**
     * 12 rule 08 · the DFU pushes the file the server offered. "Success" is only "the file
     * crossed": the band drops the link, comes back, and the version it then reports is the
     * only proof. Not reading it back is `versionUnverified`.
     */
    override suspend fun updateFirmware(version: String, progress: (Double) -> Unit): FirmwareUpdateResult {
        if (!isConnected) throw BandError.NotConnected
        val before = pwdData?.deviceVersion ?: "—"
        val offer = lastOffer
        if (offer == null || offer.downUrl.isNullOrEmpty()) {
            return FirmwareUpdateResult.Failed(reason = "No firmware file on this phone — check for the update again")
        }
        BandTrace.notice("dfu start $before → $version")
        val file = try {
            download(offer)
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            return FirmwareUpdateResult.Failed(reason = "No firmware file on this phone — check for the update again")
        }
        val ok: Boolean = when {
            vp.isJLDevice -> jieLiOta(file.absolutePath, progress)
            vp.isNordicDevice -> sdk("dfu", seconds = 900.0) { done ->
                vp.startNordicOtaUpgrade(file.absolutePath, object : OnMcuMgrOtaListener {
                    override fun onUpgradeStarted(controller: FirmwareUpgradeController?) {}
                    override fun onStateChanged(prev: FirmwareUpgradeManager.State?, next: FirmwareUpgradeManager.State?) {}
                    override fun onUpgradeCompleted() { done(Result.success(true)) }
                    override fun onUpgradeFailed(state: FirmwareUpgradeManager.State?, error: McuMgrException?) { done(Result.success(false)) }
                    override fun onUpgradeCanceled(state: FirmwareUpgradeManager.State?) { done(Result.success(false)) }
                    override fun onUploadProgressChanged(bytesSent: Int, imageSize: Int, timestamp: Long) {
                        if (imageSize > 0) progress(VeepooMapping.progressFraction(bytesSent.toDouble() / imageSize))
                    }
                })
            }
            vp.isBluetrumDevice -> sdk("dfu", seconds = 900.0) { done ->
                vp.startZkOtaUpgrade(file.absolutePath, object : IZkOtaUpgradeListener {
                    override fun onOtaUpgradeReady() {}
                    override fun onOtaUpgradeStart() {}
                    override fun onOtaUpgradeUpdating(p: Int) { progress(VeepooMapping.progressFraction(p.toDouble())) }
                    override fun onOtaUpgradePause() {}
                    override fun onOtaUpgradeContinue() {}
                    override fun onOtaUpgradeSuccess() { done(Result.success(true)) }
                    override fun onOtaUpgradeWaitFinish() { done(Result.success(true)) }
                    override fun onOtaUpgradeFail(code: Int, message: String?) { done(Result.success(false)) }
                })
            }
            // The legacy OAD service (Goodix / old Nordic DFU) is not linked into this build.
            else -> return FirmwareUpdateResult.Failed(reason = "This band's update path is not available on Android")
        }
        if (!ok) return FirmwareUpdateResult.Failed(reason = "The band rejected the update — it is still on $before")
        // The band reboots on the new build and the link goes with it. Wait for it to come back,
        // then read the version it now reports.
        var waited = 0
        while (state != BandConnectionState.connected && waited < 300) {
            delay(100); waited += 1
            if (waited == 100 && state != BandConnectionState.connected) reconnectIfBound()
        }
        val after = pwdData?.deviceVersion
        if (state != BandConnectionState.connected || after.isNullOrEmpty()) {
            BandTrace.error("dfu done but the band did not come back to say its version")
            return FirmwareUpdateResult.VersionUnverified
        }
        BandTrace.notice("dfu done, band reports $after")
        return if (after == before) FirmwareUpdateResult.VersionUnverified else FirmwareUpdateResult.Completed(version = after)
    }

    private suspend fun download(offer: OadFileBean): File = withContext(Dispatchers.IO) {
        val dir = File(context?.cacheDir ?: throw BandError.NotConnected, "ota").apply { mkdirs() }
        val name = offer.downUrl.substringAfterLast('/').ifEmpty { "firmware.bin" }
        val file = File(dir, name)
        val response = OkHttpClient().newCall(Request.Builder().url(offer.downUrl).build()).execute()
        response.use { r ->
            if (!r.isSuccessful) throw BandError.Rejected("update server unreachable")
            file.outputStream().use { out -> r.body?.byteStream()?.copyTo(out) ?: throw BandError.Rejected("empty firmware file") }
        }
        val expected = offer.md5?.lowercase()?.takeIf { it.isNotBlank() }
        if (expected != null) {
            val digest = MessageDigest.getInstance("MD5").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
            if (digest != expected) { file.delete(); throw BandError.Rejected("firmware checksum mismatch") }
        }
        file
    }

    /** JieLi platform: notify → MTU → device authentication → file system → OTA. */
    private suspend fun jieLiOta(path: String, progress: (Double) -> Unit): Boolean {
        sdk<Unit>("dfu.jl.notify", seconds = 15.0) { done ->
            vp.openJLDataNotify(object : BleNotifyResponse {
                override fun onNotify(service: UUID?, character: UUID?, value: ByteArray?) {}
                override fun onResponse(code: Int) {
                    vp.changeMTU(247, IMtuChangeListener { done(Result.success(Unit)) })
                }
            })
        }
        sdk<Unit>("dfu.jl.auth", seconds = 30.0) { done ->
            vp.startJLDeviceAuth(object : RcspAuthResponse {
                override fun onRcspAuthStart() {}
                override fun onRcspAuthSuccess() { done(Result.success(Unit)) }
                override fun onRcspAuthFailed() { done(Result.failure(BandError.Rejected("JL AUTH FAILED"))) }
            })
        }
        sdk<Unit>("dfu.jl.files", seconds = 60.0) { done ->
            vp.listJLWatchList(object : JLWatchFaceManager.OnWatchDialInfoGetListener {
                override fun onGettingWatchDialInfo() {}
                override fun onWatchDialInfoGetStart() {}
                override fun onWatchDialInfoGetComplete() { done(Result.success(Unit)) }
                override fun onWatchDialInfoGetSuccess(system: MutableList<com.jieli.jl_fatfs.model.FatFile>?,
                                                       server: MutableList<com.jieli.jl_fatfs.model.FatFile>?,
                                                       pic: com.jieli.jl_fatfs.model.FatFile?) { done(Result.success(Unit)) }
                override fun onWatchDialInfoGetFailed(error: com.jieli.jl_rcsp.model.base.BaseError?) {
                    done(Result.failure(BandError.Rejected("JL FILE SYSTEM FAILED")))
                }
            })
        }
        return sdk("dfu", seconds = 1_800.0) { done ->
            vp.startJLDeviceOTAUpgrade(path, object : JLOTAHolder.OnJLDeviceOTAListener {
                override fun onOTAStart() {}
                override fun onProgress(p: Float) { progress(VeepooMapping.progressFraction(p.toDouble())) }
                override fun onNeedReconnect(address: String?, dfuLangAddress: String?, isReconnectBySdk: Boolean) {}
                override fun onDFULangConnectSuccess(address: String?) {}
                override fun onDFULangConnectFailed(address: String?) {}
                override fun onOTASuccess() { done(Result.success(true)) }
                override fun onOTAFailed(error: com.jieli.jl_bt_ota.model.base.BaseError?) { done(Result.success(false)) }
            })
        }
    }

    // MARK: find, signal, alarms

    override suspend fun startFindHoop() {
        if (!isConnected) throw BandError.NotConnected
        if (sp?.isSupportFindDeviceByPhone == false) throw BandError.Unsupported("Find NEXTBODY")
        findGeneration += 1
        val gen = findGeneration
        queue.run("startFindHoop", priority = HoopQueue.Priority.p0) {
            sdk<Unit>("find.start", seconds = 8.0) { done ->
                vp.startFindDeviceByPhone(writeResponse, findListener(gen) { phase ->
                    when (phase) {
                        FindHoopPhase.unsupported -> done(Result.failure(BandError.Unsupported("Find NEXTBODY")))
                        else -> done(Result.success(Unit))
                    }
                })
            }
        }
    }

    private fun findListener(gen: Int, onPhase: (FindHoopPhase) -> Unit = {}) = object : IFindDevicelistener {
        private fun emit(phase: FindHoopPhase) {
            if (gen == findGeneration) hub.send(BandEvent.FindHoop(phase))
            onPhase(phase)
        }
        override fun unSupportFindDeviceByPhone() = emit(FindHoopPhase.unsupported)
        override fun findedDevice() = emit(FindHoopPhase.exit)
        override fun unFindDevice() = emit(FindHoopPhase.timeout)
        override fun findingDevice() = emit(FindHoopPhase.enter)
    }

    override suspend fun stopFindHoop() {
        findGeneration += 1
        rssiEpoch += 1
        if (!isConnected) return
        val gen = findGeneration
        // STOP must return now. Timeout from this call is not a find-timeout.
        onMain {
            runCatching {
                vp.stopFindDeviceByPhone(writeResponse, object : IFindDevicelistener {
                    override fun unSupportFindDeviceByPhone() {}
                    override fun findedDevice() { if (gen == findGeneration) hub.send(BandEvent.FindHoop(FindHoopPhase.exit)) }
                    override fun unFindDevice() {}
                    override fun findingDevice() {}
                })
            }
        }
    }

    override suspend fun readConnectedRSSI(): Int {
        val mac = address ?: throw BandError.NotConnected
        val epoch = rssiEpoch
        return queue.run("rssi", priority = HoopQueue.Priority.p1) {
            sdk("rssi", seconds = 2.0) { done ->
                vp.readRssi(mac, BleReadRssiResponse { code, rssi ->
                    when {
                        epoch != rssiEpoch -> done(Result.failure(CancellationException()))
                        code != Code.REQUEST_SUCCESS || rssi == null -> done(Result.failure(BandError.Rejected("RSSI READ FAILED")))
                        else -> done(Result.success(rssi))
                    }
                })
            }
        }
    }

    override suspend fun readAlarms(): List<BandAlarm> = mutateAlarms(mode = 2, alarm = BandAlarm.emptyRead())
    override suspend fun writeAlarm(alarm: BandAlarm): List<BandAlarm> = mutateAlarms(mode = 1, alarm = BandAlarmMath.prepared(alarm))
    override suspend fun deleteAlarm(alarm: BandAlarm): List<BandAlarm> = mutateAlarms(mode = 0, alarm = alarm)

    private fun refuseIfBusy() {
        val current = queue.current ?: return
        if (busyCommandPrefixes.any { current.startsWith(it) }) throw BandError.Busy
    }

    private val alarmProtocol: BandAlarmProtocol?
        get() = when {
            sp?.isSupportTextAlarm == true -> BandAlarmProtocol.text
            sp?.isSupportMultiAlarm == true -> BandAlarmProtocol.scene
            else -> null
        }

    /** App operations are delete=0, write=1, read=2, exactly as the iOS adapter names them. */
    private suspend fun mutateAlarms(mode: Int, alarm: BandAlarm): List<BandAlarm> {
        if (!isConnected) throw BandError.NotConnected
        refuseIfBusy()
        val name = if (mode == 2) "alarms.read" else if (mode == 0) "alarms.delete" else "alarms.write"
        return queue.run(name, priority = if (mode == 2) HoopQueue.Priority.p1 else HoopQueue.Priority.p0) {
            val kind = alarmProtocol ?: throw BandError.Unsupported("alarms")
            BandTrace.record("alarms.protocol", mapOf("protocol" to kind.name, "operation" to mode.toString()))
            if (kind == BandAlarmProtocol.text) {
                // The vendor limits text alarms to ten. Read before adding so we never send an
                // eleventh row.
                if (mode == 1) {
                    val current = textAlarms(BandAlarm.emptyRead(), 2)
                    if (current.first.none { it.id == alarm.id } && current.second >= kind.capacity) {
                        throw BandError.Rejected("ALARM TABLE FULL")
                    }
                }
                return@run textAlarms(alarm, mode).first
            }
            sdk(name) { done ->
                val listener = IAlarm2DataListListener { data: AlarmData2? ->
                    val op = data?.oprate
                    val ok = op == EMultiAlarmOprate.READ_SUCCESS || op == EMultiAlarmOprate.READ_SUCCESS_SAVE ||
                        op == EMultiAlarmOprate.READ_SUCCESS_SAME_CRC || op == EMultiAlarmOprate.READ_SUCCESS_NULL ||
                        op == EMultiAlarmOprate.SETTING_SUCCESS || op == EMultiAlarmOprate.CLEAR_SUCCESS
                    when {
                        op == EMultiAlarmOprate.ALARM_FULL -> done(Result.failure(BandError.Rejected("THIS NEXTBODY IS FULL")))
                        ok -> done(Result.success((data?.alarm2SettingList ?: emptyList()).mapNotNull { sceneAlarm(it) }))
                        op == null || op == EMultiAlarmOprate.ALARM_REPORT || op == EMultiAlarmOprate.DEVICE_ALARM_MODIFY -> {}
                        else -> done(Result.failure(BandError.Rejected(if (mode == 2) "ALARM READ FAILED" else "ALARM WRITE FAILED")))
                    }
                }
                when (mode) {
                    2 -> vp.readAlarm2(writeResponse, listener)
                    0 -> vp.deleteAlarm2(writeResponse, listener, sdkAlarm(alarm))
                    else -> {
                        val existing = runCatching { vp.alarm2List }.getOrNull().orEmpty().any { it.alarmId == alarm.id }
                        if (existing) vp.modifyAlarm2(writeResponse, listener, sdkAlarm(alarm))
                        else vp.addAlarm2(writeResponse, listener, sdkAlarm(alarm))
                    }
                }
            }
        }
    }

    private suspend fun textAlarms(alarm: BandAlarm, mode: Int): Pair<List<BandAlarm>, Int> {
        if (mode != 2 && !alarm.isValidDeviceValue) throw BandError.Rejected("INVALID ALARM")
        val name = "alarms.text.${if (mode == 2) "read" else if (mode == 0) "delete" else "write"}"
        return sdk(name) { done ->
            val listener = object : ITextAlarmDataListener { override fun onAlarmDataChangeListListener(data: TextAlarmData?) {
                val op = data?.oprate
                val ok = op == EMultiAlarmOprate.READ_SUCCESS || op == EMultiAlarmOprate.READ_SUCCESS_SAVE ||
                    op == EMultiAlarmOprate.READ_SUCCESS_SAME_CRC || op == EMultiAlarmOprate.READ_SUCCESS_NULL ||
                    op == EMultiAlarmOprate.SETTING_SUCCESS || op == EMultiAlarmOprate.CLEAR_SUCCESS
                when {
                    op == EMultiAlarmOprate.ALARM_FULL -> done(Result.failure(BandError.Rejected("ALARM TABLE FULL")))
                    ok -> {
                        val raw = data?.textAlarm2SettingList ?: emptyList()
                        val alarms = raw.mapNotNull { setting ->
                            val a = BandAlarm(id = setting.alarmId, hour = setting.alarmHour, minute = setting.alarmMinute,
                                on = setting.isOpen, repeatMask = VeepooMapping.repeatMask(setting.repeatStatus) ?: -1,
                                date = BandAlarm.onceDatePlaceholder, scene = BandAlarm.silentScene, text = setting.content ?: "")
                            a.takeIf { it.isValidDeviceValue }
                        }
                        // Malformed firmware rows still occupy capacity; never silently deleted.
                        BandTrace.record("alarms.text_result", mapOf("operation" to mode.toString(),
                            "count" to raw.size.toString(), "invalidCount" to (raw.size - alarms.size).toString()))
                        done(Result.success(alarms to raw.size))
                    }
                    op == null -> {}
                    else -> done(Result.failure(BandError.Rejected(if (mode == 2) "ALARM READ FAILED" else "ALARM WRITE FAILED")))
                }
            } }
            when (mode) {
                2 -> vp.readTextAlarm(writeResponse, listener)
                0 -> vp.deleteTextAlarm(writeResponse, listener, textSetting(alarm))
                else -> {
                    val existing = runCatching { vp.textAlarmList }.getOrNull().orEmpty().any { it.alarmId == alarm.id }
                    if (existing) vp.modifyTextAlarm(writeResponse, listener, textSetting(alarm))
                    else vp.addTextAlarm(writeResponse, listener, textSetting(alarm))
                }
            }
        }
    }

    private fun textSetting(alarm: BandAlarm) = TextAlarm2Setting().apply {
        alarmId = alarm.id
        alarmHour = alarm.hour
        alarmMinute = alarm.minute
        isOpen = alarm.on
        repeatStatus = VeepooMapping.repeatString(alarm.repeatMask)
        unRepeatDate = alarm.date
        content = alarm.text
    }

    private fun sdkAlarm(alarm: BandAlarm) = Alarm2Setting().apply {
        alarmId = alarm.id
        alarmHour = alarm.hour
        alarmMinute = alarm.minute
        isOpen = alarm.on
        repeatStatus = VeepooMapping.repeatString(alarm.repeatMask)
        scene = BandAlarm.silentScene
        unRepeatDate = alarm.date
    }

    private fun sceneAlarm(setting: Alarm2Setting): BandAlarm? = BandAlarm(
        id = setting.alarmId, hour = setting.alarmHour, minute = setting.alarmMinute, on = setting.isOpen,
        repeatMask = VeepooMapping.repeatMask(setting.repeatStatus) ?: 0,
        date = setting.unRepeatDate ?: BandAlarm.onceDatePlaceholder,
        scene = setting.scene)

    // MARK: settings

    override suspend fun writeSetting(setting: BandSetting): BandSetting {
        if (!isConnected) throw BandError.NotConnected
        // F3 · the switch renders the value that came back. Optimistic UI means the firmware
        // wins a second later and the toggle flips under the user's finger.
        return queue.run("writeSetting", priority = HoopQueue.Priority.p0) {
            when (setting) {
                is BandSetting.HeartRateAlarm -> sdk("writeSetting.heartRateAlarm") { done ->
                    vp.settingHeartWarning(writeResponse, IHeartWaringDataListener { back: HeartWaringData? ->
                        when (back?.status) {
                            EHeartWaringStatus.OPEN_SUCCESS, EHeartWaringStatus.CLOSE_SUCCESS, EHeartWaringStatus.READ_SUCCESS ->
                                done(Result.success(BandSetting.HeartRateAlarm(on = back.isOpen,
                                    low = back.heartLow.takeIf { it > 0 } ?: setting.low,
                                    high = back.heartHigh.takeIf { it > 0 } ?: setting.high)))
                            EHeartWaringStatus.UNSUPPORT -> done(Result.failure(BandError.Unsupported("heart rate alarm")))
                            else -> done(Result.failure(BandError.Rejected("HEART RATE ALARM REFUSED")))
                        }
                    }, HeartWaringSetting(setting.high, setting.low, setting.on))
                }
            }
        }
    }

    // MARK: pulse study

    /** 06 · the pulse study. The SDK command is its single-lead start — the only path to
     *  beat-to-beat timing on this hardware — and the waveform is never requested
     *  (`isNeedCurve = false`), never carried, never drawn. See `BandService.measurePulseStudy`. */
    override fun measurePulseStudy(): Flow<PulseStudyStep> = callbackFlow {
        if (!isConnected) { close(BandError.NotConnected); return@callbackFlow }
        if (sp?.isSupportECG == false) { close(BandError.Unsupported("PULSE STUDY")); return@callbackFlow }
        trySend(PulseStudyStep.WaitingForContact)
        var contacted = false
        var finished = false
        val rrs = mutableListOf<Double>()
        val hearts = mutableListOf<Double>()
        var lastHrv: Int? = null
        var seconds = 0
        fun finish(averageHeart: Int?, duration: Int?, vendorHrv: Int?) {
            if (finished) return
            finished = true
            val (values, source) = VeepooMapping.pulseIntervals(rrs, hearts)
            BandTrace.notice("pulse study finished · ${values.size} interval(s) from ${source.raw} · rrs ${rrs.size} hearts ${hearts.size}")
            val meanHeart = hearts.filter { it > 0 }.takeIf { it.isNotEmpty() }?.average()?.roundToInt()
            trySend(PulseStudyStep.Finished(PulseStudy(
                heartRate = averageHeart?.takeIf { it > 0 } ?: meanHeart,
                intervals = values, source = source,
                durationSeconds = duration ?: seconds,
                vendorHRV = vendorHrv?.takeIf { it in 1..254 } ?: lastHrv)))
            close()
        }
        val listener = object : IECGDetectListener {
            override fun onEcgDetectInfoChange(info: EcgDetectInfo?) {}
            override fun onEcgDetectStateChange(s: EcgDetectState?) {
                val st = s ?: return
                if (finished) return
                BandTrace.notice("pulseStudy ← dataType ${st.dataType} progress ${st.progress} hr ${st.hr1} rr ${st.rr1} wear ${st.wear}")
                when (st.dataType) {
                    3 -> { finished = true; trySend(PulseStudyStep.Failed(reason = "NO READING")); close(); return }
                    4 -> { finish(null, null, null); return }
                }
                if (st.deviceState?.name == "BUSY") { finished = true; close(BandError.Busy); return }
                if (st.wear == 1) {
                    // The finger left the electrode: the run is over, its own outcome.
                    if (contacted) { finished = true; trySend(PulseStudyStep.LostContact); close() }
                    return
                }
                if (!contacted) { contacted = true; trySend(PulseStudyStep.Contact) }
                if (st.rr1 > 0) rrs.add(st.rr1.toDouble())
                if (st.hr1 > 0) hearts.add(st.hr1.toDouble())
                if (st.hrv in 1..254) lastHrv = st.hrv
                seconds += 1
                trySend(PulseStudyStep.Measuring(percent = st.progress.coerceIn(0, 100), heartRate = st.hr1.takeIf { it > 0 }))
                if (st.progress >= 100) finish(null, null, null)
            }
            override fun onEcgDetectResultChange(result: EcgDetectResult?) {
                val r = result ?: return
                if (r.detectHeart?.isNotEmpty() == true && hearts.isEmpty()) hearts.addAll(r.detectHeart.map { it.toDouble() })
                finish(r.aveHeart, r.duration.takeIf { it > 0 }, r.aveHrv)
            }
            override fun onEcgDetectDiagnosisChange(diagnosis: EcgDiagnosis?) {
                val d = diagnosis ?: return
                if (d.detectHeart?.isNotEmpty() == true && hearts.isEmpty()) hearts.addAll(d.detectHeart.map { it.toDouble() })
                finish(d.heartRate, d.duration.takeIf { it > 0 }, d.hrv)
            }
            override fun onEcgADCChange(data: IntArray?, power: IntArray?) {
                // ⚠️ The waveform is dropped on the floor here rather than carried up.
            }
        }
        BandTrace.notice("pulseStudy → start")
        onMain { vp.startDetectECG(bleWriteResponse, false, listener) }
        // F1 rule 05 · stop before the screen goes, however it goes.
        awaitClose { onMain { runCatching { vp.stopDetectECG(bleWriteResponse, false, listener) } } }
    }

    // MARK: probes

    /** DEBUG · what the watch itself has stored. One read, every kind. ⚠️ Nothing is measured. */
    override suspend fun readManualTestData(since: Instant): List<String> {
        if (!isConnected) throw BandError.NotConnected
        val from = max(0L, since.epochSecond)
        return queue.run("readManualTestData", priority = HoopQueue.Priority.p1) {
            sdk("manualTestData", seconds = 20.0) { done ->
                val lines = mutableListOf<String>()
                val types = listOf(DeviceManualDataType.ALL)
                vp.readDeviceManualData(writeResponse, from, types, types, object : IDeviceManualDetectDataListener {
                    override fun onBloodPressureDataChange(list: MutableList<BloodPressureManualData>?) { list?.forEach { lines.add("blood pressure · $it") } }
                    override fun onHeartRateDataChange(list: MutableList<HeartRateManualData>?) { list?.forEach { lines.add("heart rate · $it") } }
                    override fun onBloodGlucoseDataChange(list: MutableList<BloodGlucoseManualData>?) { list?.forEach { lines.add("blood sugar · $it") } }
                    override fun onPressureManualDataChange(list: MutableList<PressureManualData>?) { list?.forEach { lines.add("stress · $it") } }
                    override fun onBloodOxygenDataChange(list: MutableList<BloodOxygenManualData>?) { list?.forEach { lines.add("blood oxygen · $it") } }
                    override fun onBodyTemperatureDataChange(list: MutableList<BodyTemperatureManualData>?) { list?.forEach { lines.add("temperature · $it") } }
                    override fun onMetoManualDataChange(list: MutableList<MetoManualData>?) { list?.forEach { lines.add("MET · $it") } }
                    override fun onHrvManualDataChange(list: MutableList<HrvManualData>?) { list?.forEach { lines.add("HRV · $it") } }
                    override fun onBloodComponentManualDataChange(list: MutableList<BloodComponentManualData>?) { list?.forEach { lines.add("blood components · $it") } }
                    override fun onMiniCheckupManualDataChange(list: MutableList<MiniCheckupManualData>?) { list?.forEach { lines.add("health glance · $it") } }
                    override fun onEmotionManualDataChange(list: MutableList<EmotionManualData>?) { list?.forEach { lines.add("emotion · $it") } }
                    override fun onFatigueManualDataChange(list: MutableList<FatigueManualData>?) { list?.forEach { lines.add("fatigue · $it") } }
                    override fun onSkinConductanceManualDataChange(list: MutableList<SkinConductanceManualData>?) { list?.forEach { lines.add("skin conductance · $it") } }
                    override fun onReadProgress(progress: Float) {}
                    override fun onReadComplete() {
                        BandTrace.notice("manual test data · ${lines.size} record(s)")
                        done(Result.success(lines.toList()))
                    }
                    // A firmware with nothing stored answers with nothing: an empty list.
                    override fun onReadFail() { done(Result.success(lines.toList())) }
                })
            }
        }
    }

    /** DEBUG · 微体检. ⚠️ A real measurement on the wrist. */
    override suspend fun probeMicroTest(progress: (Int) -> Unit): List<Pair<String, Double>> {
        if (!isConnected) throw BandError.NotConnected
        if (sp?.isSupportMiniCheckup == false) throw BandError.Unsupported("MICRO TEST")
        val listener = object : IMiniCheckupOptListener {
            var done: ((Result<List<Pair<String, Double>>>) -> Unit)? = null
            override fun onMiniCheckupTestProgress(p: Int) { progress(p) }
            override fun onMiniCheckupStopSuccess() {}
            override fun onMiniCheckupTestFailed(errorCode: EMiniCheckupTestErrorCode) {
                done?.invoke(Result.failure(when (errorCode) {
                    EMiniCheckupTestErrorCode.FUNCTION_NOT_SUPPORT -> BandError.Unsupported("MICRO TEST")
                    EMiniCheckupTestErrorCode.DEVICE_BUSY -> BandError.Busy
                    EMiniCheckupTestErrorCode.LOW_POWER -> BandError.Rejected("BAND BATTERY LOW")
                    EMiniCheckupTestErrorCode.WEARING_ABNORMALITY -> BandError.Rejected("NOT ON THE WRIST")
                    EMiniCheckupTestErrorCode.ECG_LEAD_DETACHMENT -> BandError.Rejected("FINGER OFF THE ELECTRODE")
                    else -> BandError.Rejected("MICRO TEST FAILED")
                }))
            }
            override fun onMiniCheckupSuccess(m: MiniCheckupResultData) {
                done?.invoke(Result.success(listOf(
                    "heart rate" to m.heartRate.toDouble(),
                    "blood oxygen" to m.bloodOxygen.toDouble(),
                    "stress" to m.stress.toDouble(),
                    "blood sugar" to m.bloodGlucose.toDouble(),
                    "body temperature" to m.bodyTemperature.toDouble(),
                    "systolic" to m.systolicBloodPressure.toDouble(),
                    "diastolic" to m.diastolicBloodPressure.toDouble(),
                    "HRV" to m.hrv.toDouble(),
                )))
            }
            override fun onMiniCheckupDetailTestSuccess(detail: MiniCheckupDetailData) {}
        }
        val stop = { onMain { runCatching { vp.stopMiniCheckup(bleWriteResponse, listener) } } }
        try {
            return sdk("microTest", seconds = 180.0) { done ->
                listener.done = { result -> stop(); done(result) }
                vp.startMiniCheckup(bleWriteResponse, listener)
            }
        } catch (e: Throwable) {
            stop()
            throw e
        }
    }

    /** DEBUG · 微体检 (公版). The Android SDK has one mini-checkup command (above) and no
     *  health-glance model with its function bitmask; the honest answer is "not on this SDK". */
    override suspend fun probeHealthGlance(progress: (Int) -> Unit): BandHealthGlance {
        if (!isConnected) throw BandError.NotConnected
        throw BandError.Unsupported("HEALTH GLANCE")
    }

    /** The band's own list of what it can measure — `readFunSwitchState`, one read, no sensor
     *  time. ⚠️ An empty answer is a firmware with no such command, never seventeen noes. */
    override suspend fun readHealthFunctions(): List<BandHealthFunction> {
        if (!isConnected) throw BandError.NotConnected
        return queue.run("readHealthFunctions", priority = HoopQueue.Priority.p1) {
            // ⚠️ 5 s: a firmware without the command says nothing at all, and this read sits on
            // the serial queue in front of the day pull.
            sdk("readFuncAssessment", seconds = 5.0) { done ->
                vp.readFunSwitchState(bleWriteResponse, IFunSwitchListener { _: Int, states: Map<Int, EFunctionStatus>? ->
                    val rows = if (states.isNullOrEmpty()) emptyList()
                    else VeepooMapping.healthFunctions(states.mapValues { it.value?.name })
                    BandTrace.notice("health functions · ${rows.joinToString(" ") { "${it.name}=${if (it.support) (if (it.open) "open" else "support") else "no"}" }}")
                    done(Result.success(rows))
                })
            }
        }
    }

    /** DEBUG · what this firmware claims, read from the SDK's own capability cache. */
    override suspend fun probeCapabilitySweep(): List<String> {
        if (!isConnected) throw BandError.NotConnected
        val util = sp ?: throw BandError.NotConnected
        val f = functions
        return listOf(
            "model · ${pwdData?.deviceNumber} fw ${pwdData?.deviceVersion} test ${pwdData?.deviceTestVersion} cpu ${runCatching { vp.cpuPlatform }.getOrNull()}",
            "types · temp=${util.temperatureType} hrv=${util.hrvType} ecg=${util.ecgType} spo2=${util.spo2hType} stress=${util.stressType} origin=${util.originProtocolVersion}",
            "support · hrv=${util.isSupportHRV} spo2=${util.isSupportSpo2h} stress=${util.isSupportStress} ecg=${util.isSupportECG} body=${util.isSupportBodyComponent} auto=${util.isSupportAutoMeasure} light=${util.isSupportHealthLight}",
            "alarms · scene=${util.isSupportMultiAlarm} text=${util.isSupportTextAlarm} · find=${util.isSupportFindDeviceByPhone}",
            "days · ${f?.wathcDay} · precisionSleep=${f?.precisionSleep} · sport=${f?.sportModel}/${f?.multSportModel}",
        )
    }

    // MARK: automatic measurement

    override suspend fun readAutoMonitoring(): AutoMonitoringRead {
        if (!isConnected) throw BandError.NotConnected
        return queue.run("readAutoMonitoring", priority = HoopQueue.Priority.p1) {
            val intervalAPI = sp?.isSupportAutoMeasure == true
            BandTrace.notice("autoMeasure intervalAPI $intervalAPI")
            if (intervalAPI) {
                val models = readAutoMeasureNow()
                // ⚠️ One entry per measurement type, each with its own window and interval.
                // That is why 12's row leads to a sheet rather than a switch.
                val slots = models.mapNotNull { m ->
                    val kind = VeepooMapping.autoMeasureKind(m.funType?.name) ?: return@mapNotNull null
                    VeepooMapping.autoSlot(kind, on = m.isSwitchOpen, slotModify = m.isSlotModify,
                        intervalModify = m.isIntervalModify, startMinute = m.currentStartMinute,
                        endMinute = m.currentEndMinute, interval = m.measureInterval, stepUnit = m.stepUnit)
                }
                diagnoseSettings(slots, "interval_callback")
                return@run AutoMonitoringRead.Interval(includingScientificSleep(slots))
            }
            readSwitchFallback()
        }
    }

    private suspend fun readAutoMeasureNow(): List<AutoMeasureData> = sdk("readAutoMonitoring") { done ->
        vp.readAutoMeasureSettingData(writeResponse, object : IAutoMeasureSettingDataListener {
            override fun onSettingDataChange(list: MutableList<AutoMeasureData>?) {
                if (list == null) done(Result.failure(BandError.Rejected("THIS NEXTBODY DID NOT REPORT ITS AUTOMATIC MEASUREMENTS")))
                else done(Result.success(list.toList()))
            }
            override fun onSettingDataChangeFail() { done(Result.failure(BandError.Rejected("AUTO MONITORING REFUSED"))) }
            override fun onSettingDataChangeSuccess() {}
        })
    }

    override suspend fun writeAutoMonitoring(slot: AutoMonitorSlot) {
        if (!isConnected) throw BandError.NotConnected
        queue.run("writeAutoMonitoring", priority = HoopQueue.Priority.p0) {
            // Automatic PPG is the documented controller for scientific sleep on every firmware
            // generation, including devices that also expose the interval API.
            if (slot.kind == AutoMonitorSlot.Kind.scientificSleep || sp?.isSupportAutoMeasure != true) {
                writeSwitchFallback(slot)
                return@run
            }
            val native = readAutoMeasureNow().firstOrNull { VeepooMapping.autoMeasureKind(it.funType?.name) == slot.kind }
                ?: throw BandError.Unsupported("automatic ${slot.kind.raw} monitoring")
            val requested = slot.intervalMinutes
            if (requested !in 0..AutoMeasurementIntervalPolicy.maximumMinutes) {
                throw BandError.Rejected("$requested minute interval is not supported")
            }
            native.isSwitchOpen = slot.on
            if (native.isSlotModify) {
                native.currentStartMinute = slot.startHour * 60
                native.currentEndMinute = min(slot.endHour * 60, 24 * 60)
            }
            native.measureInterval = requested
            sdk<Unit>("writeAutoMonitoring") { done ->
                BandTrace.record("sdk.setting_write_submitted", mapOf("kind" to slot.kind.raw, "on" to slot.on.toString(), "api" to "interval"))
                vp.setAutoMeasureSettingData(writeResponse, native, object : IAutoMeasureSettingDataListener {
                    override fun onSettingDataChange(list: MutableList<AutoMeasureData>?) {
                        val accepted = list?.firstOrNull { VeepooMapping.autoMeasureKind(it.funType?.name) == slot.kind }
                        if (accepted != null && accepted.measureInterval != requested) {
                            done(Result.failure(BandError.Rejected("AUTO MONITORING INTERVAL WAS NOT APPLIED"))); return
                        }
                        done(Result.success(Unit))
                    }
                    override fun onSettingDataChangeFail() { done(Result.failure(BandError.Rejected("AUTO MONITORING REFUSED"))) }
                    override fun onSettingDataChangeSuccess() { done(Result.success(Unit)) }
                })
            }
        }
    }

    /** Firmware without the interval API: the older personalization switches, plus the
     *  night-oxygen switch, each `firmwareOwned`. A failed read hides nothing it could show. */
    private suspend fun readSwitchFallback(): AutoMonitoringRead {
        val settings = readCustomSettingNow()
        val slots = mutableListOf<AutoMonitorSlot>()
        fun add(kind: AutoMonitorSlot.Kind, status: EFunctionStatus?) {
            isOn(status)?.let { slots.add(AutoMonitorSlot.firmwareOwned(kind, it)) }
        }
        add(AutoMonitorSlot.Kind.heartRate, settings.autoHeartDetect)
        add(AutoMonitorSlot.Kind.bloodPressure, settings.autoBpDetect)
        add(AutoMonitorSlot.Kind.hrv, settings.autoHrv)
        add(AutoMonitorSlot.Kind.temperature, settings.autoTemperatureDetect)
        add(AutoMonitorSlot.Kind.bloodGlucose, settings.bloodGlucoseDetection)
        add(AutoMonitorSlot.Kind.stress, settings.stressDetect)
        add(AutoMonitorSlot.Kind.bloodComponents, settings.bloodComponentDetect)
        if (sp?.isSupportSpo2hDetectionSwitch == true) {
            runCatching { readOxygenSwitch() }.getOrNull()?.let { slots.add(AutoMonitorSlot.firmwareOwned(AutoMonitorSlot.Kind.bloodOxygen, it)) }
        }
        diagnoseSettings(slots, "base_switch_callback")
        return AutoMonitoringRead.Switches(includingScientificSleep(slots))
    }

    /** Scientific sleep is not one of the interval API's rows. Its authoritative state is the
     *  automatic PPG switch: turning that off also turns precise sleep off. */
    private suspend fun includingScientificSleep(slots: List<AutoMonitorSlot>): List<AutoMonitorSlot> {
        val result = slots.toMutableList()
        try {
            val on = isOn(readCustomSettingNow().ppg)
            if (on == null) {
                BandTrace.record("sdk.setting_fallback", mapOf("kind" to "scientificSleep", "reason" to "not_exposed"))
                return result
            }
            val sleep = AutoMonitorSlot.firmwareOwned(AutoMonitorSlot.Kind.scientificSleep, on)
            val index = result.indexOfFirst { it.kind == AutoMonitorSlot.Kind.scientificSleep }
            if (index >= 0) result[index] = sleep else result.add(sleep)
        } catch (e: Throwable) {
            if (e is CancellationException) throw e
            BandTrace.record("sdk.setting_fallback", mapOf("kind" to "scientificSleep", "reason" to diagnosticError(e)))
        }
        return result
    }

    private suspend fun readOxygenSwitch(): Boolean = sdk("readAutoMonitoringSwitch.oxygen", seconds = 8.0) { done ->
        vp.readSpo2hAutoDetect(writeResponse, IAllSetDataListener { data: AllSetData? ->
            if (data == null) done(Result.failure(BandError.Rejected("AUTO MONITORING SWITCH READ FAILED")))
            else done(Result.success(data.openState == 1 || data.isOpen == 1))
        })
    }

    private suspend fun writeSwitchFallback(slot: AutoMonitorSlot) {
        val on = if (slot.on) EFunctionStatus.SUPPORT_OPEN else EFunctionStatus.SUPPORT_CLOSE
        BandTrace.record("sdk.setting_write_submitted", mapOf("kind" to slot.kind.raw, "on" to slot.on.toString(), "api" to "base_switch"))
        if (slot.kind == AutoMonitorSlot.Kind.bloodOxygen) {
            sdk<Unit>("writeAutoMonitoringSwitch") { done ->
                vp.settingSpo2hAutoDetect(writeResponse, IAllSetDataListener { data: AllSetData? ->
                    val back = data?.let { it.openState == 1 || it.isOpen == 1 }
                    if (back == slot.on) done(Result.success(Unit))
                    else done(Result.failure(BandError.Rejected(if (slot.on) "AUTO MONITORING STAYED OFF" else "AUTO MONITORING STAYED ON")))
                }, AllSetSetting(EAllSetType.SPO2H_NIGHT_AUTO_DETECT, 22, 0, 8, 0, 0, if (slot.on) 1 else 0))
            }
            return
        }
        val back = writeCustomSetting("writeAutoMonitoringSwitch") { s ->
            when (slot.kind) {
                AutoMonitorSlot.Kind.heartRate -> s.isOpenAutoHeartDetect = slot.on
                AutoMonitorSlot.Kind.bloodPressure -> s.isOpenAutoBpDetect = slot.on
                AutoMonitorSlot.Kind.hrv -> s.isOpenAutoHRV = on
                AutoMonitorSlot.Kind.temperature -> s.isOpenAutoTemperatureDetect = on
                AutoMonitorSlot.Kind.bloodGlucose -> s.isOpenBloodGlucoseDetect = on
                AutoMonitorSlot.Kind.stress -> s.stressDetect = on
                AutoMonitorSlot.Kind.scientificSleep -> s.isOpenPPG = on
                AutoMonitorSlot.Kind.bloodComponents -> s.isOpenBloodComponentDetect = on
                else -> throw BandError.Unsupported("automatic ${slot.kind.raw} monitoring")
            }
        }
        val reported = when (slot.kind) {
            AutoMonitorSlot.Kind.heartRate -> isOn(back.autoHeartDetect)
            AutoMonitorSlot.Kind.bloodPressure -> isOn(back.autoBpDetect)
            AutoMonitorSlot.Kind.hrv -> isOn(back.autoHrv)
            AutoMonitorSlot.Kind.temperature -> isOn(back.autoTemperatureDetect)
            AutoMonitorSlot.Kind.bloodGlucose -> isOn(back.bloodGlucoseDetection)
            AutoMonitorSlot.Kind.stress -> isOn(back.stressDetect)
            AutoMonitorSlot.Kind.scientificSleep -> isOn(back.ppg)
            AutoMonitorSlot.Kind.bloodComponents -> isOn(back.bloodComponentDetect)
            else -> null
        }
        BandTrace.record("sdk.setting_write_callback", mapOf("kind" to slot.kind.raw, "state" to reported.toString(), "api" to "base_switch"))
        when (reported) {
            null -> throw BandError.Unsupported("automatic ${slot.kind.raw} monitoring")
            slot.on -> return
            else -> throw BandError.Rejected(if (slot.on) "AUTO MONITORING STAYED OFF" else "AUTO MONITORING STAYED ON")
        }
    }

    private fun diagnoseSettings(slots: List<AutoMonitorSlot>, source: String) {
        for (slot in slots) {
            BandTrace.record("sdk.setting_snapshot", mapOf("kind" to slot.kind.raw, "on" to slot.on.toString(),
                "source" to source, "startHour" to slot.startHour.toString(), "endHour" to slot.endHour.toString(),
                "intervalMinutes" to slot.intervalMinutes.toString()))
        }
    }

    // MARK: sport

    /** Open `mode`, let the band answer, close it again. The open callback is the verdict. */
    override suspend fun probeSportMode(rawValue: Int): Boolean {
        return try {
            startSportMode(rawValue)
            runCatching { stopSportMode(rawValue) }
            true
        } catch (e: BandError) {
            when (e) {
                is BandError.Unsupported, is BandError.Rejected -> false
                else -> throw e
            }
        }
    }

    /** ESportType's `value` equals its ordinal and the iOS `VPDeviceRuningMode` raw value
     *  (0 Common/NONE … 188 SpinningTop). ⚠️ `getSportType` answers NONE for an unknown
     *  value rather than null, so the match is checked here. */
    private fun sportType(rawValue: Int): ESportType? =
        runCatching { ESportType.getSportType(rawValue) }.getOrNull()?.takeIf { it.value == rawValue }

    override suspend fun startSportMode(rawValue: Int) {
        if (!isConnected) throw BandError.NotConnected
        val type = sportType(rawValue) ?: throw BandError.Unsupported("sport mode $rawValue")
        queue.run("startSportMode", priority = HoopQueue.Priority.p0) {
            sdk<Unit>("startSportMode") { done ->
                val listener = object : ISportModelStateListener {
                    override fun onSportModelStateChange(data: SportModelStateData?) {
                        val d = data ?: return
                        when {
                            d.oprateStauts == ECheckWear.OPEN_SUCCESS -> { runningSport = type; done(Result.success(Unit)) }
                            d.deviceStauts == ESportModelStateStauts.DEVICE_BUSY -> done(Result.failure(BandError.Busy))
                            d.oprateStauts == ECheckWear.OPEN_FAIL -> done(Result.failure(BandError.Rejected("SPORT MODE REFUSED")))
                        }
                    }
                    override fun onSportStopped() {}
                }
                if (rawValue == 0) vp.startSportModel(writeResponse, listener)
                else vp.startMultSportModel(writeResponse, listener, type)
            }
        }
    }

    override suspend fun stopSportMode(rawValue: Int) {
        if (!isConnected) throw BandError.NotConnected
        val type = sportType(rawValue) ?: throw BandError.Unsupported("sport mode $rawValue")
        try {
            queue.run("stopSportMode", priority = HoopQueue.Priority.p0) {
                sdk<Unit>("stopSportMode") { done ->
                    vp.stopSportModel(writeResponse, object : ISportModelStateListener {
                        override fun onSportModelStateChange(data: SportModelStateData?) {
                            val d = data ?: return
                            when {
                                d.oprateStauts == ECheckWear.CLOSE_SUCCESS -> done(Result.success(Unit))
                                d.deviceStauts == ESportModelStateStauts.DEVICE_BUSY -> done(Result.failure(BandError.Busy))
                                d.oprateStauts == ECheckWear.CLOSE_FAIL -> {
                                    BandTrace.notice("sport stop failed for $rawValue")
                                    done(Result.failure(BandError.Rejected("SPORT MODE DID NOT CLOSE")))
                                }
                            }
                        }
                        override fun onSportStopped() { done(Result.success(Unit)) }
                    })
                }
            }
            runningSport = ESportType.NONE
        } catch (e: BandError.Rejected) {
            // 14 · the legacy close refused — a session opened on the band itself answers no
            // here. The sport-control protocol's stop is the other door: fire it, then ask the
            // band where it stands. Only a `not started` answer counts as closed.
            BandTrace.notice("sport stop · trying the control protocol")
            queue.run("stopSportMode.control", priority = HoopQueue.Priority.p0) {
                onMain { runCatching { vp.setSportControlInfo(writeResponse, ESportControlType.STOP, type, sportControlListener()) } }
            }
            delay(1_200)
            val state = sportRunState()
            BandTrace.notice("sport stop · state after control stop ${state ?: "none"}")
            if (state != 0) throw BandError.Rejected("SPORT MODE DID NOT CLOSE")
            runningSport = ESportType.NONE
        }
    }

    private fun sportControlListener() = object : ISportControlOptListener {
        override fun onSportControlOptFail() {}
        override fun onSportControlOptSuccess() {}
        override fun onSportControlDataChange(dataInfo: SportControlDataInfo) = deliverSport(dataInfo)
    }

    private fun deliverSport(info: SportControlDataInfo) {
        val live = SportLiveInfo.deviceReport(
            heartRate = info.heartRate, rawCalories = info.calories.toLong(),
            durationSec = info.sportDuration, runState = info.runState?.value ?: 0,
            distanceM = info.distance.takeIf { it > 0 })
        sportLastReceipt = Instant.now()
        BandTrace.notice("sport info receipt hasHR=${live.heartRate != null} state=${live.runState ?: -1}")
        for (reader in sportReaders.values) reader(live)
    }

    /** One SDK report listener is shared by live readers and one-shot state probes; the poll
     *  that keeps it talking stops with the last reader. */
    override fun sportLiveInfo(): Flow<SportLiveInfo> = callbackFlow {
        if (!isConnected) { close(); return@callbackFlow }
        val id = UUID.randomUUID()
        sportReaders[id] = { trySend(it) }
        sportClosers[id] = { close() }
        val first = synchronized(sportSubscription) { sportSubscription.add(id) }
        if (first) {
            val generation = sportSubscription.generation
            sportLastReceipt = Instant.now()
            BandTrace.notice("sport info subscribe generation=$generation")
            onMain {
                runCatching {
                    vp.setSportControlReportListener(object : IDeviceSportReportListener {
                        override fun onSportControlDataChange(info: SportControlDataInfo) = deliverSport(info)
                    })
                }
            }
            sportPoll = work.launch {
                var misses = 0
                while (isActive) {
                    if (sportSubscription.generation != generation || sportReaders.isEmpty()) return@launch
                    if (state != BandConnectionState.connected) { finishSportReaders(); return@launch }
                    // Poll admission waits behind active native commands.
                    runCatching {
                        queue.run("sportStatePoll", priority = HoopQueue.Priority.p0) {
                            onMain { runCatching { vp.readSportControlInfo(writeResponse, runningSport, sportControlListener()) } }
                        }
                    }
                    delay(1_000)
                    if (BandTime.interval(Instant.now(), sportLastReceipt) > 1.5) {
                        misses += 1
                        if (misses >= 3) {
                            BandTrace.notice("sport info no answer to three reads")
                            finishSportReaders()
                            return@launch
                        }
                    } else misses = 0
                }
            }
        }
        awaitClose { removeSportReader(id) }
    }

    private fun removeSportReader(id: UUID) {
        sportReaders.remove(id)
        sportClosers.remove(id)
        val last = synchronized(sportSubscription) { sportSubscription.remove(id) }
        if (!last) return
        sportPoll?.cancel()
        sportPoll = null
        onMain { runCatching { vp.setSportControlReportListener(null) } }
    }

    private fun finishSportReaders() {
        for ((id, close) in sportClosers.toMap()) {
            removeSportReader(id)
            close()
        }
    }

    // MARK: history store

    /** What the iOS SDK keeps in its own database, for this process: per calendar date. */
    private class HistoryStore {
        class Batch {
            val origin = HashMap<String, HashMap<String, VeepooMapping.OriginSlot>>()
            val hrv = HashMap<String, HashMap<String, Map<String, Any?>>>()
            val oxygen = HashMap<String, HashMap<String, Map<String, Any?>>>()
            val sleep = mutableListOf<VeepooMapping.SleepInput>()

            fun addOrigin(data: OriginData, fallbackDate: String?) {
                val t = data.getmTime() ?: return
                val date = if (t.year > 0) VeepooMapping.dayKey(t.year, t.month, t.day) else fallbackDate ?: return
                val time = VeepooMapping.clock(t.hour, t.minute)
                val d3 = data as? OriginData3
                origin.getOrPut(date) { HashMap() }[time] = VeepooMapping.OriginSlot(
                    time = time, rateValue = data.rateValue,
                    ppgs = d3?.ppgs?.toList().orEmpty(), ecgs = d3?.ecgs?.toList().orEmpty(),
                    steps = data.stepValue, calories = data.calValue, distanceKm = data.disValue,
                    met = d3?.met?.toDouble()?.takeIf { it > 0 },
                    temperature = data.temperature.takeIf { it > 0 } ?: data.baseTemperature.takeIf { it > 0 },
                    pressure = d3?.pressure,
                    resRates = d3?.resRates?.toList().orEmpty(),
                    bloodGlucose = d3?.bloodGlucose?.toDouble())
            }

            fun addHrv(data: HRVOriginData) {
                val t = data.getmTime() ?: return
                val date = VeepooMapping.dayKey(t.year, t.month, t.day)
                val time = VeepooMapping.clock(t.hour, t.minute)
                hrv.getOrPut(date) { HashMap() }[time] = VeepooMapping.hrvRow(time,
                    VeepooMapping.hearts(data.rate, data.rrValue), data.hrvValue)
            }

            fun addOxygen(data: Spo2hOriginData) {
                val t = data.getmTime() ?: return
                val date = VeepooMapping.dayKey(t.year, t.month, t.day)
                val time = VeepooMapping.clock(t.hour, t.minute)
                oxygen.getOrPut(date) { HashMap() }[time] = VeepooMapping.oxygenRow(time, data.oxygenValue, data.respirationRate)
            }
        }

        private val lock = Any()
        private val origin = HashMap<String, Map<String, VeepooMapping.OriginSlot>>()
        private val hrv = HashMap<String, Map<String, Map<String, Any?>>>()
        private val oxygen = HashMap<String, Map<String, Map<String, Any?>>>()
        private val temperature = HashMap<String, Map<String, Map<String, Any?>>>()
        private var sleep: List<VeepooMapping.SleepInput> = emptyList()

        /** A completed dump replaces the dates it returned; older dates stay. */
        fun adopt(batch: Batch) = synchronized(lock) {
            origin.putAll(batch.origin)
            hrv.putAll(batch.hrv)
            oxygen.putAll(batch.oxygen)
            val bySpan = (sleep + batch.sleep).associateBy { it.sleepStamp to it.wakeStamp }
            sleep = bySpan.values.toList()
        }

        fun adoptHrv(rows: List<HRVOriginData>) {
            val b = Batch(); rows.forEach { b.addHrv(it) }
            synchronized(lock) { hrv.putAll(b.hrv) }
        }

        fun adoptOxygen(rows: List<Spo2hOriginData>) {
            val b = Batch(); rows.forEach { b.addOxygen(it) }
            synchronized(lock) { oxygen.putAll(b.oxygen) }
        }

        fun adoptTemperature(rows: List<TemptureData>) {
            val byDate = HashMap<String, HashMap<String, Map<String, Any?>>>()
            for (row in rows) {
                val t = row.getmTime() ?: continue
                val date = VeepooMapping.dayKey(t.year, t.month, t.day)
                byDate.getOrPut(date) { HashMap() }[VeepooMapping.clock(t.hour, t.minute)] =
                    VeepooMapping.temperatureRow(t.hour, t.minute, row.baseTempture.toDouble().takeIf { it > 0 } ?: row.tempture.toDouble())
            }
            synchronized(lock) { temperature.putAll(byDate) }
        }

        fun originSlots(date: String): List<VeepooMapping.OriginSlot> = synchronized(lock) { origin[date]?.values?.toList().orEmpty() }
        fun hrvRows(date: String): List<Map<String, Any?>> = synchronized(lock) { hrv[date]?.values?.toList().orEmpty() }
        fun oxygenRows(date: String): List<Map<String, Any?>> = synchronized(lock) { oxygen[date]?.values?.toList().orEmpty() }
        fun temperatureRows(date: String): List<Map<String, Any?>> = synchronized(lock) { temperature[date]?.values?.toList().orEmpty() }
        fun sleepInputs(): List<VeepooMapping.SleepInput> = synchronized(lock) { sleep }

        fun hasData(date: String): Boolean = synchronized(lock) {
            !origin[date].isNullOrEmpty() || !hrv[date].isNullOrEmpty() || !oxygen[date].isNullOrEmpty() ||
                !temperature[date].isNullOrEmpty() ||
                sleep.any { it.wakeStamp?.startsWith(date) == true || it.sleepStamp?.startsWith(date) == true }
        }
    }

    companion object {
        private val busyCommandPrefixes = listOf(
            "readAllData", "readSleep", "readHRV", "readTemperature", "readOxygen",
            "hrvTest", "microTest", "healthGlance", "manualTestData",
            "dfu", "startSportMode", "find.start",
        )

        /** "yyyy-MM-dd" in the phone's calendar, the day's key in the history store. */
        private fun dayString(daysAgo: Int): String =
            BandTime.dayKey(Instant.now().atZone(ZoneId.systemDefault()).minusDays(daysAgo.toLong()).toInstant())

        private fun cacheDomain(domain: BandAuxiliaryDomain): BandHistoryReadCache.Domain = when (domain) {
            BandAuxiliaryDomain.hrv -> BandHistoryReadCache.Domain.hrv
            BandAuxiliaryDomain.oxygen -> BandHistoryReadCache.Domain.oxygen
            BandAuxiliaryDomain.temperature -> BandHistoryReadCache.Domain.temperature
        }
    }
}

/**
 * The band the app is talking to. Since two HOOPs, one wearer (2026-09-13) this reads the
 * transport slot in `DeviceSlots`: every call site that keys readiness, refresh scope and
 * evidence by `identifier` follows the link the moment the transport slot changes.
 */
object BoundBand {
    /** MockBand / simulator walk-through. Must never unbind a real NEXTBODY. */
    const val seedIdentifier = "C4-2E-8F-1A-73-9D"
    private const val legacyKey = "nb.band.identifier"
    private const val legacyPeripheralKey = "nb.band.peripheralIdentifier"
    private const val legacyPeripheralOwnerKey = "nb.band.peripheralBinding"

    /** A phone that bound one NEXTBODY before slots existed keeps it, in slot A — for the
     *  account signed in now. With nobody signed in it waits for `adoptUnownedBindings`. */
    private fun migrateIfNeeded() {
        if (DeviceSlots.owner == null || DeviceSlots.bindings.isNotEmpty()) return
        val legacy = BandPrefs.string(legacyKey) ?: return
        val peripheral = if (BandPrefs.string(legacyPeripheralOwnerKey) == legacy) BandPrefs.string(legacyPeripheralKey) else null
        DeviceSlots.set(SlotBinding(slot = HoopSlot.a, identifier = legacy, peripheralIdentifier = peripheral))
        DeviceSlots.transport = HoopSlot.a
        DeviceSlots.wearing = HoopSlot.a
        for (key in listOf(legacyKey, legacyPeripheralKey, legacyPeripheralOwnerKey)) BandPrefs.remove(key)
    }

    /** The durable binding key of the transport band. `null` means nothing is bound. */
    var identifier: String?
        get() {
            migrateIfNeeded()
            return DeviceSlots.binding(DeviceSlots.transport)?.identifier
        }
        set(newValue) {
            migrateIfNeeded()
            val slot = DeviceSlots.transport
            if (newValue == null) { DeviceSlots.remove(slot); return }
            var binding = DeviceSlots.binding(slot) ?: SlotBinding(slot = slot, identifier = newValue)
            if (binding.identifier != newValue) binding = binding.copy(peripheralIdentifier = null)
            binding = binding.copy(identifier = newValue)
            DeviceSlots.set(binding)
        }

    /** The slot the link currently targets. */
    val transportSlot: HoopSlot
        get() {
            migrateIfNeeded()
            return DeviceSlots.transport
        }

    /** Point the link at another slot. The caller disconnects first and reconnects after;
     *  readiness snapshots and refresh scopes keyed by `identifier` fall out on their own. */
    fun switchTransport(slot: HoopSlot) {
        migrateIfNeeded()
        DeviceSlots.transport = slot
    }

    /** This phone's alias for the transport band. On Android that is the BLE address; the
     *  iOS SDK's remembered-MAC compatibility path has no Android counterpart. */
    val peripheralIdentifier: String?
        get() {
            migrateIfNeeded()
            val value = DeviceSlots.binding(DeviceSlots.transport)?.peripheralIdentifier
            return value?.takeIf { isPeripheralAlias(it) }
        }

    fun remember(peripheralIdentifier: String) {
        if (!isPeripheralAlias(peripheralIdentifier)) return
        migrateIfNeeded()
        val slot = DeviceSlots.transport
        // A reconnect keeps legacy cache keys; a new pairing gets the stable alias.
        if (!BandSyncPolicy.matchesBoundDevice(discovered = peripheralIdentifier, bound = identifier,
                boundPeripheral = this.peripheralIdentifier)) {
            identifier = peripheralIdentifier
        }
        val binding = DeviceSlots.binding(slot) ?: return
        DeviceSlots.set(binding.copy(peripheralIdentifier = peripheralIdentifier))
    }

    /** Launch, before anything reads a binding: bands stored before one band, one account
     *  go to the account the stored session says is signed in, or nowhere. */
    fun adoptUnownedBindings(owner: String?) {
        DeviceSlots.owner = owner
        DeviceSlots.adoptUnownedBindings(owner)
        if (owner == null) for (key in listOf(legacyKey, legacyPeripheralKey, legacyPeripheralOwnerKey)) BandPrefs.remove(key)
    }

    /** Forget only the app bindings — both slots; server history stays. */
    fun forget() {
        DeviceSlots.forgetAll()
        for (key in listOf(legacyKey, legacyPeripheralKey, legacyPeripheralOwnerKey)) BandPrefs.remove(key)
    }

    private fun isPeripheralAlias(value: String): Boolean =
        runCatching { UUID.fromString(value); true }.getOrDefault(false) || BluetoothAdapter.checkBluetoothAddress(value)
}

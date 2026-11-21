// The phone↔watch link on Android: one radio over the Wear OS data layer.
//
// Plan: `docs/plans/2026-11-20-280-wear-os-shell-plan/2026-11-20-280-wear-os-shell-plan.md`
// (D-28002, D-28003). The mirror of `ios/Classes/OmniTrainWatchLinkPlugin.swift`,
// with the same five calls and the same four event kinds, so the Dart side
// (`WatchLink`, `WatchConnectivityChannel`) is one file for both platforms and
// nothing above it knows which wrist it is talking to.
//
// Three rules shape it:
//
// 1. **Symmetric, not phone-only.** The same Flutter project builds both apps,
//    so both compile this module. The device's own feature set says which role
//    it plays (`FEATURE_WATCH`), and the peer is discovered by the *other*
//    side's capability. Nothing here assumes it is the phone.
// 2. **The OS queue is the data layer.** A frame the phone owes the wrist for
//    good becomes one data item under its own `messageId`, which the data layer
//    carries when the two devices next meet and which either side can list and
//    delete. That is the Wear counterpart of `transferUserInfo`.
// 3. **No event is lost to a cold start.** Events are buffered (cap 500) until
//    Dart attaches its listener, exactly as the iOS half buffers them.

package dev.sasha.omnitrain.watch_link

import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.NodeClient
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.util.ArrayDeque

class OmniTrainWatchLinkPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        private const val METHODS = "omnitrain/watch_link/methods"
        private const val EVENTS = "omnitrain/watch_link/events"

        /** The live channel: one Wear message, one path. */
        private const val FRAME_PATH = "/omnitrain/frame"

        /** Queued frames: one data item per frame, keyed by its `messageId`. */
        private const val QUEUE_PREFIX = "/omnitrain/queue/"

        /**
         * The capabilities the two apps declare in their own `wear.xml`, so a
         * peer that is installed is known before it ever launches a sync.
         */
        private const val PHONE_CAPABILITY = "omnitrain_phone"
        private const val WATCH_CAPABILITY = "omnitrain_wear"

        private const val ROLE_PHONE = "phone"
        private const val ROLE_WATCH = "watch"

        /**
         * What the data layer carries in one message or one data item. A frame
         * larger than this is refused rather than truncated: the sender learns
         * it was not delivered and the protocol splits it.
         */
        private const val MAX_FRAME_BYTES = 100 * 1024

        /** How many events wait for Dart to attach its listener. */
        private const val BUFFER_CAP = 500

        private const val KEY_MESSAGE_ID = "messageId"
        private const val KEY_ROLE = "role"
        private const val KEY_FRAME = "frame"
        private const val KEY_TYPE = "type"
        private const val KEY_SESSION_ID = "sessionId"
        private const val KEY_CHANGE_ID = "changeId"
    }

    private var context: Context? = null
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null

    private val main = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private val pending = ArrayDeque<Map<String, Any?>>()

    private var nodeClient: NodeClient? = null
    private var messageClient: MessageClient? = null
    private var dataClient: DataClient? = null
    private var capabilityClient: CapabilityClient? = null

    /** Attached for the life of the engine; the platform keeps them weakly. */
    private var messageListener: MessageClient.OnMessageReceivedListener? = null
    private var dataListener: DataClient.OnDataChangedListener? = null
    private var capabilityListener: CapabilityClient.OnCapabilityChangedListener? = null

    private var isWatch = false
    private var supported = false

    /** The peer's node id, when one is known, and whether it is in range. */
    private var peerNodeId: String? = null
    private var peerNearby = false

    /** The last reachability reported, so a repeat is not reported again. */
    private var lastReachable: Boolean? = null

    // MARK: - FlutterPlugin

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val appContext = binding.applicationContext
        context = appContext
        methods = MethodChannel(binding.binaryMessenger, METHODS).also {
            it.setMethodCallHandler(this)
        }
        events = EventChannel(binding.binaryMessenger, EVENTS).also {
            it.setStreamHandler(this)
        }

        isWatch = appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH)
        supported = GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(appContext) == ConnectionResult.SUCCESS

        if (!supported) return

        nodeClient = Wearable.getNodeClient(appContext)
        messageClient = Wearable.getMessageClient(appContext)
        dataClient = Wearable.getDataClient(appContext)
        capabilityClient = Wearable.getCapabilityClient(appContext)

        attachListeners()
        resolvePeer()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachListeners()
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        methods = null
        events = null
        nodeClient = null
        messageClient = null
        dataClient = null
        capabilityClient = null
        context = null
        sink = null
        pending.clear()
        supported = false
        lastReachable = null
    }

    private fun attachListeners() {
        val messages = MessageClient.OnMessageReceivedListener { event -> onMessage(event) }
        messageClient?.addListener(messages)
        messageListener = messages

        val data = DataClient.OnDataChangedListener { buffer -> onDataChanged(buffer) }
        dataClient?.addListener(data)
        dataListener = data

        val capability = CapabilityClient.OnCapabilityChangedListener { info ->
            applyNodes(info.nodes)
        }
        capabilityClient?.addListener(capability, peerCapability())
        capabilityListener = capability
    }

    private fun detachListeners() {
        messageListener?.let { messageClient?.removeListener(it) }
        dataListener?.let { dataClient?.removeListener(it) }
        capabilityListener?.let { capabilityClient?.removeListener(it) }
        messageListener = null
        dataListener = null
        capabilityListener = null
    }

    // MARK: - Methods

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(statusMap())
            "sendMessage" -> sendMessage(call.arguments, result)
            "transferUserInfo" -> transferUserInfo(call.arguments, result)
            "outstandingTransfers" -> outstandingTransfers(result)
            "cancelTransfers" -> cancelTransfers(call.arguments, result)
            else -> result.notImplemented()
        }
    }

    /**
     * What the link can say about the peer right now.
     *
     * Android has no equivalent of `WCSession.isPaired`, so the honest mapping
     * is: a peer that has declared our capability is **paired** (an install
     * declares it, so this needs no launch from the other device), and a peer
     * that is also `isNearby` is **reachable**, which is the state a message can
     * actually be carried in. `appInstalled` is the capability's own meaning.
     */
    private fun statusMap(): Map<String, Any?> = mapOf(
        "supported" to supported,
        "paired" to (peerNodeId != null),
        "appInstalled" to (peerNodeId != null),
        "activated" to supported,
        "reachable" to (peerNodeId != null && peerNearby),
    )

    private fun peerCapability(): String =
        if (isWatch) PHONE_CAPABILITY else WATCH_CAPABILITY

    private fun ownRole(): String = if (isWatch) ROLE_WATCH else ROLE_PHONE

    private fun failure(code: String, message: String? = null): LinkFailure =
        LinkFailure(code, message)


    /**
     * Reads the pairing afresh: the capability first (it names the peers that
     * have our app), the connected nodes as the fallback for an install that
     * predates the capability.
     */
    private fun resolvePeer() {
        val client = capabilityClient ?: return
        client.getCapability(peerCapability(), CapabilityClient.FILTER_ALL)
            .addOnSuccessListener { info ->
                if (info.nodes.isEmpty()) {
                    connectedPeers()
                } else {
                    applyNodes(info.nodes)
                }
            }
            .addOnFailureListener { connectedPeers() }
    }

    private fun connectedPeers() {
        nodeClient?.connectedNodes
            ?.addOnSuccessListener { nodes -> applyNodes(nodes.toSet()) }
            ?.addOnFailureListener { applyNodes(emptySet()) }
    }

    private fun applyNodes(nodes: Set<Node>) {
        main.post {
            val nearby = nodes.firstOrNull { it.isNearby } ?: nodes.firstOrNull()
            peerNodeId = nearby?.id
            peerNearby = nearby?.isNearby == true
            reportReachability(peerNodeId != null && peerNearby)
            emitState()
        }
    }

    private fun sendMessage(arguments: Any?, result: MethodChannel.Result) {
        if (!supported) return result.error(failure("not_supported"))

        val frame = frameArgument(arguments)
            ?: return result.error(failure("send_failed", "the frame is not a dictionary"))
        val bytes = encodeFrame(frame)

        if (bytes.size > MAX_FRAME_BYTES) {
            return result.error(
                failure(
                    "send_failed",
                    "the frame is ${bytes.size} bytes; the Wear data layer carries at most " +
                        "$MAX_FRAME_BYTES in one message",
                )
            )
        }

        val nodeId = peerNodeId
        if (nodeId == null || !peerNearby) {
            return result.error(failure("not_reachable"))
        }

        messageClient?.sendMessage(nodeId, FRAME_PATH, bytes)
            ?.addOnSuccessListener { main.post { result.success(null) } }
            ?.addOnFailureListener { error ->
                main.post {
                    result.error(failure("send_failed", error.message ?: error.toString()))
                }
            }
            ?: result.error(failure("not_supported"))
    }

    /**
     * Hands the peer one frame the data layer carries later: one data item at
     * the frame's `messageId`. A frame whose id already waits is answered
     * `already_queued` rather than written twice.
     */
    private fun transferUserInfo(arguments: Any?, result: MethodChannel.Result) {
        if (!supported) return result.error(failure("not_supported"))

        val frame = frameArgument(arguments)
            ?: return result.error(failure("send_failed", "the frame is not a dictionary"))
        val messageId = frame[KEY_MESSAGE_ID] as? String
            ?: return result.error(
                failure("send_failed", "the frame has no messageId to queue under")
            )
        val bytes = encodeFrame(frame)
        if (bytes.size > MAX_FRAME_BYTES) {
            return result.error(
                failure(
                    "send_failed",
                    "the frame is ${bytes.size} bytes; the Wear data layer carries at most " +
                        "$MAX_FRAME_BYTES in one data item",
                )
            )
        }

        val client = dataClient ?: return result.error(failure("not_supported"))
        client.dataItems.addOnCompleteListener { task ->
            val held = if (task.isSuccessful) task.result.toList().map { it.uri } else emptyList()
            val path = QUEUE_PREFIX + messageId
            val already = held.any { it.path == path }
            if (already) {
                main.post { result.success("already_queued") }
                return@addOnCompleteListener
            }
            val request = PutDataRequest.create(path).setData(dataMapFor(frame, messageId, bytes).toByteArray())
            client.putDataItem(request)
                .addOnSuccessListener { main.post { result.success("queued") } }
                .addOnFailureListener { error ->
                    main.post {
                        result.error(failure("send_failed", error.message ?: error.toString()))
                    }
                }
        }
    }

    private fun dataMapFor(
        frame: Map<String, Any?>,
        messageId: String,
        bytes: ByteArray,
    ): DataMap {
        val map = DataMap()
        map.putString(KEY_MESSAGE_ID, messageId)
        map.putString(KEY_ROLE, ownRole())
        map.putByteArray(KEY_FRAME, bytes)
        (frame[KEY_TYPE] as? String)?.let { map.putString(KEY_TYPE, it) }
        (frame[KEY_SESSION_ID] as? String)?.let { map.putString(KEY_SESSION_ID, it) }
        (changeIdOf(frame))?.let { map.putString(KEY_CHANGE_ID, it) }
        return map
    }

    /**
     * The frames this device queued and the peer has not taken: a data item is
     * gone once either side deletes it, so what is still there is still owed.
     */
    private fun outstandingTransfers(result: MethodChannel.Result) {
        if (!supported) return result.error(failure("not_supported"))
        val client = dataClient ?: return result.error(failure("not_supported"))

        client.dataItems.addOnCompleteListener { task ->
            val entries = mutableListOf<Map<String, Any?>>()
            if (task.isSuccessful) {
                for (item in task.result) {
                    val path = item.uri.path ?: continue
                    if (!path.startsWith(QUEUE_PREFIX)) continue
                    val bytes = item.data ?: continue
                    val map = runCatching { DataMap.fromByteArray(bytes) }.getOrNull() ?: continue
                    if (map.getString(KEY_ROLE) != ownRole()) continue
                    val messageId = map.getString(KEY_MESSAGE_ID) ?: continue
                    val entry = mutableMapOf<String, Any?>(
                        KEY_MESSAGE_ID to messageId,
                        KEY_TYPE to (map.getString(KEY_TYPE) ?: ""),
                    )
                    map.getString(KEY_SESSION_ID)?.let { entry[KEY_SESSION_ID] = it }
                    map.getString(KEY_CHANGE_ID)?.let { entry[KEY_CHANGE_ID] = it }
                    entries.add(entry)
                }
            }
            main.post { result.success(entries) }
        }
    }

    /** Cancels the waiting frames whose id is in `messageIds`; answers how many. */
    private fun cancelTransfers(arguments: Any?, result: MethodChannel.Result) {
        val ids = ((arguments as? Map<*, *>)?.get("messageIds") as? List<*>)
            ?.filterIsInstance<String>()
            .orEmpty()
        if (ids.isEmpty()) return result.success(0)
        if (!supported) return result.error(failure("not_supported"))
        val client = dataClient ?: return result.error(failure("not_supported"))

        client.dataItems.addOnCompleteListener { task ->
            val wanted = ids.toSet()
            val uris = mutableListOf<Uri>()
            if (task.isSuccessful) {
                for (item in task.result) {
                    val path = item.uri.path ?: continue
                    if (!path.startsWith(QUEUE_PREFIX)) continue
                    val bytes = item.data ?: continue
                    val map = runCatching { DataMap.fromByteArray(bytes) }.getOrNull() ?: continue
                    if (map.getString(KEY_ROLE) != ownRole()) continue
                    val messageId = map.getString(KEY_MESSAGE_ID) ?: continue
                    if (wanted.contains(messageId)) uris.add(item.uri)
                }
            }
            var outstanding = uris.size
            if (outstanding == 0) {
                main.post { result.success(0) }
                return@addOnCompleteListener
            }
            var cancelled = 0
            for (uri in uris) {
                client.deleteDataItems(uri).addOnCompleteListener {
                    outstanding -= 1
                    if (it.isSuccessful) cancelled += 1
                    if (outstanding == 0) main.post { result.success(cancelled) }
                }
            }
        }
    }

    // MARK: - Arrivals

    private fun onMessage(event: MessageEvent) {
        if (event.path != FRAME_PATH) return
        val frame = decodeFrame(event.data) ?: return
        emit(mapOf("kind" to "message", "frame" to frame))
    }

    /**
     * A queued frame has arrived. It is emitted first and deleted after, so a
     * frame the app takes is not offered again on the next change; the protocol
     * is idempotent, so a crash between the two costs a redelivery, not data.
     */
    private fun onDataChanged(buffer: DataEventBuffer) {
        try {
            for (event in buffer) {
                if (event.type != DataEvent.TYPE_CHANGED) continue
                val item = event.dataItem
                val path = item.uri.path ?: continue
                if (!path.startsWith(QUEUE_PREFIX)) continue
                val itemBytes = item.data ?: continue
                val map = runCatching { DataMap.fromByteArray(itemBytes) }.getOrNull() ?: continue
                if (map.getString(KEY_ROLE) == ownRole()) continue
                val frameBytes = map.getByteArray(KEY_FRAME) ?: continue
                val frame = decodeFrame(frameBytes) ?: continue
                val uri = item.uri
                emit(mapOf("kind" to "userInfo", "frame" to frame))
                dataClient?.deleteDataItems(uri)
            }
        } finally {
            buffer.release()
        }
    }

    // MARK: - Events

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink?) {
        sink = eventSink
        val waiting = pending.toList()
        pending.clear()
        for (event in waiting) eventSink?.success(event)
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun emit(event: Map<String, Any?>) {
        main.post {
            val current = sink
            if (current != null) {
                current.success(event)
                return@post
            }
            pending.addLast(event)
            while (pending.size > BUFFER_CAP) pending.removeFirst()
        }
    }

    private fun emitState() {
        val state = statusMap().toMutableMap()
        state["kind"] = "state"
        emit(state)
    }

    private fun reportReachability(reachable: Boolean) {
        main.post {
            if (lastReachable == reachable) return@post
            lastReachable = reachable
            emit(mapOf("kind" to "reachability", "reachable" to reachable))
        }
    }

    // MARK: - Frames

    /**
     * The frame a call carried, with its keys as strings — the codec hands
     * Dart's `Map<String, Object?>` over as a `Map<*, *>`.
     */
    private fun frameArgument(arguments: Any?): Map<String, Any?>? {
        val raw = arguments as? Map<*, *> ?: return null
        val frame = linkedMapOf<String, Any?>()
        for ((key, value) in raw) frame[key.toString()] = value
        return frame
    }

    private fun changeIdOf(frame: Map<String, Any?>): String? =
        (frame["payload"] as? Map<*, *>)?.get(KEY_CHANGE_ID) as? String

    private fun encodeFrame(frame: Map<*, *>): ByteArray =
        toJsonValue(frame).toString().toByteArray(Charsets.UTF_8)

    @Suppress("UNCHECKED_CAST")
    private fun decodeFrame(bytes: ByteArray): Map<String, Any?>? {
        val text = runCatching { String(bytes, Charsets.UTF_8) }.getOrNull() ?: return null
        val parsed = runCatching { JSONTokener(text).nextValue() }.getOrNull() ?: return null
        val value = fromJsonValue(parsed)
        return value as? Map<String, Any?>
    }

    /**
     * A frame as `org.json` sees it.
     *
     * `JSONObject(Map)` drops a null value, and the protocol uses an explicit
     * null (`{"rest": null}` clears a timer), so nulls are written as
     * `JSONObject.NULL` here rather than left to the map constructor.
     */
    private fun toJsonValue(value: Any?): Any = when (value) {
        null -> JSONObject.NULL
        is Map<*, *> -> {
            val json = JSONObject()
            for ((key, entry) in value) json.put(key.toString(), toJsonValue(entry))
            json
        }
        is Iterable<*> -> {
            val json = JSONArray()
            for (entry in value) json.put(toJsonValue(entry))
            json
        }
        is BooleanArray -> JSONArray(value.toList())
        is IntArray -> JSONArray(value.toList())
        is DoubleArray -> JSONArray(value.toList())
        is LongArray -> JSONArray(value.toList())
        is ByteArray -> JSONArray(value.toList())
        else -> value
    }

    /**
     * The reverse of [toJsonValue]: `JSONObject.NULL` becomes a real null, so a
     * frame arrives at Dart exactly as it left the sender.
     */
    private fun fromJsonValue(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> {
            val map = linkedMapOf<String, Any?>()
            for (key in value.keys()) map[key] = fromJsonValue(value.opt(key))
            map
        }
        is JSONArray -> {
            val list = mutableListOf<Any?>()
            for (index in 0 until value.length()) list.add(fromJsonValue(value.opt(index)))
            list
        }
        else -> value
    }
}

/**
 * A refusal, reported with the same codes the iOS half uses, so Dart's
 * `WatchLinkException` and everything above it are platform-blind:
 * `not_supported`, `not_reachable`, `send_failed`.
 */
private data class LinkFailure(val code: String, val message: String?)

/** Answers a call with [failure]. */
private fun MethodChannel.Result.error(failure: LinkFailure) {
    error(failure.code, failure.message, null)
}

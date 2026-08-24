package dev.dartloom.externalinput

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Parcelable
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.ArrayDeque
import java.util.UUID

/** Receives Android share and Open With intents as Dartloom input batches. */
class DartloomExternalInputPlugin : FlutterPlugin, ActivityAware, PluginRegistry.NewIntentListener,
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val EVENT_CHANNEL = "dev.dartloom.external_input/events"
        private const val METHOD_CHANNEL = "dev.dartloom.external_input/methods"
    }

    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private val pending = ArrayDeque<Map<String, Any?>>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(binding.binaryMessenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addOnNewIntentListener(this)
        handleIntent(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        handleIntent(intent)
        return false
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        flushPending()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePending" -> {
                val values = pending.toList()
                pending.clear()
                result.success(values)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null || !isExternalInputIntent(intent)) return
        val host = activity ?: return
        val items = mutableListOf<Map<String, Any?>>()
        intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            ?.takeIf(String::isNotBlank)
            ?.let { text ->
                val uri = Uri.parse(text)
                if (uri.scheme == "http" || uri.scheme == "https") {
                    items += mapOf("type" to "url", "url" to text)
                } else {
                    items += mapOf("type" to "text", "text" to text)
                }
            }
        if (intent.action == Intent.ACTION_VIEW &&
            (intent.data?.scheme == "http" || intent.data?.scheme == "https")) {
            items += mapOf("type" to "url", "url" to intent.data.toString())
        }
        attachmentUris(intent).forEach { uri ->
            copyAttachment(host, uri, intent.type)?.let(items::add)
        }
        if (items.isEmpty()) return
        deliver(
            mapOf(
                "items" to items,
                "source" to if (intent.action == Intent.ACTION_VIEW) "openWith" else "share",
            ),
        )
    }

    private fun isExternalInputIntent(intent: Intent): Boolean =
        intent.action == Intent.ACTION_SEND ||
            intent.action == Intent.ACTION_SEND_MULTIPLE ||
            intent.action == Intent.ACTION_VIEW

    @Suppress("DEPRECATION")
    private fun attachmentUris(intent: Intent): List<Uri> {
        val values = mutableListOf<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtra<Parcelable>(Intent.EXTRA_STREAM)
                ?.filterIsInstance<Uri>()
                ?.let(values::addAll)
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(values::add)
            if (intent.action == Intent.ACTION_VIEW &&
                intent.data?.scheme != "http" &&
                intent.data?.scheme != "https") {
                intent.data?.let(values::add)
            }
        }
        return values.distinct()
    }

    private fun copyAttachment(
        host: Activity,
        uri: Uri,
        intentMimeType: String?,
    ): Map<String, Any?>? = try {
        val identifier = UUID.randomUUID().toString()
        val directory = File(host.filesDir, "dartloom/external_input/$identifier")
        if (!directory.mkdirs() && !directory.isDirectory) return null
        val target = File(directory, "payload")
        host.contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use(input::copyTo)
        } ?: return null
        mapOf(
            "type" to "file",
            "path" to target.absolutePath,
            "name" to displayName(host, uri),
            "mimeType" to (host.contentResolver.getType(uri) ?: intentMimeType),
        )
    } catch (_: Exception) {
        null
    }

    private fun displayName(host: Activity, uri: Uri): String? {
        val cursor: Cursor = host.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        ) ?: return null
        cursor.use {
            return if (it.moveToFirst()) it.getString(0) else null
        }
    }

    private fun deliver(batch: Map<String, Any?>) {
        val sink = eventSink
        if (sink == null) {
            pending.addLast(batch)
        } else {
            sink.success(batch)
        }
    }

    private fun flushPending() {
        val sink = eventSink ?: return
        while (pending.isNotEmpty()) sink.success(pending.removeFirst())
    }
}

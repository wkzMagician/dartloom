package dev.dartloom.externalinput

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
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
import java.security.MessageDigest
import java.util.ArrayDeque
import java.util.UUID

/** Receives Android share, Open With, and explicit clipboard input batches. */
class DartloomExternalInputPlugin : FlutterPlugin,
    ActivityAware,
    PluginRegistry.NewIntentListener,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
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
        return isExternalInputIntent(intent)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takePending" -> {
                val values = pending.toList()
                pending.clear()
                result.success(values)
            }
            "readClipboard" -> result.success(
                readClipboard(call.argument<String>("afterChangeToken")),
            )
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        flushPending()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null || !isExternalInputIntent(intent)) return
        val host = activity ?: return
        val items = mutableListOf<Map<String, Any?>>()
        intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            ?.takeIf(String::isNotBlank)
            ?.let { items += inputForText(it) }
        if (intent.action == Intent.ACTION_VIEW && isWebUrl(intent.data)) {
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

    private fun readClipboard(afterChangeToken: String?): Map<String, Any?> {
        val host = activity
            ?: return mapOf("kind" to "unavailable", "reason" to "noForegroundActivity")
        return try {
            val clipboard = host.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
                ?: return mapOf("kind" to "unavailable", "reason" to "clipboardUnavailable")
            val clip = clipboard.primaryClip ?: return mapOf("kind" to "empty")
            val token = clipboardToken(clip)
            if (afterChangeToken == token) return mapOf("kind" to "unchanged")

            val mimeType = clip.description?.getMimeType(0)
            val items = mutableListOf<Map<String, Any?>>()
            for (index in 0 until clip.itemCount) {
                val item = clip.getItemAt(index)
                val uri = item.uri
                when {
                    uri != null && isWebUrl(uri) ->
                        items += mapOf("type" to "url", "url" to uri.toString())
                    uri != null -> copyAttachment(host, uri, mimeType)?.let(items::add)
                    item.text != null -> items += inputForText(item.text.toString())
                    else -> item.coerceToText(host)?.toString()
                        ?.takeIf(String::isNotBlank)
                        ?.let { items += inputForText(it) }
                }
            }
            if (items.isEmpty()) {
                mapOf("kind" to "empty", "changeToken" to token)
            } else {
                mapOf(
                    "kind" to "content",
                    "changeToken" to token,
                    "batch" to mapOf("items" to items, "source" to "clipboard"),
                )
            }
        } catch (_: Exception) {
            mapOf("kind" to "unavailable", "reason" to "clipboardReadFailed")
        }
    }

    private fun clipboardToken(clip: ClipData): String {
        val canonical = buildString {
            append(clip.description?.label ?: "")
            append('|')
            for (index in 0 until clip.itemCount) {
                val item = clip.getItemAt(index)
                append(item.text ?: "")
                append('|')
                append(item.uri ?: "")
                append('|')
                append(item.intent?.dataString ?: "")
                append('\u0000')
            }
        }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(canonical.toByteArray(Charsets.UTF_8))
        return digest.joinToString(separator = "") {
            "%02x".format(it.toInt() and 0xff)
        }
    }

    private fun inputForText(value: String): Map<String, Any?> {
        val trimmed = value.trim()
        val uri = Uri.parse(trimmed)
        return if (isWebUrl(uri)) {
            mapOf("type" to "url", "url" to trimmed)
        } else {
            mapOf("type" to "text", "text" to value)
        }
    }

    private fun isExternalInputIntent(intent: Intent): Boolean =
        intent.action == Intent.ACTION_SEND ||
            intent.action == Intent.ACTION_SEND_MULTIPLE ||
            intent.action == Intent.ACTION_VIEW

    private fun isWebUrl(uri: Uri?): Boolean =
        uri?.scheme?.lowercase() == "http" || uri?.scheme?.lowercase() == "https"

    @Suppress("DEPRECATION")
    private fun attachmentUris(intent: Intent): List<Uri> {
        val values = mutableListOf<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtra<Parcelable>(Intent.EXTRA_STREAM)
                ?.filterIsInstance<Uri>()
                ?.let(values::addAll)
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(values::add)
            if (intent.action == Intent.ACTION_VIEW && !isWebUrl(intent.data)) {
                intent.data?.let(values::add)
            }
        }
        return values.distinct()
    }

    private fun copyAttachment(
        host: Activity,
        uri: Uri,
        intentMimeType: String?,
    ): Map<String, Any?>? {
        return try {
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
                "name" to (displayName(host, uri) ?: uri.lastPathSegment),
                "mimeType" to (host.contentResolver.getType(uri) ?: intentMimeType),
            )
        } catch (_: Exception) {
            null
        }
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
        while (pending.isNotEmpty()) {
            sink.success(pending.removeFirst())
        }
    }
}

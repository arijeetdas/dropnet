package com.dropnet

import android.content.ContentUris
import android.content.ContentValues
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.storage.StorageManager
import android.os.storage.StorageVolume
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.media.MediaScannerConnection
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.ByteArrayOutputStream
import java.net.URLConnection
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
	companion object {
		private const val EXTRA_SHARE_HANDLED = "com.dropnet.extra.SHARE_HANDLED"
		private const val SHARED_IMPORTS_DIR = "shared_imports"
	}

	private val appsChannelName = "dropnet/android_apps"
	private val shareChannelName = "dropnet/share_intent"
	private val mediaStoreChannelName = "dropnet/media_store"
	private val androidStorageChannelName = "dropnet/android_storage"
	private val androidSafChannelName = "dropnet/android_saf"
	private val shortcutsChannelName = "dropnet/app_shortcuts"

	private var appsChannel: MethodChannel? = null
	private var shareChannel: MethodChannel? = null
	private var mediaStoreChannel: MethodChannel? = null
	private var androidStorageChannel: MethodChannel? = null
	private var androidSafChannel: MethodChannel? = null
	private var shortcutsChannel: MethodChannel? = null
	// Shared items waiting for Dart to pick them up, guarded by pendingSharedFilePaths.
	// Dart always *pulls* them through consumePendingSharedPayload; native only
	// signals "sharedPayloadAvailable". That single delivery path is what makes
	// cold-start shares reliable: whichever of Dart's startup consume or the
	// completion signal happens second still finds the items, and nothing is
	// ever delivered twice.
	private val pendingSharedFilePaths = mutableListOf<String>()
	private val pendingSharedTexts = mutableListOf<String>()
	// Number of share batches still being resolved/copied on shareExecutor.
	private var inFlightShareImports = 0
	// Shared items that could not be read or copied since Dart last asked,
	// so the app can say so instead of silently showing nothing.
	private var failedShareImports = 0
	private var pendingShortcut: String? = null
	private var pendingSafPickResult: MethodChannel.Result? = null
	private var pendingFilePickResult: MethodChannel.Result? = null
	private lateinit var openDocumentTreeLauncher: ActivityResultLauncher<Intent>
	private lateinit var filePickerLauncher: ActivityResultLauncher<Intent>
	private val mainThreadHandler = Handler(Looper.getMainLooper())
	private val appsExecutor = Executors.newSingleThreadExecutor()
	// content:// URIs (share sheet, media/audio picker) are copied into the
	// app's cache with a blocking stream read — for a large file that can take
	// long enough to trigger an ANR if done on the main thread, so it always
	// runs here instead.
	private val shareExecutor = Executors.newSingleThreadExecutor()

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		openDocumentTreeLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { activityResult ->
			val result = pendingSafPickResult
			pendingSafPickResult = null
			if (result == null) {
				return@registerForActivityResult
			}

			if (activityResult.resultCode != RESULT_OK) {
				result.success(null)
				return@registerForActivityResult
			}

			val uri = activityResult.data?.data
			if (uri == null) {
				result.success(null)
				return@registerForActivityResult
			}

			val flags = (activityResult.data?.flags ?: 0) and
				(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
			runCatching {
				contentResolver.takePersistableUriPermission(uri, flags)
			}

			val displayName = documentFileName(uri)
			result.success(
				mapOf(
					"uri" to uri.toString(),
					"name" to displayName,
				)
			)
		}
		filePickerLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { activityResult ->
			val result = pendingFilePickResult
			pendingFilePickResult = null
			if (result == null) {
				return@registerForActivityResult
			}

			if (activityResult.resultCode != RESULT_OK) {
				result.success(null)
				return@registerForActivityResult
			}

			val clipData = activityResult.data?.clipData
			val dataUri = activityResult.data?.data
			val uris = mutableListOf<Uri>()

			if (clipData != null) {
				for (i in 0 until clipData.itemCount) {
					clipData.getItemAt(i).uri?.let(uris::add)
				}
			} else if (dataUri != null) {
				uris.add(dataUri)
			}

			shareExecutor.execute {
				// One unreadable item must not throw away the whole selection
				// (or leave the Dart call waiting forever).
				val paths = uris.mapNotNull { uri -> safeResolveShareUri(uri) }
				mainThreadHandler.post {
					result.success(paths)
				}
			}
		}

		// Handle the launching share intent exactly once. A non-null
		// savedInstanceState means the activity is being recreated (process
		// death, a config change not covered by configChanges) with the *same*
		// intent, which was already imported the first time.
		if (savedInstanceState == null) {
			handleShareIntent(intent)
		}
	}

	/// Pressing back on the app's first screen used to finish this activity,
	/// throwing away the running app — including files already collected from
	/// earlier shares — so the next share started a fresh instance. Leaving
	/// the root screen now sends the app to the background instead (what
	/// Android 12+ already does for apps opened from the launcher), so the
	/// same instance keeps collecting files from every app you share from.
	override fun finish() {
		if (isTaskRoot && !isChangingConfigurations) {
			if (moveTaskToBack(true)) {
				return
			}
		}
		super.finish()
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		handleShareIntent(intent)
		handleShortcutIntent(intent, emitToFlutter = true)
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		val appsMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appsChannelName)
		appsChannel = appsMethodChannel
		appsMethodChannel
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"listInstalledApps" -> {
						val includeSystemApps = call.argument<Boolean>("includeSystemApps") ?: false
						appsExecutor.execute {
							try {
								val apps = listInstalledApps(includeSystemApps)
								mainThreadHandler.post {
									result.success(apps)
								}
							} catch (error: Exception) {
								mainThreadHandler.post {
									result.error(
										"LIST_APPS_FAILED",
										error.message ?: "Could not query installed apps",
										null
									)
								}
							}
						}
					}

					"inspectApk" -> {
						val path = call.argument<String>("path")?.trim().orEmpty()
						if (path.isEmpty()) {
							result.success(null)
						} else {
							appsExecutor.execute {
								val info = runCatching { inspectApkFile(path) }.getOrNull()
								mainThreadHandler.post {
									result.success(info)
								}
							}
						}
					}

					"installApk" -> {
						val path = call.argument<String>("path")?.trim().orEmpty()
						val installed = if (path.isEmpty()) false else runCatching { installApkFile(path) }.getOrDefault(false)
						result.success(installed)
					}

					else -> result.notImplemented()
				}
			}

		val shareMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
		shareChannel = shareMethodChannel
		shareMethodChannel
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"consumePendingSharedPayload" -> {
						val payload = synchronized(pendingSharedFilePaths) {
							val files = pendingSharedFilePaths.toList()
							val texts = pendingSharedTexts.toList()
							pendingSharedFilePaths.clear()
							pendingSharedTexts.clear()
							mapOf(
								"files" to files,
								"texts" to texts,
								// Tells Dart more items are still being copied in and
								// will be signalled through sharedPayloadAvailable.
								"importing" to (inFlightShareImports > 0),
								"failed" to failedShareImports,
							).also { failedShareImports = 0 }
						}
						result.success(payload)
					}

					"consumePendingSharedFiles" -> {
						val files = synchronized(pendingSharedFilePaths) {
							val snapshot = pendingSharedFilePaths.toList()
							pendingSharedFilePaths.clear()
							snapshot
						}
						result.success(files)
					}

					else -> result.notImplemented()
				}
			}

		val mediaStoreMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaStoreChannelName)
		mediaStoreChannel = mediaStoreMethodChannel
		mediaStoreMethodChannel
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"saveToGallery" -> {
						val path = call.argument<String>("path")?.trim().orEmpty()
						if (path.isEmpty()) {
							result.success(false)
							return@setMethodCallHandler
						}
						val saved = runCatching { saveFileToMediaStore(path) }.getOrDefault(false)
						result.success(saved)
					}

					"openFileExternally" -> {
						val path = call.argument<String>("path")?.trim().orEmpty()
						if (path.isEmpty()) {
							result.success(false)
							return@setMethodCallHandler
						}
						val opened = runCatching { openFileExternally(path) }.getOrDefault(false)
						result.success(opened)
					}

					"pickGalleryMedia" -> {
						android.util.Log.d("DropNetNative", "[DropNetNative] pickGalleryMedia invoked")
						if (pendingFilePickResult != null) {
							android.util.Log.w("DropNetNative", "[DropNetNative] pickGalleryMedia error: Another file picker is already open")
							result.error("PICK_IN_PROGRESS", "Another file picker is already open.", null)
							return@setMethodCallHandler
						}
						pendingFilePickResult = result
						try {
							var intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
								android.util.Log.d("DropNetNative", "[DropNetNative] Creating ACTION_PICK_IMAGES intent")
								Intent(MediaStore.ACTION_PICK_IMAGES).apply {
									putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, 100)
								}
							} else {
								android.util.Log.d("DropNetNative", "[DropNetNative] Creating ACTION_PICK intent")
								Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
									type = "image/*"
									putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
									putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
								}
							}
							android.util.Log.d("DropNetNative", "[DropNetNative] Launching media picker activity")
							filePickerLauncher.launch(intent)
						} catch (e: Exception) {
							android.util.Log.e("DropNetNative", "[DropNetNative] Error launching gallery picker: ${e.message}", e)
							try {
								android.util.Log.d("DropNetNative", "[DropNetNative] Falling back to ACTION_GET_CONTENT")
								val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
									type = "*/*"
									putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
									putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
								}
								filePickerLauncher.launch(intent)
							} catch (e2: Exception) {
								android.util.Log.e("DropNetNative", "[DropNetNative] Error launching fallback picker: ${e2.message}", e2)
								pendingFilePickResult = null
								result.error("LAUNCH_FAILED", "Failed to launch picker: ${e2.message}", null)
							}
						}
					}

					"pickAudio" -> {
						android.util.Log.d("DropNetNative", "[DropNetNative] pickAudio invoked")
						if (pendingFilePickResult != null) {
							android.util.Log.w("DropNetNative", "[DropNetNative] pickAudio error: Another file picker is already open")
							result.error("PICK_IN_PROGRESS", "Another file picker is already open.", null)
							return@setMethodCallHandler
						}
						pendingFilePickResult = result
						try {
							android.util.Log.d("DropNetNative", "[DropNetNative] Creating pickAudio ACTION_GET_CONTENT intent")
							val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
								type = "audio/*"
								putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*"))
								putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
								addCategory(Intent.CATEGORY_OPENABLE)
							}
							android.util.Log.d("DropNetNative", "[DropNetNative] Launching audio picker activity")
							filePickerLauncher.launch(intent)
						} catch (e: Exception) {
							android.util.Log.e("DropNetNative", "[DropNetNative] Error launching audio picker: ${e.message}", e)
							pendingFilePickResult = null
							result.error("LAUNCH_FAILED", "Failed to launch audio picker: ${e.message}", null)
						}
					}

					else -> result.notImplemented()
				}
			}

		val androidStorageMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, androidStorageChannelName)
		androidStorageChannel = androidStorageMethodChannel
		androidStorageMethodChannel
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"listStorageRoots" -> {
						val roots = runCatching { listStorageRoots() }.getOrDefault(emptyList())
						result.success(roots)
					}
					"getDeviceEnvironment" -> {
						result.success(
							mapOf(
								"isChromeOS" to isRunningOnChromeOS(),
								"manufacturer" to (Build.MANUFACTURER ?: ""),
								"brand" to (Build.BRAND ?: ""),
								"model" to (Build.MODEL ?: ""),
							)
						)
					}
					"getInstalledApkType" -> {
						val type = getInstalledApkType()
						result.success(type)
					}

					else -> result.notImplemented()
				}
			}

		val androidSafMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, androidSafChannelName)
		androidSafChannel = androidSafMethodChannel
		androidSafMethodChannel
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"pickDirectoryTree" -> {
						if (pendingSafPickResult != null) {
							result.error("PICK_IN_PROGRESS", "Another SAF picker is already open.", null)
							return@setMethodCallHandler
						}
						pendingSafPickResult = result
						val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
							addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
							addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
							addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
							addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
						}
						openDocumentTreeLauncher.launch(intent)
					}
					"listPersistedTrees" -> {
						result.success(listPersistedTrees())
					}
					"releasePersistedTree" -> {
						val uriString = call.argument<String>("uri")?.trim().orEmpty()
						if (uriString.isEmpty()) {
							result.success(false)
							return@setMethodCallHandler
						}
						val released = runCatching {
							val uri = Uri.parse(uriString)
							contentResolver.releasePersistableUriPermission(
								uri,
								Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
							)
							true
						}.getOrDefault(false)
						result.success(released)
					}
					"listTreeEntries" -> {
						val treeUri = call.argument<String>("treeUri")?.trim().orEmpty()
						val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
						val entries = runCatching { listTreeEntries(treeUri, relativePath) }.getOrDefault(emptyList())
						result.success(entries)
					}
					"existsInTree" -> {
						val treeUri = call.argument<String>("treeUri")?.trim().orEmpty()
						val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
						result.success(runCatching { resolveDocument(treeUri, relativePath, createDirs = false) != null }.getOrDefault(false))
					}
					"fileSizeInTree" -> {
						val treeUri = call.argument<String>("treeUri")?.trim().orEmpty()
						val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
						val size = runCatching {
							resolveDocument(treeUri, relativePath, createDirs = false)?.length() ?: -1L
						}.getOrDefault(-1L)
						result.success(size)
					}
					"modificationTimeInTree" -> {
						val treeUri = call.argument<String>("treeUri")?.trim().orEmpty()
						val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
						val modifiedAt = runCatching {
							resolveDocument(treeUri, relativePath, createDirs = false)?.lastModified() ?: 0L
						}.getOrDefault(0L)
						result.success(modifiedAt)
					}
					"readFileFromTree" -> {
						val treeUri = call.argument<String>("treeUri")?.trim().orEmpty()
						val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
						val bytes = runCatching {
							val doc = resolveDocument(treeUri, relativePath, createDirs = false)
							if (doc == null || doc.isDirectory) {
								null
							} else {
								contentResolver.openInputStream(doc.uri)?.use { input -> input.readBytes() }
							}
						}.getOrNull()
						result.success(bytes)
					}
					"writeFileToTree" -> {
						val treeUri = call.argument<String>("treeUri")?.trim().orEmpty()
						val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
						val bytes = call.argument<ByteArray>("bytes")
						if (bytes == null) {
							result.success(false)
							return@setMethodCallHandler
						}
						val wrote = runCatching {
							writeFileToTree(treeUri, relativePath, bytes)
						}.getOrDefault(false)
						result.success(wrote)
					}
					"createDirectoryInTree" -> {
						val treeUri = call.argument<String>("treeUri")?.trim().orEmpty()
						val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
						val ok = runCatching {
							resolveDocument(treeUri, relativePath, createDirs = true, directoryHint = true) != null
						}.getOrDefault(false)
						result.success(ok)
					}
					"deleteFromTree" -> {
						val treeUri = call.argument<String>("treeUri")?.trim().orEmpty()
						val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
						val ok = runCatching {
							resolveDocument(treeUri, relativePath, createDirs = false)?.delete() == true
						}.getOrDefault(false)
						result.success(ok)
					}
					"renameInTree" -> {
						val treeUri = call.argument<String>("treeUri")?.trim().orEmpty()
						val fromRelativePath = call.argument<String>("fromRelativePath")?.trim().orEmpty()
						val toName = call.argument<String>("toName")?.trim().orEmpty()
						if (toName.isEmpty()) {
							result.success(false)
							return@setMethodCallHandler
						}
						val ok = runCatching {
							val doc = resolveDocument(treeUri, fromRelativePath, createDirs = false)
							doc?.renameTo(toName) == true
						}.getOrDefault(false)
						result.success(ok)
					}
					else -> result.notImplemented()
				}
			}

		val shortcutsMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shortcutsChannelName)
		shortcutsChannel = shortcutsMethodChannel
		shortcutsMethodChannel
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"consumePendingShortcut" -> {
						val shortcut = pendingShortcut
						pendingShortcut = null
						result.success(shortcut)
					}
					else -> result.notImplemented()
				}
			}

		handleShortcutIntent(intent, emitToFlutter = false)
	}

	override fun onDestroy() {
		appsExecutor.shutdownNow()
		shareExecutor.shutdownNow()
		super.onDestroy()
	}

	private fun listPersistedTrees(): List<Map<String, Any?>> {
		val out = mutableListOf<Map<String, Any?>>()
		for (permission in contentResolver.persistedUriPermissions) {
			val uri = permission.uri
			if (uri == null) continue
			if (!permission.isReadPermission) continue
			val name = documentFileName(uri)
			out.add(
				mapOf(
					"uri" to uri.toString(),
					"name" to name,
					"read" to permission.isReadPermission,
					"write" to permission.isWritePermission,
				)
			)
		}
		return out
	}

	private fun listTreeEntries(treeUriString: String, relativePath: String): List<Map<String, Any?>> {
		val doc = resolveDocument(treeUriString, relativePath, createDirs = false)
		if (doc == null || !doc.isDirectory) {
			return emptyList()
		}
		return doc.listFiles().map { child ->
			mapOf(
				"name" to (child.name ?: ""),
				"isDirectory" to child.isDirectory,
				"size" to child.length(),
				"modifiedAt" to child.lastModified(),
			)
		}
	}

	private fun writeFileToTree(treeUriString: String, relativePath: String, bytes: ByteArray): Boolean {
		val normalized = relativePath.trim().replace("\\", "/").trim('/')
		if (normalized.isEmpty()) {
			return false
		}
		val segments = normalized.split('/').filter { it.isNotBlank() }
		if (segments.isEmpty()) {
			return false
		}

		val parentPath = segments.dropLast(1).joinToString("/")
		val fileName = segments.last()
		val parent = resolveDocument(treeUriString, parentPath, createDirs = true, directoryHint = true)
		if (parent == null || !parent.isDirectory) {
			return false
		}

		var file = parent.findFile(fileName)
		if (file == null || file.isDirectory) {
			file = parent.createFile("application/octet-stream", fileName)
		}
		if (file == null) {
			return false
		}

		contentResolver.openOutputStream(file.uri, "wt")?.use { output ->
			output.write(bytes)
			output.flush()
		} ?: return false

		return true
	}

	private fun resolveDocument(
		treeUriString: String,
		relativePath: String,
		createDirs: Boolean,
		directoryHint: Boolean = false,
	): DocumentFile? {
		if (treeUriString.isBlank()) {
			return null
		}
		val treeUri = Uri.parse(treeUriString)
		var current = DocumentFile.fromTreeUri(this, treeUri) ?: return null

		val normalized = relativePath.trim().replace("\\", "/").trim('/')
		if (normalized.isEmpty()) {
			return current
		}

		val segments = normalized.split('/').filter { it.isNotBlank() }
		for ((index, segment) in segments.withIndex()) {
			val isLast = index == segments.lastIndex
			val existing = current.findFile(segment)
			if (existing != null) {
				current = existing
				continue
			}
			if (!createDirs || (isLast && !directoryHint)) {
				return null
			}
			val created = current.createDirectory(segment) ?: return null
			current = created
		}

		return current
	}

	private fun documentFileName(uri: Uri): String {
		val document = DocumentFile.fromTreeUri(this, uri)
		val candidate = document?.name?.trim().orEmpty()
		if (candidate.isNotEmpty()) {
			return candidate
		}
		return uri.lastPathSegment?.trim().orEmpty().ifBlank { "Folder" }
	}

	private fun listStorageRoots(): List<Map<String, Any?>> {
		val output = mutableListOf<Map<String, Any?>>()
		val seen = mutableSetOf<String>()

		fun addRoot(path: String?, label: String, removable: Boolean, primary: Boolean, state: String) {
			val normalized = path?.trim().orEmpty()
			if (normalized.isEmpty()) return
			val file = File(normalized)
			if (!file.exists() || !file.isDirectory) return
			if (!seen.add(file.absolutePath)) return

			output.add(
				mapOf(
					"path" to file.absolutePath,
					"label" to label,
					"isRemovable" to removable,
					"isPrimary" to primary,
					"state" to state,
				)
			)
		}

		val storageManager = getSystemService(Context.STORAGE_SERVICE) as StorageManager
		for (volume in storageManager.storageVolumes) {
			val path = resolveStorageVolumePath(volume)
			val label = runCatching { volume.getDescription(this) }.getOrNull().orEmpty().ifBlank {
				if (volume.isPrimary) "Internal Storage" else "External Storage"
			}
			addRoot(path, label, volume.isRemovable, volume.isPrimary, volume.state ?: "unknown")
		}

		addRoot(Environment.getExternalStorageDirectory().absolutePath, "Internal Storage", false, true, Environment.MEDIA_MOUNTED)

		return output.sortedWith(compareBy<Map<String, Any?>>({ (it["isPrimary"] as? Boolean) != true }, { (it["path"] as? String).orEmpty().lowercase() }))
	}

	private fun resolveStorageVolumePath(volume: StorageVolume): String? {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
			return volume.directory?.absolutePath
		}

		val uuid = volume.uuid
		val primary = volume.isPrimary
		val candidates = applicationContext.getExternalFilesDirs(null)
		for (candidate in candidates) {
			if (candidate == null) continue
			val absolute = candidate.absolutePath
			val root = absolute.substringBefore("/Android/")
			if (root.isBlank()) continue

			if (primary && root.contains("/emulated/", ignoreCase = true)) {
				return root
			}
			if (!primary && !uuid.isNullOrBlank() && root.contains(uuid, ignoreCase = true)) {
				return root
			}
		}

		return null
	}

	private fun handleShortcutIntent(intent: Intent?, emitToFlutter: Boolean) {
		if (intent == null) {
			return
		}
		val shortcut = intent.getStringExtra("shortcut") ?: return
		intent.removeExtra("shortcut")
		if (emitToFlutter) {
			shortcutsChannel?.invokeMethod("shortcutTapped", shortcut)
		} else {
			pendingShortcut = shortcut
		}
	}

	private fun handleShareIntent(intent: Intent?) {
		if (intent == null) {
			return
		}
		val action = intent.action ?: return
		if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
			return
		}
		// Reopening the app from Recents re-delivers the original launch intent
		// (and its URI grants are usually gone by then), and the same Intent
		// object can reach this method twice (onCreate + a later onNewIntent
		// with setIntent). Import each share exactly once.
		if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) {
			return
		}
		if (intent.getBooleanExtra(EXTRA_SHARE_HANDLED, false)) {
			return
		}
		intent.putExtra(EXTRA_SHARE_HANDLED, true)

		val collectedUris = mutableListOf<Uri>()
		val collectedTexts = mutableListOf<String>()
		// Track URIs already processed from EXTRA_STREAM to avoid duplicating them
		// when the same URIs also appear in clipData (Android always mirrors EXTRA_STREAM
		// into clipData for compatibility, which would otherwise cause two file copies).
		val seenUris = mutableSetOf<Uri>()

		// Some senders put a Uri where a list is expected (or vice versa), or
		// ship extras that fail to unparcel; neither may abort the whole share.
		if (action == Intent.ACTION_SEND) {
			val uri = runCatching {
				if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
					intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
				} else {
					@Suppress("DEPRECATION")
					intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
				}
			}.getOrNull()
			if (uri != null && seenUris.add(uri)) {
				collectedUris.add(uri)
			}
		}

		if (action == Intent.ACTION_SEND_MULTIPLE) {
			val uris = runCatching {
				if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
					intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
				} else {
					@Suppress("DEPRECATION")
					intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
				}
			}.getOrNull()
			uris?.forEach { uri ->
				if (seenUris.add(uri)) {
					collectedUris.add(uri)
				}
			}
		}

		runCatching { intent.getStringExtra(Intent.EXTRA_TEXT) }.getOrNull()
			?.trim()
			?.takeIf { it.isNotEmpty() }
			?.let(collectedTexts::add)

		val clip = intent.clipData
		if (clip != null) {
			for (index in 0 until clip.itemCount) {
				val item = clip.getItemAt(index)
				item.uri?.let { uri ->
					// Skip URIs already handled via EXTRA_STREAM to prevent duplicate copies
					if (seenUris.add(uri)) {
						collectedUris.add(uri)
					}
				}
				val text = item.text?.toString()?.trim().orEmpty()
				if (text.isNotEmpty()) {
					collectedTexts.add(text)
				}
			}
		}

		val dedupedTexts = collectedTexts.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
		if (collectedUris.isEmpty() && dedupedTexts.isEmpty()) {
			return
		}

		if (collectedUris.isEmpty()) {
			addPendingSharedItems(emptyList(), dedupedTexts)
			notifySharedPayloadAvailable()
			return
		}

		synchronized(pendingSharedFilePaths) {
			inFlightShareImports++
		}
		// Lets Dart switch to the Send screen and show progress right away,
		// instead of sitting on the previous screen while a large file copies.
		runCatching {
			shareChannel?.invokeMethod("sharedImportStateChanged", mapOf("importing" to true))
		}

		// Resolving a content:// URI may copy its full contents into the app's
		// cache — done off the main thread so a large shared file can't block
		// the UI long enough to trigger an ANR.
		shareExecutor.execute {
			pruneStaleSharedImports()
			val results = collectedUris.map { uri -> safeResolveShareUri(uri) }
			val failures = results.count { it.isNullOrBlank() }
			val resolvedFiles = results
				.filterNotNull()
				.map { it.trim() }
				.filter { it.isNotEmpty() }
				.distinct()

			mainThreadHandler.post {
				synchronized(pendingSharedFilePaths) {
					inFlightShareImports = (inFlightShareImports - 1).coerceAtLeast(0)
					failedShareImports += failures
				}
				addPendingSharedItems(resolvedFiles, dedupedTexts)
				// Always signal, even when nothing could be read: Dart's consume
				// call also reports that importing has finished.
				notifySharedPayloadAvailable()
			}
		}
	}

	private fun addPendingSharedItems(files: List<String>, texts: List<String>) {
		synchronized(pendingSharedFilePaths) {
			for (path in files) {
				if (!pendingSharedFilePaths.contains(path)) {
					pendingSharedFilePaths.add(path)
				}
			}
			for (text in texts) {
				if (!pendingSharedTexts.contains(text)) {
					pendingSharedTexts.add(text)
				}
			}
		}
	}

	/// Tells Dart that shared items are waiting. If the Dart side isn't
	/// listening yet (cold start, engine still booting) the message is simply
	/// dropped and the items stay queued for the consume call Dart makes during
	/// startup — the previous "emit only when warm" logic lost exactly those.
	private fun notifySharedPayloadAvailable() {
		runCatching {
			shareChannel?.invokeMethod("sharedPayloadAvailable", null)
		}
	}

	private fun safeResolveShareUri(uri: Uri): String? {
		return try {
			resolveShareUriToPath(uri)
		} catch (error: Throwable) {
			android.util.Log.w("DropNetShare", "Could not import shared item $uri: ${error.message}")
			null
		}
	}

	/// Copies into shared_imports are only needed until the file has been
	/// sent; drop anything older than a day that isn't still queued.
	private fun pruneStaleSharedImports() {
		runCatching {
			val dir = File(cacheDir, SHARED_IMPORTS_DIR)
			val cutoff = System.currentTimeMillis() - 24L * 60L * 60L * 1000L
			val stillPending = synchronized(pendingSharedFilePaths) { pendingSharedFilePaths.toSet() }
			dir.listFiles()?.forEach { file ->
				if (file.lastModified() < cutoff && !stillPending.contains(file.absolutePath)) {
					file.deleteRecursively()
				}
			}
		}
	}

	private fun resolveShareUriToPath(uri: Uri): String? {
		return when (uri.scheme?.lowercase()) {
			"file" -> uri.path?.let(::File)?.takeIf { it.isFile && it.canRead() }?.absolutePath
			"content" -> resolveDirectFilePath(uri) ?: copyContentUriToCache(uri)
			else -> null
		}
	}

	/// Resolves a content:// URI straight to the real file already on disk,
	/// without duplicating it into the app's own storage — DropNet should read
	/// the sender's file directly wherever the OS lets it, only falling back to
	/// a cache copy (below) for genuinely virtual/remote content (e.g. a cloud
	/// file that isn't fully downloaded) where no real path exists at all.
	private fun resolveDirectFilePath(uri: Uri): String? {
		val path = try {
			when {
				DocumentsContract.isDocumentUri(applicationContext, uri) -> resolveDocumentUriPath(uri)
				uri.authority == MediaStore.AUTHORITY -> resolveMediaStoreUriPath(uri)
				else -> null
			}
		} catch (_: Exception) {
			null
		}
		val file = path?.let(::File)
		if (file != null && file.isFile && file.canRead()) {
			return file.absolutePath
		}
		return resolvePathFromDescriptor(uri)
	}

	/// Most apps (WhatsApp, file managers, galleries) share through their own
	/// FileProvider, whose URIs can't be mapped to a path by querying them.
	/// Their content is still an ordinary file on shared storage, though: open
	/// it and ask the kernel which file the descriptor points at. If that
	/// file is readable here (DropNet has all-files access) and has the same
	/// size, send it straight from where it is. Previously every such share
	/// was copied into the app's cache first, which for a multi-GB video took
	/// long enough to look stuck, and failed outright when the phone didn't
	/// have that much free space.
	private fun resolvePathFromDescriptor(uri: Uri): String? {
		return try {
			applicationContext.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
				val linked = android.system.Os.readlink("/proc/self/fd/${pfd.fd}")
				val file = File(normalizeStoragePath(linked))
				val expectedSize = pfd.statSize
				if (file.isFile && file.canRead() && (expectedSize < 0 || file.length() == expectedSize)) {
					file.absolutePath
				} else {
					null
				}
			}
		} catch (_: Throwable) {
			null
		}
	}

	/// The descriptor may be reported with a provider-side mount path; map it
	/// back to the /storage path this app can open.
	private fun normalizeStoragePath(path: String): String {
		Regex("^/mnt/(?:pass_through|user|runtime/[^/]+)/\\d+/(.+)$").find(path)?.let {
			return "/storage/${it.groupValues[1]}"
		}
		Regex("^/mnt/media_rw/(.+)$").find(path)?.let { return "/storage/${it.groupValues[1]}" }
		Regex("^/data/media/(\\d+)/(.+)$").find(path)?.let {
			return "/storage/emulated/${it.groupValues[1]}/${it.groupValues[2]}"
		}
		return path
	}

	private fun resolveDocumentUriPath(uri: Uri): String? {
		val docId = DocumentsContract.getDocumentId(uri)

		when (uri.authority) {
			"com.android.externalstorage.documents" -> {
				val parts = docId.split(":", limit = 2)
				if (parts.size != 2) return null
				val (volumeId, relativePath) = parts
				val root = if (volumeId.equals("primary", ignoreCase = true)) {
					Environment.getExternalStorageDirectory()
				} else {
					// Removable/secondary volumes: standard mount point on all
					// currently supported Android versions.
					File("/storage/$volumeId")
				}
				return File(root, relativePath).path
			}

			"com.android.providers.downloads.documents" -> {
				// Modern Android encodes the real path directly ("raw:/storage/...");
				// older versions need a MediaStore lookup by numeric row id instead.
				if (docId.startsWith("raw:")) {
					return docId.removePrefix("raw:")
				}
				val id = docId.toLongOrNull() ?: return null
				val contentUri = ContentUris.withAppendedId(
					Uri.parse("content://downloads/public_downloads"),
					id,
				)
				return queryDataColumn(contentUri)
			}

			"com.android.providers.media.documents" -> {
				val parts = docId.split(":", limit = 2)
				if (parts.size != 2) return null
				val (type, id) = parts
				val contentUri = when (type) {
					"image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
					"video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
					"audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
					else -> return null
				}
				return queryDataColumn(contentUri, "_id=?", arrayOf(id))
			}

			else -> return null
		}
	}

	private fun resolveMediaStoreUriPath(uri: Uri): String? = queryDataColumn(uri)

	private fun queryDataColumn(
		uri: Uri,
		selection: String? = null,
		selectionArgs: Array<String>? = null,
	): String? {
		val column = "_data"
		return applicationContext.contentResolver.query(
			uri,
			arrayOf(column),
			selection,
			selectionArgs,
			null,
		)?.use { cursor ->
			if (cursor.moveToFirst()) {
				val index = cursor.getColumnIndex(column)
				if (index >= 0) cursor.getString(index) else null
			} else {
				null
			}
		}
	}

	private fun copyContentUriToCache(uri: Uri): String? {
		val resolver = applicationContext.contentResolver
		val input = runCatching { resolver.openInputStream(uri) }.getOrNull()
			// Some providers only implement openAssetFile/openFile.
			?: runCatching { resolver.openAssetFileDescriptor(uri, "r")?.createInputStream() }.getOrNull()
			?: return null
		val displayName = runCatching { queryDisplayName(uri) }.getOrNull()
			?.trim()
			?.takeIf { it.isNotEmpty() }
			?: "shared_${System.currentTimeMillis()}"
		var safeName = displayName.replace(Regex("[^a-zA-Z0-9._-]+"), "_")
		// Several apps (WhatsApp documents, Telegram, some galleries) report a
		// name without an extension; derive one from the MIME type so the
		// receiver can still recognise and open the file.
		if (!safeName.contains('.')) {
			val mimeType = runCatching { resolver.getType(uri) }.getOrNull()
			val extension = mimeType?.let {
				android.webkit.MimeTypeMap.getSingleton().getExtensionFromMimeType(it)
			}
			if (!extension.isNullOrBlank()) {
				safeName = "$safeName.$extension"
			}
		}
		val targetDir = File(cacheDir, SHARED_IMPORTS_DIR).apply { mkdirs() }
		// Fail fast instead of filling the disk and dying halfway through.
		val declaredSize = runCatching { querySize(uri) }.getOrNull()
		if (declaredSize != null && declaredSize > 0 &&
			targetDir.usableSpace < declaredSize + 64L * 1024L * 1024L
		) {
			input.close()
			throw java.io.IOException("Not enough free storage to import $displayName")
		}
		var target = File(targetDir, safeName)
		if (target.exists()) {
			val dotIndex = safeName.lastIndexOf('.')
			val stem = if (dotIndex > 0) safeName.substring(0, dotIndex) else safeName
			val ext = if (dotIndex > 0) safeName.substring(dotIndex) else ""
			var counter = 2
			while (target.exists()) {
				target = File(targetDir, "${stem}_$counter$ext")
				counter++
			}
		}

		return try {
			input.use { source ->
				target.outputStream().use { out ->
					source.copyTo(out)
				}
			}
			target.absolutePath
		} catch (error: Throwable) {
			// Never leave a truncated file behind that could be picked up later.
			target.delete()
			throw error
		}
	}

	private fun querySize(uri: Uri): Long? {
		applicationContext.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
			if (cursor.moveToFirst()) {
				val index = cursor.getColumnIndex(OpenableColumns.SIZE)
				if (index >= 0 && !cursor.isNull(index)) {
					return cursor.getLong(index)
				}
			}
		}
		return null
	}

	private fun queryDisplayName(uri: Uri): String? {
		val resolver = applicationContext.contentResolver
		val projection = arrayOf(OpenableColumns.DISPLAY_NAME)
		var cursor: Cursor? = null
		return try {
			cursor = resolver.query(uri, projection, null, null, null)
			if (cursor != null && cursor.moveToFirst()) {
				val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
				if (nameIndex >= 0) cursor.getString(nameIndex) else null
			} else {
				null
			}
		} finally {
			cursor?.close()
		}
	}

	private fun saveFileToMediaStore(path: String): Boolean {
		val source = File(path)
		if (!source.exists() || !source.isFile) {
			return false
		}

		val mimeType = URLConnection.guessContentTypeFromName(source.name)?.lowercase() ?: "application/octet-stream"
		val isImage = mimeType.startsWith("image/")
		val isVideo = mimeType.startsWith("video/")
		if (!isImage && !isVideo) {
			return false
		}

		val scanCompleted = java.util.concurrent.CountDownLatch(1)
		var scanSuccess = false
		MediaScannerConnection.scanFile(
			applicationContext,
			arrayOf(source.absolutePath),
			arrayOf(mimeType),
		) { _, uri ->
			scanSuccess = uri != null
			scanCompleted.countDown()
		}
		runCatching {
			scanCompleted.await()
		}
		return scanSuccess
	}

	private fun openFileExternally(path: String): Boolean {
		val source = File(path)
		if (!source.exists() || !source.isFile) {
			return false
		}

		val mimeType = URLConnection.guessContentTypeFromName(source.name)?.lowercase() ?: "*/*"
		val authority = "${applicationContext.packageName}.fileprovider"

		val contentUri = runCatching {
			FileProvider.getUriForFile(applicationContext, authority, source)
		}.getOrNull() ?: return false

		val intent = Intent(Intent.ACTION_VIEW).apply {
			setDataAndType(contentUri, mimeType)
			addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
		}

		val resolved = packageManager.queryIntentActivities(
			intent,
			PackageManager.MATCH_DEFAULT_ONLY,
		)
		if (resolved.isEmpty()) {
			return false
		}

		for (info in resolved) {
			val packageName = info.activityInfo?.packageName ?: continue
			runCatching {
				grantUriPermission(packageName, contentUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
			}
		}

		val chooserIntent = Intent.createChooser(intent, "Open with").apply {
			addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
		}
		startActivity(chooserIntent)
		return true
	}

	private fun listInstalledApps(includeSystemApps: Boolean): List<Map<String, Any?>> {
		val packageManager = applicationContext.packageManager
		val apps = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
		val output = mutableListOf<Map<String, Any?>>()

		for (appInfo in apps) {
			val isSystem = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
			if (!includeSystemApps && isSystem) {
				continue
			}

			val apkPath = appInfo.sourceDir ?: continue
			val appName = packageManager.getApplicationLabel(appInfo)?.toString()?.trim().orEmpty()
			val resolvedName = if (appName.isEmpty()) appInfo.packageName else appName
			val iconBytes = runCatching {
				drawableToPngBytes(packageManager.getApplicationIcon(appInfo))
			}.getOrNull()

			val apkFile = java.io.File(apkPath)
			val apkSize = if (apkFile.exists()) apkFile.length() else 0L
			val versionName = runCatching {
				packageManager.getPackageInfo(appInfo.packageName, 0).versionName ?: ""
			}.getOrElse { "" }

			output.add(
				mapOf(
					"name" to resolvedName,
					"packageName" to appInfo.packageName,
					"apkPath" to apkPath,
					"isSystemApp" to isSystem,
					"iconBytes" to iconBytes,
					"versionName" to versionName,
					"apkSize" to apkSize,
				)
			)
		}

		output.sortBy { (it["name"] as? String ?: "").lowercase() }
		return output
	}

	private fun inspectApkFile(path: String): Map<String, Any?>? {
		val apkFile = File(path)
		if (!apkFile.exists()) {
			return null
		}

		val packageManager = applicationContext.packageManager
		val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
			PackageManager.PackageInfoFlags.of(PackageManager.GET_META_DATA.toLong())
		} else null
		@Suppress("DEPRECATION")
		val packageInfo = if (flags != null) {
			packageManager.getPackageArchiveInfo(path, flags)
		} else {
			packageManager.getPackageArchiveInfo(path, PackageManager.GET_META_DATA)
		} ?: return null

		val appInfo = packageInfo.applicationInfo ?: return null
		// getPackageArchiveInfo doesn't populate sourceDir/publicSourceDir, so
		// the icon/label loaders below would otherwise fail or return a
		// generic placeholder.
		appInfo.sourceDir = path
		appInfo.publicSourceDir = path

		val appName = runCatching {
			packageManager.getApplicationLabel(appInfo)?.toString()?.trim()
		}.getOrNull()?.takeIf { it.isNotEmpty() } ?: packageInfo.packageName

		// PackageManager.getApplicationIcon()/ApplicationInfo.loadIcon() silently
		// substitutes the generic Android icon whenever it can't resolve the
		// real one — which happens more often than expected for an *archived*
		// (not-yet-installed) APK, especially adaptive icons that need the
		// foreground/background layers resolved through the APK's own Resources.
		// Resolving the icon resource explicitly avoids that silent fallback so
		// a real failure can actually be told apart from success.
		val icon = runCatching {
			val res = packageManager.getResourcesForApplication(appInfo)
			if (appInfo.icon != 0) res.getDrawable(appInfo.icon, null) else null
		}.getOrNull() ?: runCatching { packageManager.getApplicationIcon(appInfo) }.getOrNull()

		val iconBytes = icon?.let { runCatching { drawableToPngBytes(it) }.getOrNull() }

		val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
			packageInfo.longVersionCode
		} else {
			@Suppress("DEPRECATION")
			packageInfo.versionCode.toLong()
		}

		val minSdkVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
			appInfo.minSdkVersion
		} else {
			-1
		}

		val installed = runCatching { packageManager.getPackageInfo(packageInfo.packageName, 0) }.getOrNull()
		val installedVersionCode = installed?.let {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
				it.longVersionCode
			} else {
				@Suppress("DEPRECATION")
				it.versionCode.toLong()
			}
		}

		return mapOf(
			"packageName" to packageInfo.packageName,
			"appName" to appName,
			"versionName" to (packageInfo.versionName ?: ""),
			"versionCode" to versionCode,
			"apkSize" to apkFile.length(),
			"minSdkVersion" to minSdkVersion,
			"deviceSdkVersion" to Build.VERSION.SDK_INT,
			"iconBytes" to iconBytes,
			"isInstalled" to (installed != null),
			"installedVersionName" to installed?.versionName,
			"installedVersionCode" to installedVersionCode,
			"isOwnPackage" to (packageInfo.packageName == applicationContext.packageName),
		)
	}

	private fun installApkFile(path: String): Boolean {
		val source = File(path)
		if (!source.exists() || !source.isFile) {
			return false
		}

		val authority = "${applicationContext.packageName}.fileprovider"
		val contentUri = runCatching {
			FileProvider.getUriForFile(applicationContext, authority, source)
		}.getOrNull() ?: return false

		val intent = Intent(Intent.ACTION_VIEW).apply {
			setDataAndType(contentUri, "application/vnd.android.package-archive")
			addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
		}

		val resolved = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
		if (resolved.isEmpty()) {
			return false
		}
		for (info in resolved) {
			val packageName = info.activityInfo?.packageName ?: continue
			runCatching {
				grantUriPermission(packageName, contentUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
			}
		}

		return runCatching {
			startActivity(intent)
			true
		}.getOrDefault(false)
	}

	private fun drawableToPngBytes(drawable: Drawable): ByteArray {
		val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 96
		val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 96
		val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
		val canvas = Canvas(bitmap)
		drawable.setBounds(0, 0, canvas.width, canvas.height)
		drawable.draw(canvas)
		val stream = ByteArrayOutputStream()
		bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
		return stream.toByteArray()
	}

	/// True when this APK runs on a Chromebook through ChromeOS's Android
	/// runtime (ARC++ or ARCVM). "org.chromium.arc" is the system feature
	/// ChromeOS declares for its Android container (the check Google documents
	/// for detecting ChromeOS); "org.chromium.arc.device_management" is present
	/// on the same devices. ARC builds also use a "cheets" device name, kept as
	/// a fallback for images that don't expose the features.
	private fun isRunningOnChromeOS(): Boolean {
		val pm = packageManager
		if (runCatching { pm.hasSystemFeature("org.chromium.arc") }.getOrDefault(false)) return true
		if (runCatching { pm.hasSystemFeature("org.chromium.arc.device_management") }.getOrDefault(false)) return true
		val device = Build.DEVICE.orEmpty()
		return device.matches(Regex(".+_cheets|cheets_.+"))
	}

	private fun getInstalledApkType(): String {
		try {
			val apkPath = applicationInfo.sourceDir ?: return "unknown"
			val zipFile = java.util.zip.ZipFile(apkPath)
			val entries = zipFile.entries()
			val abisSeen = mutableSetOf<String>()
			while (entries.hasMoreElements()) {
				val entry = entries.nextElement()
				val name = entry.name
				if (name.startsWith("lib/")) {
					val parts = name.split("/")
					if (parts.size > 2) {
						val abi = parts[1]
						abisSeen.add(abi)
					}
				}
			}
			zipFile.close()

			val standardAbis = abisSeen.filter { it in setOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64") }
			if (standardAbis.size > 1) {
				return "universal"
			} else if (standardAbis.size == 1) {
				return when (val abi = standardAbis.first()) {
					"arm64-v8a" -> "arm-v8a"
					"armeabi-v7a" -> "arm-v7a"
					else -> abi
				}
			}
		} catch (e: Exception) {
			// fallback
		}

		try {
			val nativeLibDir = applicationInfo.nativeLibraryDir
			if (!nativeLibDir.isNullOrEmpty()) {
				if (nativeLibDir.contains("arm64")) {
					return "arm-v8a"
				} else if (nativeLibDir.contains("arm") || nativeLibDir.contains("armeabi")) {
					return "arm-v7a"
				} else if (nativeLibDir.contains("x86_64")) {
					return "x86_64"
				} else if (nativeLibDir.contains("x86")) {
					return "x86"
				}
			}
		} catch (e: Exception) {
			// fallback
		}
		return "universal"
	}
}

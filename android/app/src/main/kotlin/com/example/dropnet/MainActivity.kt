package com.example.dropnet

import android.content.ContentValues
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
import androidx.documentfile.provider.DocumentFile
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.ByteArrayOutputStream
import java.net.URLConnection
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
	private val appsChannelName = "dropnet/android_apps"
	private val shareChannelName = "dropnet/share_intent"
	private val mediaStoreChannelName = "dropnet/media_store"
	private val androidStorageChannelName = "dropnet/android_storage"
	private val androidSafChannelName = "dropnet/android_saf"

	private var appsChannel: MethodChannel? = null
	private var shareChannel: MethodChannel? = null
	private var mediaStoreChannel: MethodChannel? = null
	private var androidStorageChannel: MethodChannel? = null
	private var androidSafChannel: MethodChannel? = null
	private val pendingSharedFilePaths = mutableListOf<String>()
	private var pendingSafPickResult: MethodChannel.Result? = null
	private lateinit var openDocumentTreeLauncher: ActivityResultLauncher<Intent>
	private val mainThreadHandler = Handler(Looper.getMainLooper())
	private val appsExecutor = Executors.newSingleThreadExecutor()

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
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		setIntent(intent)
		handleShareIntent(intent, emitToFlutter = true)
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

					else -> result.notImplemented()
				}
			}

		val shareMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
		shareChannel = shareMethodChannel
		shareMethodChannel
			.setMethodCallHandler { call, result ->
				when (call.method) {
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

		handleShareIntent(intent, emitToFlutter = false)
	}

	override fun onDestroy() {
		appsExecutor.shutdownNow()
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

	private fun handleShareIntent(intent: Intent?, emitToFlutter: Boolean) {
		if (intent == null) {
			return
		}
		val action = intent.action ?: return
		if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
			return
		}

		val collected = mutableListOf<String>()
		if (action == Intent.ACTION_SEND) {
			val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
				intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
			} else {
				@Suppress("DEPRECATION")
				intent.getParcelableExtra(Intent.EXTRA_STREAM)
			}
			if (uri != null) {
				resolveShareUriToPath(uri)?.let(collected::add)
			}
		}

		if (action == Intent.ACTION_SEND_MULTIPLE) {
			val uris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
				intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
			} else {
				@Suppress("DEPRECATION")
				intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
			}
			uris?.forEach { uri ->
				resolveShareUriToPath(uri)?.let(collected::add)
			}
		}

		val deduped = collected.distinct()
		if (deduped.isEmpty()) {
			return
		}

		synchronized(pendingSharedFilePaths) {
			pendingSharedFilePaths.addAll(deduped)
		}

		if (emitToFlutter) {
			shareChannel?.invokeMethod("sharedFilesUpdated", deduped)
		}
	}

	private fun resolveShareUriToPath(uri: Uri): String? {
		return when (uri.scheme?.lowercase()) {
			"file" -> uri.path
			"content" -> copyContentUriToCache(uri)
			else -> null
		}
	}

	private fun copyContentUriToCache(uri: Uri): String? {
		val resolver = applicationContext.contentResolver
		val input = resolver.openInputStream(uri) ?: return null
		val displayName = queryDisplayName(uri) ?: "shared_${System.currentTimeMillis()}"
		val safeName = displayName.replace(Regex("[^a-zA-Z0-9._-]+"), "_")
		val targetDir = File(cacheDir, "shared_imports").apply { mkdirs() }
		val target = File(targetDir, "${System.currentTimeMillis()}_$safeName")

		input.use { source ->
			target.outputStream().use { out ->
				source.copyTo(out)
			}
		}
		return target.absolutePath
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

		val resolver = applicationContext.contentResolver
		val now = System.currentTimeMillis()
		val values = ContentValues().apply {
			put(MediaStore.MediaColumns.DISPLAY_NAME, source.name)
			put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				put(MediaStore.MediaColumns.RELATIVE_PATH, if (isImage) Environment.DIRECTORY_PICTURES else Environment.DIRECTORY_MOVIES)
				put(MediaStore.MediaColumns.IS_PENDING, 1)
			}
			put(MediaStore.MediaColumns.DATE_ADDED, now / 1000)
			put(MediaStore.MediaColumns.DATE_MODIFIED, now / 1000)
		}

		val collection = when {
			isImage -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
			isVideo -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
			else -> MediaStore.Files.getContentUri("external")
		}

		val targetUri = resolver.insert(collection, values) ?: return false
		return try {
			resolver.openOutputStream(targetUri)?.use { output ->
				source.inputStream().use { input ->
					input.copyTo(output)
				}
			} ?: return false

			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				val done = ContentValues().apply {
					put(MediaStore.MediaColumns.IS_PENDING, 0)
				}
				resolver.update(targetUri, done, null, null)
			}
			true
		} catch (error: Exception) {
			resolver.delete(targetUri, null, null)
			false
		}
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

			output.add(
				mapOf(
					"name" to resolvedName,
					"packageName" to appInfo.packageName,
					"apkPath" to apkPath,
					"isSystemApp" to isSystem,
					"iconBytes" to iconBytes,
				)
			)
		}

		output.sortBy { (it["name"] as? String ?: "").lowercase() }
		return output
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
}

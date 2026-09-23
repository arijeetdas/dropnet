package com.dropnet

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log

/**
 * The only entry point for the system share sheet.
 *
 * The share sheet starts its target inside (or next to) the *sending* app's
 * task, so when MainActivity itself received shares, each app you shared from
 * could end up with its own MainActivity — each with its own Flutter engine,
 * app state and Recents entry, and files shared from different apps never
 * met. This invisible activity instead hands every share to the one
 * MainActivity (launchMode="singleTask"), which receives it through
 * onNewIntent when it is already running, then closes itself. It keeps no
 * UI, no history and no Recents entry.
 */
class ShareReceiverActivity : Activity() {
	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		val incoming = intent
		// Recreated (savedInstanceState != null) or reopened from history: the
		// share was already forwarded the first time.
		if (incoming != null &&
			savedInstanceState == null &&
			(incoming.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0
		) {
			runCatching { forwardToMainActivity(incoming) }
				.onFailure { Log.w("DropNetShare", "Could not forward share: ${it.message}") }
		}
		if (Build.VERSION.SDK_INT >= 34) {
			overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
		}
		finish()
		if (Build.VERSION.SDK_INT < 34) {
			@Suppress("DEPRECATION")
			overridePendingTransition(0, 0)
		}
	}

	private fun forwardToMainActivity(incoming: Intent) {
		val forward = Intent(incoming).apply {
			setClass(this@ShareReceiverActivity, MainActivity::class.java)
			// Drop launch flags that were meant for this trampoline (for
			// example NEW_DOCUMENT / MULTIPLE_TASK from some share sheets,
			// which would ask for yet another task).
			flags = 0
			addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			// This activity was granted read access to the shared content;
			// pass that grant on so MainActivity can read it. Grants only
			// travel with the intent's data/ClipData, so make sure every
			// shared URI is in the ClipData.
			addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
			clipData = buildClipData(incoming)
		}
		startActivity(forward)
	}

	private fun buildClipData(incoming: Intent): ClipData? {
		val items = mutableListOf<ClipData.Item>()
		val seen = mutableSetOf<Uri>()

		incoming.clipData?.let { clip ->
			for (index in 0 until clip.itemCount) {
				val item = clip.getItemAt(index)
				item.uri?.let(seen::add)
				items.add(item)
			}
		}
		for (uri in streamUris(incoming)) {
			if (seen.add(uri)) {
				items.add(ClipData.Item(uri))
			}
		}
		if (items.isEmpty()) {
			return null
		}
		val clip = ClipData("DropNet share", arrayOf("*/*"), items.first())
		for (item in items.drop(1)) {
			clip.addItem(item)
		}
		return clip
	}

	private fun streamUris(incoming: Intent): List<Uri> {
		return when (incoming.action) {
			Intent.ACTION_SEND -> listOfNotNull(
				runCatching {
					if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
						incoming.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
					} else {
						@Suppress("DEPRECATION")
						incoming.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
					}
				}.getOrNull()
			)
			Intent.ACTION_SEND_MULTIPLE -> runCatching {
				if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
					incoming.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
				} else {
					@Suppress("DEPRECATION")
					incoming.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
				}
			}.getOrNull().orEmpty()
			else -> emptyList()
		}
	}

}

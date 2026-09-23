package com.solusibejo.flutter_dynamic_icon_plus

import android.content.ComponentName
import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.ComponentInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log


object ComponentUtil {
    private fun enable(
        context: Context,
        packageManager: PackageManager,
        componentNameString: String,
    ) {
        val componentName = ComponentName(context, componentNameString)

        packageManager.setComponentEnabledSetting(
            componentName,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )
    }

    private fun disable(
        context: Context,
        packageManager: PackageManager,
        componentNameString: String,
    ) {
        val componentName = ComponentName(context, componentNameString)

        packageManager.setComponentEnabledSetting(
            componentName,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP
        )
    }

    fun packageInfo(context: Context): PackageInfo {
        val packageManager = context.packageManager
        val packageName = context.packageName
        val component = PackageManager.GET_ACTIVITIES or PackageManager.GET_DISABLED_COMPONENTS

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(
                component.toLong()))
        } else {
            @Suppress("DEPRECATION") packageManager.getPackageInfo(packageName,
                component
            )
        }
    }

    fun getCurrentEnabledAlias(context: Context): ActivityInfo? {
        val packageManager = context.packageManager
        val packageName = context.packageName
        return try {
            val info = packageInfo(context)
            var enabled: ActivityInfo? = null
            // Store activities in a local variable to make it safe for smart cast
            val activities = info.activities
            if (activities != null) {
                for (activityInfo in activities) {
                    // Only checks among the `activity-alias`s, for current enabled alias
                    if (activityInfo.targetActivity != null) {
                        val isEnabled: Boolean =
                            isComponentEnabled(context, packageManager, packageName, activityInfo.name)
                        if (isEnabled) enabled = activityInfo
                    }
                }
            }
            enabled
        } catch (e: PackageManager.NameNotFoundException) {
            e.printStackTrace()
            null
        }
    }

    private fun isComponentEnabled(context: Context, pm: PackageManager, pkgName: String?, clsName: String): Boolean {
        val componentName = ComponentName(pkgName!!, clsName)
        return when (pm.getComponentEnabledSetting(componentName)) {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT ->                 // We need to get the application info to get the component's default state
                try {
                    val packageInfo = packageInfo(context)
                    val components = ArrayList<ComponentInfo>()
                    if (packageInfo.activities != null) {
                        packageInfo.activities?.let { components.addAll(it) }
                    }

                    for (componentInfo in components) {
                        if (componentInfo.name == clsName) {
                            return componentInfo.isEnabled
                        }
                    }

                    // the component is not declared in the AndroidManifest
                    false
                } catch (e: PackageManager.NameNotFoundException) {
                    // the package isn't installed on the device
                    false
                }

            else -> try {
                val packageInfo = packageInfo(context)
                val components = ArrayList<ComponentInfo>()
                if (packageInfo.activities != null) {
                    packageInfo.activities?.let { components.addAll(it) }
                }
                for (componentInfo in components) {
                    if (componentInfo.name == clsName) {
                        return componentInfo.isEnabled
                    }
                }
                false
            } catch (e: PackageManager.NameNotFoundException) {
                false
            }
        }
    }

    fun changeAppIcon(context: Context, packageManager: PackageManager, packageName: String){
        // Repair installs hit by the old bug below, which could disable the
        // real launcher activity itself (leaving no way to open the app and
        // no share target). The alias switch needs it enabled anyway.
        ensureAliasTargetsEnabled(context, packageManager)

        val sp = context.getSharedPreferences(FlutterDynamicIconPlusPlugin.pluginName, Context.MODE_PRIVATE)
        val name = sp.getString(FlutterDynamicIconPlusPlugin.appIcon, null)
        Log.d("changeAppIcon", "Will Enabled: $name")
        if (name.isNullOrEmpty()) {
            return
        }
        setupIcon(context, packageManager, name)
    }

    fun removeCurrentAppIcon(context: Context){
        val sp = context.getSharedPreferences(FlutterDynamicIconPlusPlugin.pluginName, Context.MODE_PRIVATE)
        sp.edit()?.remove(FlutterDynamicIconPlusPlugin.appIcon)?.apply()
    }

    /// Names of every `<activity-alias>` in the manifest (enabled or not).
    private fun aliasNames(context: Context): List<String> {
        return try {
            packageInfo(context).activities
                ?.filter { it.targetActivity != null }
                ?.map { it.name }
                .orEmpty()
        } catch (e: PackageManager.NameNotFoundException) {
            emptyList()
        }
    }

    private fun ensureAliasTargetsEnabled(context: Context, packageManager: PackageManager) {
        val targets = try {
            packageInfo(context).activities
                ?.mapNotNull { it.targetActivity }
                ?.toSet()
                .orEmpty()
        } catch (e: PackageManager.NameNotFoundException) {
            emptySet()
        }
        for (target in targets) {
            val component = ComponentName(context.packageName, target)
            if (packageManager.getComponentEnabledSetting(component) ==
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED) {
                packageManager.setComponentEnabledSetting(
                    component,
                    PackageManager.COMPONENT_ENABLED_STATE_DEFAULT,
                    PackageManager.DONT_KILL_APP
                )
            }
        }
    }

    /// Enables exactly one launcher alias and disables every other alias.
    ///
    /// The previous version disabled only the alias it believed was current;
    /// when none was detected it disabled every activity *without* a
    /// targetActivity — i.e. the real MainActivity. It also left an extra
    /// alias enabled whenever its guess was wrong (two launcher icons).
    private fun setupIcon(context: Context, packageManager: PackageManager, newName: String) {
        val aliases = aliasNames(context)
        if (!aliases.contains(newName)) {
            Log.w("setAlternateIconName", "Ignoring unknown activity-alias $newName")
            return
        }
        Log.d("setAlternateIconName", "Enabling activity-alias $newName")
        // Enable first so there is never a moment without a launcher entry.
        enable(context, packageManager, newName)
        for (alias in aliases) {
            if (alias != newName) {
                disable(context, packageManager, alias)
            }
        }
    }
}

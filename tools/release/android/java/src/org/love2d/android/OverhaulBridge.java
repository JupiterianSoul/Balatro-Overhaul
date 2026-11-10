package org.love2d.android;

import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;

import org.libsdl.app.SDLActivity;

public class OverhaulBridge {
    private static final String PREFIX = "overhaul:";

    public static boolean handles(String url) {
        return url != null && url.startsWith(PREFIX);
    }

    public static boolean run(String url) {
        try {
            String cmd = url.substring(PREFIX.length());
            String arg = "";
            int q = cmd.indexOf('?');
            if (q >= 0) {
                arg = Uri.decode(cmd.substring(q + 1));
                cmd = cmd.substring(0, q);
            }
            Context ctx = SDLActivity.getContext();
            if (ctx == null) {
                return false;
            }
            switch (cmd) {
                case "info":
                    return info(ctx, arg);
                case "can_install":
                    return canInstall(ctx);
                case "allow_install":
                    return allowInstall(ctx);
                case "install":
                    return install(ctx, arg);
                case "open":
                    return open(ctx, arg);
                default:
                    return false;
            }
        } catch (Throwable t) {
            Log.w("OverhaulBridge", "failed: " + url, t);
            return false;
        }
    }

    private static boolean info(Context ctx, String arg) throws Exception {
        int bar = arg.indexOf('|');
        String pkg = bar >= 0 ? arg.substring(0, bar) : arg;
        String out = bar >= 0 ? arg.substring(bar + 1) : "";
        PackageManager pm = ctx.getPackageManager();
        PackageInfo pi;
        try {
            pi = pm.getPackageInfo(pkg, 0);
        } catch (PackageManager.NameNotFoundException e) {
            if (!out.isEmpty()) {
                new File(out).delete();
            }
            return false;
        }
        if (!out.isEmpty()) {
            ApplicationInfo ai = pi.applicationInfo;
            StringBuilder sb = new StringBuilder();
            sb.append(pi.versionName == null ? "" : pi.versionName).append('\n');
            sb.append(Build.VERSION.SDK_INT >= 28 ? pi.getLongVersionCode() : pi.versionCode).append('\n');
            sb.append(pi.lastUpdateTime).append('\n');
            sb.append(ai.sourceDir == null ? "" : ai.sourceDir).append('\n');
            if (ai.splitSourceDirs != null) {
                for (String s : ai.splitSourceDirs) {
                    sb.append(s).append('\n');
                }
            }
            FileOutputStream fo = new FileOutputStream(out);
            try {
                fo.write(sb.toString().getBytes(StandardCharsets.UTF_8));
            } finally {
                fo.close();
            }
        }
        return true;
    }

    private static boolean canInstall(Context ctx) {
        if (Build.VERSION.SDK_INT < 26) {
            return true;
        }
        return ctx.getPackageManager().canRequestPackageInstalls();
    }

    private static boolean allowInstall(Context ctx) {
        if (Build.VERSION.SDK_INT < 26) {
            return true;
        }
        Intent i = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + ctx.getPackageName()));
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        ctx.startActivity(i);
        return true;
    }

    private static boolean install(Context ctx, String path) throws Exception {
        File base = ctx.getFilesDir().getCanonicalFile();
        File f = new File(path).getCanonicalFile();
        String root = base.getPath() + File.separator;
        if (!f.getPath().startsWith(root) || !f.isFile()) {
            return false;
        }
        String rel = f.getPath().substring(root.length());
        Uri uri = new Uri.Builder().scheme("content").authority(ctx.getPackageName() + OverhaulFiles.SUFFIX).path(rel).build();
        Intent i = new Intent(Intent.ACTION_INSTALL_PACKAGE);
        i.setDataAndType(uri, OverhaulFiles.APK_TYPE);
        i.putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, false);
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        ctx.startActivity(i);
        return true;
    }

    private static boolean open(Context ctx, String pkg) {
        Intent i = ctx.getPackageManager().getLaunchIntentForPackage(pkg);
        if (i == null) {
            return false;
        }
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        ctx.startActivity(i);
        return true;
    }
}

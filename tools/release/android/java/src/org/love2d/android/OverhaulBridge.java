package org.love2d.android;

import android.app.Activity;
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
    private static final String PREFS = "overhaul";
    private static final String ORIENT_KEY = "orientation";

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
                case "pick":
                    return pick(ctx, arg);
                case "save":
                    return save(ctx, arg);
                case "appsave":
                    return appSave(ctx, arg);
                case "orient":
                    return orient(ctx, arg);
                case "has":
                    return "rotation_lock".equals(arg);
                default:
                    return false;
            }
        } catch (Throwable t) {
            Log.w("OverhaulBridge", "failed: " + url, t);
            return false;
        }
    }

    public static int orientation() {
        Context ctx = SDLActivity.getContext();
        if (ctx == null) {
            return 6;
        }
        String pick = ctx.getSharedPreferences(PREFS, 0).getString(ORIENT_KEY, "auto");
        if ("portrait".equals(pick)) {
            return 7;
        }
        if ("landscape".equals(pick)) {
            return 6;
        }
        return 13;
    }

    private static boolean orient(Context ctx, String arg) {
        String pick = "portrait".equals(arg) || "landscape".equals(arg) ? arg : "auto";
        ctx.getSharedPreferences(PREFS, 0).edit().putString(ORIENT_KEY, pick).commit();
        if (ctx instanceof Activity) {
            final Activity a = (Activity) ctx;
            a.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    a.setRequestedOrientation(orientation());
                }
            });
        }
        return true;
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

    private static boolean start(Context ctx, Intent i) {
        if (!(ctx instanceof Activity)) {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        }
        ctx.startActivity(i);
        return true;
    }

    private static boolean pick(Context ctx, String arg) {
        String[] p = arg.split("\\|", -1);
        if (p.length < 3 || !("zip".equals(p[0]) || "audio".equals(p[0]) || "image".equals(p[0]) || "forgemod".equals(p[0]))) {
            return false;
        }
        File dest = OverhaulPicker.inside(ctx, p[1]);
        File result = OverhaulPicker.inside(ctx, p[2]);
        if (dest == null || result == null) {
            return false;
        }
        long max = 0;
        if (p.length > 4 && !p[4].isEmpty()) {
            max = Long.parseLong(p[4]);
        }
        Intent i = new Intent(ctx, OverhaulPicker.class);
        i.putExtra(OverhaulPicker.KIND, p[0]);
        i.putExtra(OverhaulPicker.DEST, dest.getPath());
        i.putExtra(OverhaulPicker.RESULT, result.getPath());
        i.putExtra(OverhaulPicker.EXTS, p.length > 3 ? p[3] : "");
        i.putExtra(OverhaulPicker.MAX, max);
        return start(ctx, i);
    }

    private static boolean save(Context ctx, String arg) {
        String[] p = arg.split("\\|", 3);
        if (p.length < 3) {
            return false;
        }
        File src = OverhaulPicker.inside(ctx, p[0]);
        File result = OverhaulPicker.inside(ctx, p[1]);
        if (src == null || !src.isFile() || result == null) {
            return false;
        }
        Intent i = new Intent(ctx, OverhaulPicker.class);
        i.putExtra(OverhaulPicker.KIND, "save");
        i.putExtra(OverhaulPicker.SRC, src.getPath());
        i.putExtra(OverhaulPicker.RESULT, result.getPath());
        i.putExtra(OverhaulPicker.NAME, p[2]);
        return start(ctx, i);
    }

    private static boolean appSave(Context ctx, String arg) throws Exception {
        String[] p = arg.split("\\|", -1);
        if (p.length < 6 || !("export".equals(p[0]) || "import".equals(p[0]) || "apply".equals(p[0]))) {
            return false;
        }
        String pkg = p[1];
        if (!ctx.getPackageName().equals(pkg + ".phone")) {
            return false;
        }
        File result = OverhaulPicker.inside(ctx, p[2]);
        File dest = OverhaulPicker.inside(ctx, p[3]);
        if (result == null || dest == null) {
            return false;
        }
        PackageManager pm = ctx.getPackageManager();
        try {
            pm.getPackageInfo(pkg, 0);
        } catch (PackageManager.NameNotFoundException e) {
            writeResult(result, "noapp\n");
            return true;
        }
        try {
            pm.getActivityInfo(new android.content.ComponentName(pkg, OverhaulSaves.CLASS), 0);
        } catch (PackageManager.NameNotFoundException e) {
            writeResult(result, "old\n");
            return true;
        }
        Intent i = new Intent(ctx, OverhaulPicker.class);
        i.putExtra(OverhaulPicker.KIND, "app");
        i.putExtra(OverhaulPicker.MODE, p[0]);
        i.putExtra(OverhaulPicker.PKG, pkg);
        i.putExtra(OverhaulPicker.RESULT, result.getPath());
        i.putExtra(OverhaulPicker.DEST, dest.getPath());
        i.putExtra(OverhaulPicker.TOKEN, p[4]);
        i.putExtra(OverhaulPicker.NAME, p[5]);
        return start(ctx, i);
    }

    private static void writeResult(File f, String text) throws Exception {
        File tmp = new File(f.getPath() + ".tmp");
        FileOutputStream fo = new FileOutputStream(tmp);
        try {
            fo.write(text.getBytes(StandardCharsets.UTF_8));
        } finally {
            fo.close();
        }
        if (!tmp.renameTo(f)) {
            tmp.delete();
        }
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

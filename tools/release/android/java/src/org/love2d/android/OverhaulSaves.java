package org.love2d.android;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.provider.DocumentsContract;
import android.provider.OpenableColumns;
import android.database.Cursor;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import org.libsdl.app.SDLActivity;

public class OverhaulSaves extends Activity {
    public static final String CLASS = "org.love2d.android.OverhaulSaves";
    public static final String MODE = "mode";
    public static final String TOKEN = "token";
    public static final String NAME = "name";
    public static final String STATUS = "status";
    public static final String IDENTITY = "BalatroOverhaul";
    public static final long MAX_FILE = 16L * 1024 * 1024;
    public static final long MAX_TOTAL = 96L * 1024 * 1024;
    public static final long TOKEN_LIFE = 30L * 60 * 1000;

    static final Set<String> SKIP_DIRS = new HashSet<String>(Arrays.asList(
        "backups", "exports", "imports", "crash_reports", "bot", "mods", "Mods", "lovely", "workshop", "cache", "shots", "updates",
        "Overhaul", "Overhaul.new", "overhaul_game", "overhaul_game.new", "update", "vanilla", "launcher", "patch", "android", "carry",
        "engine", "functions", "localization", "modloader", "multiplayer", "resources", "smods", "dexopt", "patcher"));
    static final Set<String> SKIP_FILES = new HashSet<String>(Arrays.asList(
        "settings.jkr", "modded_settings.jkr", "version.jkr", "overhaul_running.lock", "official.zip", "launcher_settings.lua",
        "launcher_play", "BalatroOverhaul.apk", "BalatroOverhaul.apk.part", "app_info.txt", "carry_done", "direct_play",
        "app_icon.png", "app_icon.ico", "app_pending", "import_pending", "overhaul_pick.txt", "conf.lua", "main.lua"));
    static final Set<String> ROOT_LUA = new HashSet<String>(Arrays.asList("minigames.lua", "run_history.lua", "run_splits.lua"));
    static final Set<String> JKR_NAMES = new HashSet<String>(Arrays.asList("profile.jkr", "meta.jkr", "unlock_notify.jkr", "save.jkr"));
    private static final String[] ZIP_TYPES = {"application/zip", "application/x-zip-compressed", "application/x-zip", "application/octet-stream"};
    private static final int REQUEST = 0x4f53;

    private String mode;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        if (state != null) {
            return;
        }
        mode = getIntent().getStringExtra(MODE);
        try {
            if (gameRunning()) {
                reply("running", null, null, null);
                return;
            }
            if ("export".equals(mode)) {
                if (!hasProfile(saveDir(false))) {
                    reply("empty", null, null, null);
                    return;
                }
                Intent i = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("application/zip");
                i.putExtra(Intent.EXTRA_TITLE, exportName(getIntent().getStringExtra(NAME)));
                startActivityForResult(i, REQUEST);
            } else if ("import".equals(mode)) {
                Intent i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("*/*");
                i.putExtra(Intent.EXTRA_MIME_TYPES, ZIP_TYPES);
                startActivityForResult(i, REQUEST);
            } else if ("apply".equals(mode)) {
                reply(apply(getIntent().getStringExtra(TOKEN)), null, null, null);
            } else {
                reply("error", null, null, null);
            }
        } catch (Throwable t) {
            Log.w("OverhaulSaves", "start failed", t);
            reply("error", null, null, null);
        }
    }

    static boolean gameRunning() {
        try {
            return SDLActivity.getContext() != null;
        } catch (Throwable t) {
            return false;
        }
    }

    File saveDir(boolean create) {
        File[] roots = {getFilesDir(), getExternalFilesDir(null)};
        for (File r : roots) {
            if (r != null) {
                File d = new File(new File(r, "save"), IDENTITY);
                if (d.isDirectory()) {
                    return d;
                }
            }
        }
        File d = new File(new File(getFilesDir(), "save"), IDENTITY);
        if (create) {
            d.mkdirs();
        }
        return d;
    }

    File work() {
        File d = new File(getFilesDir(), "overhaul_saves");
        d.mkdirs();
        return d;
    }

    static String exportName(String name) {
        String n = OverhaulPicker.clean(name == null || name.isEmpty() ? "Balatro Overhaul save.zip" : name);
        if (!n.toLowerCase(Locale.ROOT).endsWith(".zip")) {
            n = n + ".zip";
        }
        return n;
    }

    static boolean hasProfile(File dir) {
        File[] items = dir.listFiles();
        if (items == null) {
            return false;
        }
        for (File f : items) {
            if (f.isDirectory() && !SKIP_DIRS.contains(f.getName())
                && (new File(f, "profile.jkr").isFile() || new File(f, "meta.jkr").isFile())) {
                return true;
            }
        }
        return false;
    }

    static boolean skip(String rel) {
        String[] parts = rel.split("/");
        String low = rel.toLowerCase(Locale.ROOT);
        if (parts.length > 1 && SKIP_DIRS.contains(parts[0])) {
            return true;
        }
        if (SKIP_FILES.contains(rel)) {
            return true;
        }
        for (String p : parts) {
            if (p.isEmpty() || p.startsWith(".") || p.equals("..")) {
                return true;
            }
        }
        if (low.endsWith(".log") || low.endsWith("debug.txt") || low.contains("token") || low.contains("secret")
            || low.endsWith("key.lua") || low.endsWith("keys.lua") || low.endsWith(".part")) {
            return true;
        }
        if (low.endsWith(".so") || low.endsWith(".dll") || low.endsWith(".dylib") || low.endsWith(".exe")
            || rel.indexOf(':') >= 0 || rel.indexOf('\\') >= 0 || rel.length() > 260) {
            return true;
        }
        return parts.length == 1 && low.endsWith(".lua") && !ROOT_LUA.contains(low);
    }

    static void collect(File dir, String prefix, List<String> out) {
        File[] items = dir.listFiles();
        if (items == null) {
            return;
        }
        Arrays.sort(items);
        for (File f : items) {
            String rel = prefix.isEmpty() ? f.getName() : prefix + "/" + f.getName();
            if (f.isDirectory()) {
                if (!skip(rel + "/x")) {
                    collect(f, rel, out);
                }
            } else if (f.isFile() && !skip(rel) && f.length() <= MAX_FILE) {
                out.add(rel);
            }
        }
    }

    @Override
    protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != REQUEST) {
            return;
        }
        if (result != RESULT_OK || data == null || data.getData() == null) {
            reply("cancel", null, null, null);
            return;
        }
        final Uri uri = data.getData();
        new Thread(new Runnable() {
            @Override
            public void run() {
                String[] r;
                try {
                    r = "export".equals(mode) ? export(uri) : stage(uri);
                } catch (Throwable t) {
                    Log.w("OverhaulSaves", "failed", t);
                    r = new String[] {"error", null, null};
                }
                final String[] res = r;
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        Uri back = "ok".equals(res[0]) && "import".equals(mode) ? stagedUri() : null;
                        reply(res[0], res[1], res[2], back);
                    }
                });
            }
        }, "OverhaulSaves").start();
    }

    private String[] export(Uri target) {
        File dir = saveDir(false);
        List<String> list = new ArrayList<String>();
        collect(dir, "", list);
        boolean ok = false;
        try {
            OutputStream os = getContentResolver().openOutputStream(target, "w");
            if (os != null) {
                try {
                    ZipOutputStream zip = new ZipOutputStream(os);
                    long total = 0;
                    byte[] buf = new byte[65536];
                    for (String rel : list) {
                        File f = new File(dir, rel);
                        total += f.length();
                        if (total > MAX_TOTAL) {
                            break;
                        }
                        zip.putNextEntry(new ZipEntry(rel));
                        InputStream is = new FileInputStream(f);
                        try {
                            int n;
                            while ((n = is.read(buf)) > 0) {
                                zip.write(buf, 0, n);
                            }
                        } finally {
                            is.close();
                        }
                        zip.closeEntry();
                    }
                    zip.finish();
                    zip.flush();
                    ok = true;
                } finally {
                    os.close();
                }
            }
        } catch (Throwable t) {
            Log.w("OverhaulSaves", "export failed", t);
            ok = false;
        }
        if (!ok) {
            try {
                DocumentsContract.deleteDocument(getContentResolver(), target);
            } catch (Throwable t) {
                Log.w("OverhaulSaves", "could not remove the empty file", t);
            }
            return new String[] {"error", null, null};
        }
        return new String[] {"ok", null, displayName(target, exportName(getIntent().getStringExtra(NAME)))};
    }

    private String displayName(Uri uri, String fallback) {
        Cursor c = null;
        try {
            c = getContentResolver().query(uri, new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null);
            if (c != null && c.moveToFirst() && !c.isNull(0)) {
                String v = c.getString(0);
                if (v != null && !v.isEmpty()) {
                    return OverhaulPicker.clean(v);
                }
            }
        } catch (Throwable t) {
            Log.w("OverhaulSaves", "no name", t);
        } finally {
            if (c != null) {
                c.close();
            }
        }
        return fallback;
    }

    private String[] stage(Uri uri) throws IOException {
        File dir = work();
        File staged = new File(dir, "staged.zip");
        File tmp = new File(dir, "staged.part");
        new File(dir, "token").delete();
        staged.delete();
        String name = displayName(uri, "save.zip");
        long total = 0;
        byte[] head = new byte[4];
        int got = 0;
        InputStream is = getContentResolver().openInputStream(uri);
        if (is == null) {
            return new String[] {"error", null, null};
        }
        try {
            OutputStream os = new FileOutputStream(tmp);
            try {
                byte[] buf = new byte[65536];
                int n;
                while ((n = is.read(buf)) > 0) {
                    for (int k = 0; k < n && got < 4; k++) {
                        head[got++] = buf[k];
                    }
                    total += n;
                    if (total > MAX_TOTAL) {
                        os.close();
                        tmp.delete();
                        return new String[] {"big", null, null};
                    }
                    os.write(buf, 0, n);
                }
            } finally {
                os.close();
            }
        } finally {
            is.close();
        }
        boolean zip = got == 4 && head[0] == 'P' && head[1] == 'K' && head[2] == 3 && head[3] == 4;
        String low = name.toLowerCase(Locale.ROOT);
        if (!zip && JKR_NAMES.contains(low) && total > 0 && total <= MAX_FILE) {
            File wrapped = new File(dir, "wrapped.part");
            ZipOutputStream out = new ZipOutputStream(new FileOutputStream(wrapped));
            try {
                out.putNextEntry(new ZipEntry("1/" + low));
                InputStream in = new FileInputStream(tmp);
                try {
                    byte[] buf = new byte[65536];
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        out.write(buf, 0, n);
                    }
                } finally {
                    in.close();
                }
                out.closeEntry();
            } finally {
                out.close();
            }
            tmp.delete();
            tmp = wrapped;
            zip = true;
        }
        if (!zip) {
            tmp.delete();
            return new String[] {"wrong", null, null};
        }
        if (!tmp.renameTo(staged)) {
            tmp.delete();
            return new String[] {"error", null, null};
        }
        byte[] raw = new byte[16];
        new SecureRandom().nextBytes(raw);
        StringBuilder hex = new StringBuilder();
        for (byte b : raw) {
            hex.append(String.format(Locale.ROOT, "%02x", b & 0xff));
        }
        String token = hex.toString();
        writeText(new File(dir, "token"), token + " " + System.currentTimeMillis());
        return new String[] {"ok", token, name};
    }

    private Uri stagedUri() {
        return new Uri.Builder().scheme("content").authority(getPackageName() + OverhaulFiles.SUFFIX).path("overhaul_saves/staged.zip").build();
    }

    private String apply(String token) throws IOException {
        File dir = work();
        File tokenFile = new File(dir, "token");
        File staged = new File(dir, "staged.zip");
        String saved = readText(tokenFile);
        tokenFile.delete();
        if (token == null || token.isEmpty() || saved == null || !staged.isFile()) {
            return "error";
        }
        String[] p = saved.trim().split(" ");
        long when = 0;
        try {
            when = p.length > 1 ? Long.parseLong(p[1]) : 0;
        } catch (NumberFormatException e) {
            when = 0;
        }
        if (!p[0].equals(token) || System.currentTimeMillis() - when > TOKEN_LIFE) {
            staged.delete();
            return "error";
        }
        File imports = new File(saveDir(true), "imports");
        if (!imports.isDirectory() && !imports.mkdirs()) {
            return "error";
        }
        File tmp = new File(imports, "pending.part");
        File pending = new File(imports, "pending.zip");
        InputStream is = new FileInputStream(staged);
        try {
            OutputStream os = new FileOutputStream(tmp);
            try {
                byte[] buf = new byte[65536];
                int n;
                while ((n = is.read(buf)) > 0) {
                    os.write(buf, 0, n);
                }
            } finally {
                os.close();
            }
        } finally {
            is.close();
        }
        pending.delete();
        if (!tmp.renameTo(pending)) {
            tmp.delete();
            return "error";
        }
        staged.delete();
        return "ok";
    }

    static void writeText(File f, String text) throws IOException {
        FileOutputStream fo = new FileOutputStream(f);
        try {
            fo.write(text.getBytes(StandardCharsets.UTF_8));
        } finally {
            fo.close();
        }
    }

    static String readText(File f) {
        if (!f.isFile() || f.length() > 4096) {
            return null;
        }
        try {
            FileInputStream fi = new FileInputStream(f);
            try {
                byte[] b = new byte[(int) f.length()];
                int n = fi.read(b);
                return new String(b, 0, Math.max(n, 0), StandardCharsets.UTF_8);
            } finally {
                fi.close();
            }
        } catch (IOException e) {
            return null;
        }
    }

    private void reply(String status, String token, String name, Uri back) {
        Intent r = new Intent();
        r.putExtra(STATUS, status);
        if (token != null) {
            r.putExtra(TOKEN, token);
        }
        if (name != null) {
            r.putExtra(NAME, name);
        }
        if (back != null) {
            r.setData(back);
            r.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        }
        setResult(RESULT_OK, r);
        finish();
    }
}

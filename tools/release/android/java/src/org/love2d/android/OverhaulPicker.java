package org.love2d.android;

import android.app.Activity;
import android.content.ClipData;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.DocumentsContract;
import android.provider.OpenableColumns;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

public class OverhaulPicker extends Activity {
    static final String KIND = "kind";
    static final String DEST = "dest";
    static final String RESULT = "result";
    static final String EXTS = "exts";
    static final String MAX = "max";
    static final String SRC = "src";
    static final String NAME = "name";
    static final String PKG = "pkg";
    static final String MODE = "mode";
    static final String TOKEN = "token";

    private static final int REQUEST = 0x4f50;
    private static final String[] ZIP_TYPES = {"application/zip", "application/x-zip-compressed", "application/x-zip", "application/octet-stream"};
    private static final String[] AUDIO_TYPES = {"audio/*", "application/ogg"};
    private static final String[] IMAGE_TYPES = {"image/png", "image/jpeg", "image/bmp", "image/x-ms-bmp", "image/x-tga", "image/tga"};

    static File inside(Context ctx, String path) {
        if (path == null || path.isEmpty()) {
            return null;
        }
        try {
            File f = new File(path).getCanonicalFile();
            File[] roots = {ctx.getFilesDir(), ctx.getExternalFilesDir(null)};
            for (File r : roots) {
                if (r == null) {
                    continue;
                }
                String base = r.getCanonicalFile().getPath() + File.separator;
                if (f.getPath().startsWith(base)) {
                    return f;
                }
            }
        } catch (IOException e) {
            return null;
        }
        return null;
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        if (state != null) {
            return;
        }
        Intent in = getIntent();
        String kind = in.getStringExtra(KIND);
        try {
            Intent i;
            if ("app".equals(kind)) {
                i = new Intent();
                i.setClassName(in.getStringExtra(PKG), OverhaulSaves.CLASS);
                i.putExtra(OverhaulSaves.MODE, in.getStringExtra(MODE));
                i.putExtra(OverhaulSaves.TOKEN, in.getStringExtra(TOKEN));
                i.putExtra(OverhaulSaves.NAME, in.getStringExtra(NAME));
                try {
                    startActivityForResult(i, REQUEST);
                } catch (android.content.ActivityNotFoundException e) {
                    done("old\n");
                }
                return;
            }
            if ("save".equals(kind)) {
                i = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("application/zip");
                i.putExtra(Intent.EXTRA_TITLE, clean(in.getStringExtra(NAME)));
            } else {
                i = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("*/*");
                if ("audio".equals(kind)) {
                    i.putExtra(Intent.EXTRA_MIME_TYPES, AUDIO_TYPES);
                    i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
                } else if ("image".equals(kind)) {
                    i.putExtra(Intent.EXTRA_MIME_TYPES, IMAGE_TYPES);
                } else if ("forgemod".equals(kind)) {
                    i.setType("*/*");
                } else {
                    i.putExtra(Intent.EXTRA_MIME_TYPES, ZIP_TYPES);
                }
            }
            startActivityForResult(i, REQUEST);
        } catch (Throwable t) {
            Log.w("OverhaulPicker", "no file picker", t);
            done("error\n");
        }
    }

    @Override
    protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != REQUEST) {
            return;
        }
        if ("app".equals(getIntent().getStringExtra(KIND))) {
            appResult(data);
            return;
        }
        if (result != RESULT_OK || data == null) {
            done("cancel\n");
            return;
        }
        final List<Uri> uris = new ArrayList<Uri>();
        ClipData clip = data.getClipData();
        if (clip != null) {
            for (int i = 0; i < clip.getItemCount(); i++) {
                Uri u = clip.getItemAt(i).getUri();
                if (u != null) {
                    uris.add(u);
                }
            }
        } else if (data.getData() != null) {
            uris.add(data.getData());
        }
        if (uris.isEmpty()) {
            done("cancel\n");
            return;
        }
        new Thread(new Runnable() {
            @Override
            public void run() {
                String out;
                try {
                    out = work(uris);
                } catch (Throwable t) {
                    Log.w("OverhaulPicker", "failed", t);
                    out = "error\n";
                }
                final String text = out;
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        done(text);
                    }
                });
            }
        }, "OverhaulPicker").start();
    }

    private void appResult(Intent data) {
        String status = data == null ? null : data.getStringExtra(OverhaulSaves.STATUS);
        if (status == null || !status.matches("[a-z]{1,12}")) {
            done("cancel\n");
            return;
        }
        final String token = data.getStringExtra(OverhaulSaves.TOKEN);
        final String name = data.getStringExtra(OverhaulSaves.NAME);
        final Uri uri = data.getData();
        if (!"ok".equals(status) || !"import".equals(getIntent().getStringExtra(MODE))) {
            done(status + "\n" + (name != null ? "@" + clean(name) + "\n" : ""));
            return;
        }
        if (uri == null || token == null || !token.matches("[0-9a-f]{32}")) {
            done("error\n");
            return;
        }
        new Thread(new Runnable() {
            @Override
            public void run() {
                String out;
                try {
                    File dir = inside(OverhaulPicker.this, getIntent().getStringExtra(DEST));
                    if (dir == null || (!dir.isDirectory() && !dir.mkdirs())) {
                        out = "error\n";
                    } else {
                        File tmp = new File(dir, ".part-app-" + System.nanoTime());
                        File target = new File(dir, "app_import.zip");
                        InputStream is = getContentResolver().openInputStream(uri);
                        if (is == null) {
                            out = "error\n";
                        } else {
                            try {
                                OutputStream os = new FileOutputStream(tmp);
                                try {
                                    pump(is, os, OverhaulSaves.MAX_TOTAL);
                                } finally {
                                    os.close();
                                }
                            } finally {
                                is.close();
                            }
                            target.delete();
                            if (tmp.renameTo(target)) {
                                out = "ok\n+app_import.zip\n#" + token + "\n" + (name != null ? "@" + clean(name) + "\n" : "");
                            } else {
                                tmp.delete();
                                out = "error\n";
                            }
                        }
                    }
                } catch (TooBig e) {
                    out = "big\n";
                } catch (Throwable t) {
                    Log.w("OverhaulPicker", "app import copy failed", t);
                    out = "error\n";
                }
                final String text = out;
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        done(text);
                    }
                });
            }
        }, "OverhaulPickerApp").start();
    }

    private void done(String text) {
        File result = inside(this, getIntent().getStringExtra(RESULT));
        if (result != null) {
            File tmp = new File(result.getPath() + ".tmp");
            try {
                FileOutputStream fo = new FileOutputStream(tmp);
                try {
                    fo.write(text.getBytes(StandardCharsets.UTF_8));
                } finally {
                    fo.close();
                }
                if (!tmp.renameTo(result)) {
                    tmp.delete();
                }
            } catch (IOException e) {
                tmp.delete();
            }
        }
        finish();
    }

    private String work(List<Uri> uris) throws IOException {
        Intent in = getIntent();
        if ("save".equals(in.getStringExtra(KIND))) {
            return export(uris.get(0), inside(this, in.getStringExtra(SRC)));
        }
        File dir = inside(this, in.getStringExtra(DEST));
        if (dir == null || (!dir.isDirectory() && !dir.mkdirs())) {
            return "error\n";
        }
        Set<String> exts = new HashSet<String>();
        String list = in.getStringExtra(EXTS);
        if (list != null) {
            for (String e : list.split(",")) {
                if (!e.isEmpty()) {
                    exts.add(e.toLowerCase(Locale.ROOT));
                }
            }
        }
        long max = in.getLongExtra(MAX, 0);
        StringBuilder sb = new StringBuilder("ok\n");
        for (Uri u : uris) {
            sb.append(copy(u, dir, exts, max)).append('\n');
        }
        return sb.toString();
    }

    private String export(Uri target, File src) {
        if (src == null || !src.isFile()) {
            return "error\n";
        }
        boolean ok = false;
        try {
            InputStream is = new FileInputStream(src);
            try {
                OutputStream os = getContentResolver().openOutputStream(target, "w");
                if (os != null) {
                    try {
                        pump(is, os, 0);
                        ok = true;
                    } finally {
                        os.close();
                    }
                }
            } finally {
                is.close();
            }
        } catch (Throwable t) {
            Log.w("OverhaulPicker", "export failed", t);
            ok = false;
        }
        if (!ok) {
            try {
                DocumentsContract.deleteDocument(getContentResolver(), target);
            } catch (Throwable t) {
                Log.w("OverhaulPicker", "could not remove the empty file", t);
            }
            return "error\n";
        }
        return "ok\n+" + column(target, OpenableColumns.DISPLAY_NAME, src.getName()) + "\n";
    }

    private String copy(Uri uri, File dir, Set<String> exts, long max) {
        String name = clean(column(uri, OpenableColumns.DISPLAY_NAME, uri.getLastPathSegment()));
        int dot = name.lastIndexOf('.');
        String ext = dot >= 0 ? name.substring(dot + 1).toLowerCase(Locale.ROOT) : "";
        if (!exts.isEmpty() && !exts.contains(ext)) {
            return "-" + name;
        }
        long size = -1;
        try {
            size = Long.parseLong(column(uri, OpenableColumns.SIZE, "-1"));
        } catch (NumberFormatException e) {
            size = -1;
        }
        if (max > 0 && size > max) {
            return ">" + name;
        }
        File same = new File(dir, name);
        if (same.isFile() && size >= 0 && same.length() == size) {
            return "=" + name;
        }
        File out = same;
        String stem = dot >= 0 ? name.substring(0, dot) : name;
        String tail = dot >= 0 ? name.substring(dot) : "";
        for (int n = 2; out.exists(); n++) {
            out = new File(dir, stem + " (" + n + ")" + tail);
        }
        File tmp = new File(dir, ".part-pick-" + System.nanoTime());
        try {
            InputStream is = getContentResolver().openInputStream(uri);
            if (is == null) {
                return "!" + name;
            }
            try {
                OutputStream os = new FileOutputStream(tmp);
                try {
                    pump(is, os, max);
                } finally {
                    os.close();
                }
            } finally {
                is.close();
            }
        } catch (TooBig e) {
            tmp.delete();
            return ">" + name;
        } catch (Throwable t) {
            Log.w("OverhaulPicker", "copy failed", t);
            tmp.delete();
            return "!" + name;
        }
        if (!tmp.renameTo(out)) {
            tmp.delete();
            return "!" + name;
        }
        return "+" + out.getName();
    }

    private static class TooBig extends IOException {
    }

    private static void pump(InputStream is, OutputStream os, long max) throws IOException {
        byte[] buf = new byte[65536];
        long total = 0;
        int n;
        while ((n = is.read(buf)) > 0) {
            total += n;
            if (max > 0 && total > max) {
                throw new TooBig();
            }
            os.write(buf, 0, n);
        }
    }

    private String column(Uri uri, String col, String fallback) {
        Cursor c = null;
        try {
            c = getContentResolver().query(uri, new String[] {col}, null, null, null);
            if (c != null && c.moveToFirst() && !c.isNull(0)) {
                String v = c.getString(0);
                if (v != null && !v.isEmpty()) {
                    return v;
                }
            }
        } catch (Throwable t) {
            Log.w("OverhaulPicker", "no " + col, t);
        } finally {
            if (c != null) {
                c.close();
            }
        }
        return fallback == null ? "" : fallback;
    }

    static String clean(String name) {
        if (name == null) {
            name = "";
        }
        name = name.replace('\\', '/');
        int slash = name.lastIndexOf('/');
        if (slash >= 0) {
            name = name.substring(slash + 1);
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < name.length(); i++) {
            char ch = name.charAt(i);
            if (ch < 0x20 || ch == 0x7f || "<>:\"|?*".indexOf(ch) >= 0) {
                continue;
            }
            sb.append(ch);
        }
        name = sb.toString().trim();
        while (name.startsWith(".")) {
            name = name.substring(1);
        }
        if (name.length() > 120) {
            int dot = name.lastIndexOf('.');
            String tail = dot >= 0 && name.length() - dot <= 10 ? name.substring(dot) : "";
            name = name.substring(0, 120 - tail.length()) + tail;
        }
        return name.isEmpty() ? "file" : name;
    }
}

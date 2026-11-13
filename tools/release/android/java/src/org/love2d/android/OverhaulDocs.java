package org.love2d.android;

import android.content.ContentResolver;
import android.content.pm.ApplicationInfo;
import android.content.res.AssetFileDescriptor;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.graphics.Point;
import android.net.Uri;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract;
import android.provider.DocumentsContract.Document;
import android.provider.DocumentsContract.Root;
import android.provider.DocumentsProvider;
import android.util.Log;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

public class OverhaulDocs extends DocumentsProvider {
    static final String ROOT = "save";
    static final String TITLE = "Balatro Overhaul";
    static final String PART = ".overhaul-part-";
    static final String[] IDENTITIES = {"BalatroOverhaul", "game", "ASET"};

    static final String[] ROOT_COLS = {
        Root.COLUMN_ROOT_ID, Root.COLUMN_FLAGS, Root.COLUMN_TITLE, Root.COLUMN_DOCUMENT_ID,
        Root.COLUMN_ICON, Root.COLUMN_AVAILABLE_BYTES,
    };
    static final String[] DOC_COLS = {
        Document.COLUMN_DOCUMENT_ID, Document.COLUMN_MIME_TYPE, Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_LAST_MODIFIED, Document.COLUMN_FLAGS, Document.COLUMN_SIZE,
    };

    static final Map<String, String> TYPES = new HashMap<String, String>();

    static {
        TYPES.put("lua", "text/x-lua");
        TYPES.put("json", "application/json");
        TYPES.put("txt", "text/plain");
        TYPES.put("log", "text/plain");
        TYPES.put("md", "text/markdown");
        TYPES.put("toml", "text/plain");
        TYPES.put("cfg", "text/plain");
        TYPES.put("ini", "text/plain");
        TYPES.put("csv", "text/csv");
        TYPES.put("fs", "text/plain");
        TYPES.put("glsl", "text/plain");
        TYPES.put("png", "image/png");
        TYPES.put("jpg", "image/jpeg");
        TYPES.put("jpeg", "image/jpeg");
        TYPES.put("gif", "image/gif");
        TYPES.put("ogg", "audio/ogg");
        TYPES.put("mp3", "audio/mpeg");
        TYPES.put("wav", "audio/wav");
        TYPES.put("flac", "audio/flac");
        TYPES.put("ttf", "font/ttf");
        TYPES.put("otf", "font/otf");
        TYPES.put("zip", "application/zip");
        TYPES.put("jkr", "application/octet-stream");
        TYPES.put("prev", "application/octet-stream");
    }

    private static HandlerThread closer;

    @Override
    public boolean onCreate() {
        return true;
    }

    static File pick(File save) {
        for (String id : IDENTITIES) {
            File d = new File(save, id);
            if (d.isDirectory()) {
                return d;
            }
        }
        File best = null;
        File[] list = save.listFiles();
        if (list != null) {
            for (File d : list) {
                if (d.isDirectory() && (best == null || d.lastModified() > best.lastModified())) {
                    best = d;
                }
            }
        }
        return best != null ? best : new File(save, IDENTITIES[0]);
    }

    private File base() throws FileNotFoundException {
        try {
            return pick(new File(getContext().getFilesDir(), "save")).getCanonicalFile();
        } catch (IOException e) {
            throw new FileNotFoundException("no game folder");
        }
    }

    static boolean goodName(String name) {
        if (name == null || name.isEmpty() || name.length() > 255) {
            return false;
        }
        if (name.equals(".") || name.equals("..") || name.startsWith(PART)) {
            return false;
        }
        for (int i = 0; i < name.length(); i++) {
            char c = name.charAt(i);
            if (c == '/' || c == '\\' || c == 0 || c < 32) {
                return false;
            }
        }
        return true;
    }

    static File within(File base, String rel) throws FileNotFoundException {
        if (rel == null || rel.indexOf('\0') >= 0) {
            throw new FileNotFoundException("bad path");
        }
        File f = base;
        if (!rel.isEmpty()) {
            for (String part : rel.split("/", -1)) {
                if (!goodName(part)) {
                    throw new FileNotFoundException("bad path");
                }
                f = new File(f, part);
            }
        }
        try {
            File c = f.getCanonicalFile();
            if (!c.equals(base) && !c.getPath().startsWith(base.getPath() + File.separator)) {
                throw new FileNotFoundException("outside the game folder");
            }
            if (!c.exists() && listed(c)) {
                throw new FileNotFoundException("broken link");
            }
            return c;
        } catch (IOException e) {
            throw new FileNotFoundException("bad path");
        }
    }

    static boolean listed(File f) {
        String[] names = f.getParentFile() != null ? f.getParentFile().list() : null;
        if (names != null) {
            for (String n : names) {
                if (n.equals(f.getName())) {
                    return true;
                }
            }
        }
        return false;
    }

    static String relOf(String docId) throws FileNotFoundException {
        if (docId == null) {
            throw new FileNotFoundException("no document");
        }
        if (docId.equals(ROOT)) {
            return "";
        }
        if (!docId.startsWith(ROOT + "/")) {
            throw new FileNotFoundException("unknown document " + docId);
        }
        return docId.substring(ROOT.length() + 1);
    }

    static String idOf(File base, File f) {
        if (f.equals(base)) {
            return ROOT;
        }
        return ROOT + "/" + f.getPath().substring(base.getPath().length() + 1).replace(File.separatorChar, '/');
    }

    static String typeOf(File f) {
        if (f.isDirectory()) {
            return Document.MIME_TYPE_DIR;
        }
        String name = f.getName();
        int dot = name.lastIndexOf('.');
        if (dot < 0 || dot == name.length() - 1) {
            return "application/octet-stream";
        }
        String ext = name.substring(dot + 1).toLowerCase(Locale.ROOT);
        String t = TYPES.get(ext);
        if (t == null) {
            try {
                t = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
            } catch (Throwable e) {
                t = null;
            }
        }
        return t != null ? t : "application/octet-stream";
    }

    private String authority() {
        return getContext().getPackageName() + ".files";
    }

    private void changed(String docId) {
        try {
            ContentResolver r = getContext().getContentResolver();
            String parent = docId.equals(ROOT) ? ROOT : (docId.lastIndexOf('/') > ROOT.length() ? docId.substring(0, docId.lastIndexOf('/')) : ROOT);
            r.notifyChange(DocumentsContract.buildChildDocumentsUri(authority(), parent), null, false);
            r.notifyChange(DocumentsContract.buildDocumentUri(authority(), docId), null, false);
        } catch (Throwable e) {
            Log.w("OverhaulDocs", "notify failed", e);
        }
    }

    private String title() {
        try {
            ApplicationInfo ai = getContext().getApplicationInfo();
            CharSequence l = ai.loadLabel(getContext().getPackageManager());
            if (l != null && l.length() > 0) {
                return l.toString();
            }
        } catch (Throwable e) {
            Log.w("OverhaulDocs", "no label", e);
        }
        return TITLE;
    }

    @Override
    public Cursor queryRoots(String[] projection) throws FileNotFoundException {
        MatrixCursor c = new MatrixCursor(projection != null ? projection : ROOT_COLS);
        File b = base();
        File free = b.exists() ? b : getContext().getFilesDir();
        c.newRow()
            .add(Root.COLUMN_ROOT_ID, ROOT)
            .add(Root.COLUMN_FLAGS, Root.FLAG_SUPPORTS_CREATE | Root.FLAG_LOCAL_ONLY | Root.FLAG_SUPPORTS_IS_CHILD)
            .add(Root.COLUMN_TITLE, title())
            .add(Root.COLUMN_DOCUMENT_ID, ROOT)
            .add(Root.COLUMN_ICON, getContext().getApplicationInfo().icon)
            .add(Root.COLUMN_AVAILABLE_BYTES, free.getUsableSpace());
        c.setNotificationUri(getContext().getContentResolver(), DocumentsContract.buildRootsUri(authority()));
        return c;
    }

    private void row(MatrixCursor c, File b, File f) {
        String id = idOf(b, f);
        boolean dir = f.isDirectory() || f.equals(b);
        int flags;
        if (f.equals(b)) {
            flags = Document.FLAG_DIR_SUPPORTS_CREATE;
        } else if (dir) {
            flags = Document.FLAG_DIR_SUPPORTS_CREATE | Document.FLAG_SUPPORTS_DELETE | Document.FLAG_SUPPORTS_RENAME;
        } else {
            flags = Document.FLAG_SUPPORTS_WRITE | Document.FLAG_SUPPORTS_DELETE | Document.FLAG_SUPPORTS_RENAME;
        }
        String type = dir ? Document.MIME_TYPE_DIR : typeOf(f);
        if (type.startsWith("image/")) {
            flags |= Document.FLAG_SUPPORTS_THUMBNAIL;
        }
        c.newRow()
            .add(Document.COLUMN_DOCUMENT_ID, id)
            .add(Document.COLUMN_MIME_TYPE, type)
            .add(Document.COLUMN_DISPLAY_NAME, f.equals(b) ? title() : f.getName())
            .add(Document.COLUMN_LAST_MODIFIED, f.lastModified())
            .add(Document.COLUMN_FLAGS, flags)
            .add(Document.COLUMN_SIZE, dir ? null : f.length());
    }

    @Override
    public Cursor queryDocument(String documentId, String[] projection) throws FileNotFoundException {
        File b = base();
        File f = within(b, relOf(documentId));
        if (!f.equals(b) && !f.exists()) {
            throw new FileNotFoundException("missing " + documentId);
        }
        MatrixCursor c = new MatrixCursor(projection != null ? projection : DOC_COLS);
        row(c, b, f);
        return c;
    }

    @Override
    public Cursor queryChildDocuments(String parentDocumentId, String[] projection, String sortOrder) throws FileNotFoundException {
        File b = base();
        File dir = within(b, relOf(parentDocumentId));
        MatrixCursor c = new MatrixCursor(projection != null ? projection : DOC_COLS);
        String rel = relOf(parentDocumentId);
        String[] names = dir.list();
        if (names != null) {
            for (String name : names) {
                File real;
                try {
                    real = within(b, rel.isEmpty() ? name : rel + "/" + name);
                } catch (FileNotFoundException e) {
                    continue;
                }
                if (real.getParentFile().equals(dir) && real.getName().equals(name)) {
                    row(c, b, real);
                }
            }
        }
        c.setNotificationUri(getContext().getContentResolver(), DocumentsContract.buildChildDocumentsUri(authority(), parentDocumentId));
        return c;
    }

    @Override
    public String getDocumentType(String documentId) throws FileNotFoundException {
        File b = base();
        File f = within(b, relOf(documentId));
        return f.equals(b) ? Document.MIME_TYPE_DIR : typeOf(f);
    }

    @Override
    public boolean isChildDocument(String parentDocumentId, String documentId) {
        try {
            File b = base();
            File p = within(b, relOf(parentDocumentId));
            File d = within(b, relOf(documentId));
            return d.getPath().startsWith(p.getPath() + File.separator);
        } catch (FileNotFoundException e) {
            return false;
        }
    }

    private static synchronized Handler handler() {
        if (closer == null) {
            closer = new HandlerThread("OverhaulDocs");
            closer.start();
        }
        return new Handler(closer.getLooper());
    }

    @Override
    public ParcelFileDescriptor openDocument(final String documentId, String mode, CancellationSignal signal) throws FileNotFoundException {
        File b = base();
        final File f = within(b, relOf(documentId));
        if (f.equals(b) || f.isDirectory()) {
            throw new FileNotFoundException("a folder can not be opened");
        }
        if ("r".equals(mode)) {
            return ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY);
        }
        if (!f.getParentFile().isDirectory()) {
            throw new FileNotFoundException("missing folder");
        }
        if ("wa".equals(mode)) {
            return watched(f, ParcelFileDescriptor.MODE_WRITE_ONLY | ParcelFileDescriptor.MODE_CREATE | ParcelFileDescriptor.MODE_APPEND, notifier(documentId));
        }
        if ("rw".equals(mode)) {
            return watched(f, ParcelFileDescriptor.MODE_READ_WRITE | ParcelFileDescriptor.MODE_CREATE, notifier(documentId));
        }
        int bits;
        if ("w".equals(mode) || "wt".equals(mode)) {
            bits = ParcelFileDescriptor.MODE_WRITE_ONLY;
        } else if ("rwt".equals(mode)) {
            bits = ParcelFileDescriptor.MODE_READ_WRITE;
        } else {
            throw new FileNotFoundException("bad mode " + mode);
        }
        final File part = new File(f.getParentFile(), PART + Long.toHexString(System.nanoTime()) + "-" + f.getName());
        return watched(part, bits | ParcelFileDescriptor.MODE_CREATE | ParcelFileDescriptor.MODE_TRUNCATE, new ParcelFileDescriptor.OnCloseListener() {
            @Override
            public void onClose(IOException e) {
                if (e == null && part.renameTo(f)) {
                    changed(documentId);
                    return;
                }
                if (e != null) {
                    Log.w("OverhaulDocs", "write not finished, file kept as it was: " + f.getName(), e);
                }
                part.delete();
            }
        });
    }

    @Override
    public AssetFileDescriptor openDocumentThumbnail(String documentId, Point sizeHint, CancellationSignal signal) throws FileNotFoundException {
        File b = base();
        File f = within(b, relOf(documentId));
        if (f.equals(b) || !typeOf(f).startsWith("image/")) {
            throw new FileNotFoundException("no thumbnail");
        }
        return new AssetFileDescriptor(ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY), 0, AssetFileDescriptor.UNKNOWN_LENGTH);
    }

    private static ParcelFileDescriptor watched(File f, int bits, ParcelFileDescriptor.OnCloseListener l) throws FileNotFoundException {
        try {
            return ParcelFileDescriptor.open(f, bits, handler(), l);
        } catch (IOException e) {
            throw new FileNotFoundException(String.valueOf(e.getMessage()));
        }
    }

    private ParcelFileDescriptor.OnCloseListener notifier(final String documentId) {
        return new ParcelFileDescriptor.OnCloseListener() {
            @Override
            public void onClose(IOException e) {
                changed(documentId);
            }
        };
    }

    static File fresh(File dir, String name) {
        File f = new File(dir, name);
        if (!f.exists()) {
            return f;
        }
        int dot = name.lastIndexOf('.');
        String stem = dot > 0 ? name.substring(0, dot) : name;
        String ext = dot > 0 ? name.substring(dot) : "";
        for (int i = 1; i < 1000; i++) {
            f = new File(dir, stem + " (" + i + ")" + ext);
            if (!f.exists()) {
                return f;
            }
        }
        return null;
    }

    @Override
    public String createDocument(String parentDocumentId, String mimeType, String displayName) throws FileNotFoundException {
        File b = base();
        if (!b.isDirectory()) {
            throw new FileNotFoundException("start the game once first");
        }
        File dir = within(b, relOf(parentDocumentId));
        if (!dir.isDirectory() || !goodName(displayName)) {
            throw new FileNotFoundException("can not create " + displayName);
        }
        File f = fresh(dir, displayName);
        if (f == null) {
            throw new FileNotFoundException("too many files named " + displayName);
        }
        String id = idOf(b, within(b, (relOf(parentDocumentId).isEmpty() ? "" : relOf(parentDocumentId) + "/") + f.getName()));
        boolean ok;
        if (Document.MIME_TYPE_DIR.equals(mimeType)) {
            ok = f.mkdir();
        } else {
            try {
                ok = f.createNewFile();
            } catch (IOException e) {
                ok = false;
            }
        }
        if (!ok) {
            throw new FileNotFoundException("could not create " + displayName);
        }
        changed(id);
        return id;
    }

    static boolean wipe(File f) {
        File[] list = f.isDirectory() ? f.listFiles() : null;
        if (list != null) {
            for (File child : list) {
                boolean link;
                try {
                    link = !child.getCanonicalFile().equals(new File(f.getCanonicalFile(), child.getName()));
                } catch (IOException e) {
                    return false;
                }
                if (link) {
                    if (!child.delete()) {
                        return false;
                    }
                } else if (!wipe(child)) {
                    return false;
                }
            }
        }
        return f.delete();
    }

    @Override
    public void deleteDocument(String documentId) throws FileNotFoundException {
        File b = base();
        File f = within(b, relOf(documentId));
        if (f.equals(b)) {
            throw new FileNotFoundException("the game folder itself can not be deleted");
        }
        if (!wipe(f)) {
            changed(documentId);
            throw new FileNotFoundException("could not delete " + f.getName());
        }
        changed(documentId);
    }

    @Override
    public String renameDocument(String documentId, String displayName) throws FileNotFoundException {
        File b = base();
        File f = within(b, relOf(documentId));
        if (f.equals(b) || !goodName(displayName)) {
            throw new FileNotFoundException("can not rename to " + displayName);
        }
        String rel = relOf(documentId);
        int slash = rel.lastIndexOf('/');
        String target = (slash >= 0 ? rel.substring(0, slash + 1) : "") + displayName;
        File to = within(b, target);
        if (to.exists() || !f.renameTo(to)) {
            throw new FileNotFoundException("could not rename to " + displayName);
        }
        String id = idOf(b, to);
        changed(documentId);
        changed(id);
        return id;
    }
}

package org.love2d.android;

import java.io.File;
import java.io.FileNotFoundException;
import java.nio.file.Files;
import java.nio.file.Path;

public class DocsPathTest {
    static int fails = 0, passes = 0;

    static void refused(File base, String rel) {
        try {
            File f = OverhaulDocs.within(base, rel);
            fails++;
            System.out.println("FAIL allowed " + rel + " -> " + f);
        } catch (FileNotFoundException e) {
            passes++;
        }
    }

    static void allowed(File base, String rel, File want) throws Exception {
        try {
            File f = OverhaulDocs.within(base, rel);
            if (f.equals(want.getCanonicalFile())) { passes++; } else { fails++; System.out.println("FAIL " + rel + " -> " + f + " want " + want); }
        } catch (FileNotFoundException e) {
            fails++;
            System.out.println("FAIL refused " + rel + ": " + e.getMessage());
        }
    }

    static void badId(String id) {
        try {
            String r = OverhaulDocs.relOf(id);
            OverhaulDocs.within(BASE, r);
            fails++;
            System.out.println("FAIL id allowed " + id);
        } catch (FileNotFoundException e) {
            passes++;
        }
    }

    static void check(boolean ok, String what) {
        if (ok) passes++; else { fails++; System.out.println("FAIL " + what); }
    }

    static File BASE;

    public static void main(String[] a) throws Exception {
        Path tmp = Files.createTempDirectory("docs");
        File outside = new File(tmp.toFile(), "outside");
        outside.mkdirs();
        new File(outside, "secret.txt").createNewFile();
        File save = new File(tmp.toFile(), "save");
        File base = new File(save, "BalatroOverhaul");
        new File(base, "sub/deeper").mkdirs();
        new File(base, "a.txt").createNewFile();
        new File(base, "sub/b.lua").createNewFile();
        new File(save, "BalatroOverhaulEvil").mkdirs();
        new File(save, "BalatroOverhaulEvil/x.txt").createNewFile();
        Files.createSymbolicLink(new File(base, "link_out").toPath(), outside.toPath());
        Files.createSymbolicLink(new File(base, "file_out").toPath(), new File(outside, "secret.txt").toPath());
        Files.createSymbolicLink(new File(base, "sub/link_in").toPath(), new File(base, "a.txt").toPath());
        Files.createSymbolicLink(new File(base, "sibling").toPath(), new File(save, "BalatroOverhaulEvil").toPath());
        Files.createSymbolicLink(new File(base, "dangling").toPath(), new File(tmp.toFile(), "nothing/here").toPath());
        Files.createSymbolicLink(new File(base, "up").toPath(), new File("..").toPath());
        new File(base, ".overhaul-part-1-a.txt").createNewFile();
        base = base.getCanonicalFile();
        BASE = base;

        check(OverhaulDocs.pick(save).getName().equals("BalatroOverhaul"), "pick prefers BalatroOverhaul");
        File save2 = new File(tmp.toFile(), "save2");
        new File(save2, "ASET").mkdirs();
        new File(save2, "zzz").mkdirs();
        check(OverhaulDocs.pick(save2).getName().equals("ASET"), "pick takes the dev build folder ASET");
        new File(save2, "game").mkdirs();
        check(OverhaulDocs.pick(save2).getName().equals("game"), "pick prefers game (plain game.love build) over ASET");
        File save3 = new File(tmp.toFile(), "save3");
        check(OverhaulDocs.pick(save3).getName().equals("BalatroOverhaul"), "pick default when empty");

        allowed(base, "", base);
        allowed(base, "a.txt", new File(base, "a.txt"));
        allowed(base, "sub/b.lua", new File(base, "sub/b.lua"));
        allowed(base, "sub/deeper", new File(base, "sub/deeper"));
        allowed(base, "new file.txt", new File(base, "new file.txt"));
        allowed(base, "sub/link_in", new File(base, "a.txt"));
        allowed(base, "..hidden", new File(base, "..hidden"));
        allowed(base, "%2e%2e", new File(base, "%2e%2e"));

        String[] escapes = {
            "..", "../", "../BalatroOverhaulEvil/x.txt", "sub/../..", "sub/../../BalatroOverhaulEvil",
            "/etc/passwd", "//etc/passwd", "/", "sub//b.lua", "./a.txt", "sub/./b.lua", "a.txt/",
            "link_out", "link_out/secret.txt", "file_out", "sibling", "sibling/x.txt", "dangling", "up", "up/outside/secret.txt",
            "a\0b", "a\\..\\..\\x", "sub/\n", ".overhaul-part-1-a.txt", "..\\outside",
        };
        for (String e : escapes) refused(base, e);

        String[] ids = {"save/..", "save/../BalatroOverhaulEvil", "other/a.txt", "savex/a.txt", "save:a.txt", "", "/save/a.txt", "save//etc", null, "save/link_out/secret.txt"};
        for (String id : ids) badId(id);
        check(OverhaulDocs.relOf("save").isEmpty(), "root id");
        check(OverhaulDocs.relOf("save/sub/b.lua").equals("sub/b.lua"), "child id");
        check(OverhaulDocs.idOf(base, new File(base, "sub/b.lua")).equals("save/sub/b.lua"), "idOf child");
        check(OverhaulDocs.idOf(base, base).equals("save"), "idOf root");

        check(OverhaulDocs.goodName("save.jkr"), "name ok");
        check(!OverhaulDocs.goodName("a/b"), "slash name");
        check(!OverhaulDocs.goodName(".."), "dotdot name");
        check(!OverhaulDocs.goodName(""), "empty name");
        check(!OverhaulDocs.goodName(null), "null name");
        check(!OverhaulDocs.goodName(new String(new char[256]).replace('\0', 'x')), "long name");

        check(OverhaulDocs.typeOf(new File(base, "sub/b.lua")).equals("text/x-lua"), "lua type");
        check(OverhaulDocs.typeOf(new File(base, "x.JSON")).equals("application/json"), "json type");
        check(OverhaulDocs.typeOf(new File(base, "save.jkr")).equals("application/octet-stream"), "jkr type");
        check(OverhaulDocs.typeOf(new File(base, "Jokers.png")).equals("image/png"), "png type");
        check(OverhaulDocs.typeOf(new File(base, "mods.zip")).equals("application/zip"), "zip type");
        check(OverhaulDocs.typeOf(new File(base, "a.txt")).equals("text/plain"), "txt type");
        check(OverhaulDocs.typeOf(new File(base, "noext")).equals("application/octet-stream"), "no ext");
        check(OverhaulDocs.typeOf(new File(base, "weird.qqq")).equals("application/octet-stream"), "unknown ext");

        File d = new File(base, "sub/deeper");
        new File(d, "f.txt").createNewFile();
        Files.createSymbolicLink(new File(d, "keep_out").toPath(), outside.toPath());
        check(OverhaulDocs.wipe(new File(base, "sub").getCanonicalFile()), "wipe sub");
        check(!new File(base, "sub").exists(), "sub gone");
        check(new File(outside, "secret.txt").exists(), "outside file kept after wipe through a symlink");
        check(new File(base, "a.txt").exists(), "a.txt kept (sub/link_in only removed the link)");

        File f1 = OverhaulDocs.fresh(base, "a.txt");
        check(f1 != null && f1.getName().equals("a (1).txt"), "fresh name " + f1);

        Files.walk(tmp).sorted(java.util.Comparator.reverseOrder()).forEach(p -> p.toFile().delete());
        System.out.println("passes=" + passes + " fails=" + fails);
        System.exit(fails == 0 ? 0 : 1);
    }
}

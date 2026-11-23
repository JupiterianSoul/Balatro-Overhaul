package org.love2d.android;

import android.view.Display;
import java.lang.reflect.Constructor;


public class HighRefreshRateTest {
    static int failures = 0, passes = 0;

    static void check(boolean passed, String description) {
        if (passed) passes++; else { failures++; System.out.println("FAIL " + description); }
    }

    static Display.Mode mode(int modeId, int width, int height, float refreshRate) throws Exception {
        Constructor<Display.Mode> modeConstructor = Display.Mode.class.getDeclaredConstructor(int.class, int.class, int.class, float.class);
        modeConstructor.setAccessible(true);
        return modeConstructor.newInstance(modeId, width, height, refreshRate);
    }

    static int pickedModeId(Display.Mode currentMode, Display.Mode[] supportedModes) {
        Display.Mode pickedMode = HighRefreshRate.pickMode(currentMode, supportedModes);
        return pickedMode == null ? -1 : pickedMode.getModeId();
    }

    public static void main(String[] arguments) throws Exception {
        Display.Mode fullResolution120Hz = mode(1, 1344, 2992, 120f), resolution1080p120Hz = mode(2, 1080, 2404, 120f);
        Display.Mode fullResolution60Hz = mode(3, 1344, 2992, 60f), resolution1080p60Hz = mode(4, 1080, 2404, 60f);
        Display.Mode[] pixelModes = {fullResolution120Hz, resolution1080p120Hz, fullResolution60Hz, resolution1080p60Hz};
        check(pickedModeId(resolution1080p60Hz, pixelModes) == 2, "phone at 1080p 60 Hz picks 1080p 120 Hz, not full resolution");
        check(pickedModeId(resolution1080p120Hz, pixelModes) == 2, "phone at 1080p 120 Hz keeps 1080p");
        check(pickedModeId(fullResolution60Hz, pixelModes) == 1, "phone at full resolution picks full resolution 120 Hz");

        Display.Mode[] highRateOnlyAtOtherResolution = {mode(1, 1344, 2992, 120f), mode(2, 1080, 2404, 60f)};
        check(pickedModeId(highRateOnlyAtOtherResolution[1], highRateOnlyAtOtherResolution) == 2, "never switches resolution for a higher refresh rate");

        Display.Mode[] singleMode = {mode(1, 1080, 2400, 90f)};
        check(pickedModeId(singleMode[0], singleMode) == 1, "single mode is kept");
        check(pickedModeId(mode(9, 720, 1600, 60f), singleMode) == -1, "no mode at the current resolution picks nothing");
        check(pickedModeId(resolution1080p60Hz, new Display.Mode[0]) == -1, "no modes picks nothing");

        System.out.println("passes=" + passes + " fails=" + failures);
        System.exit(failures == 0 ? 0 : 1);
    }
}

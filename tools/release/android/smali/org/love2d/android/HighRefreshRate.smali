.class public Lorg/love2d/android/HighRefreshRate;
.super Ljava/lang/Object;
.source "HighRefreshRate.java"


.field private static appliedModeHz:F

.field private static appliedSurfaceHz:F


.method static constructor <clinit>()V
    .locals 1

    const/4 v0, 0x0
    sput v0, Lorg/love2d/android/HighRefreshRate;->appliedModeHz:F
    sput v0, Lorg/love2d/android/HighRefreshRate;->appliedSurfaceHz:F

    return-void
.end method

.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static apply(Landroid/app/Activity;)V
    .locals 12
    .param p0, "activity"

    const-string v0, "HighRefreshRate"

    sget v1, Landroid/os/Build$VERSION;->SDK_INT:I
    const/16 v2, 0x17    # 23
    if-ge v1, v2, :cond_api_ok

    const-string v1, "API < 23, skipping preferredDisplayModeId"
    invoke-static {v0, v1}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
    return-void

    :cond_api_ok
    :try_start_0
    invoke-virtual {p0}, Landroid/app/Activity;->getWindow()Landroid/view/Window;
    move-result-object v1

    invoke-virtual {p0}, Landroid/app/Activity;->getWindowManager()Landroid/view/WindowManager;
    move-result-object v2
    invoke-interface {v2}, Landroid/view/WindowManager;->getDefaultDisplay()Landroid/view/Display;
    move-result-object v2

    invoke-virtual {v2}, Landroid/view/Display;->getRefreshRate()F
    move-result v3

    new-instance v4, Ljava/lang/StringBuilder;
    invoke-direct {v4}, Ljava/lang/StringBuilder;-><init>()V
    const-string v5, "Current display refresh rate: "
    invoke-virtual {v4, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v4, v3}, Ljava/lang/StringBuilder;->append(F)Ljava/lang/StringBuilder;
    const-string v5, " Hz"
    invoke-virtual {v4, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v4}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v4
    invoke-static {v0, v4}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    invoke-virtual {v2}, Landroid/view/Display;->getSupportedModes()[Landroid/view/Display$Mode;
    move-result-object v4

    const/4 v5, 0x0         # bestHz = 0.0f
    const/4 v6, -0x1        # bestModeId = -1

    array-length v7, v4
    const/4 v8, 0x0          # i = 0

    :loop_start
    if-ge v8, v7, :loop_end

    aget-object v9, v4, v8

    invoke-virtual {v9}, Landroid/view/Display$Mode;->getModeId()I
    move-result v10
    invoke-virtual {v9}, Landroid/view/Display$Mode;->getRefreshRate()F
    move-result v11

    new-instance v3, Ljava/lang/StringBuilder;
    invoke-direct {v3}, Ljava/lang/StringBuilder;-><init>()V
    const-string v2, "  Mode "
    invoke-virtual {v3, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v3, v10}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    const-string v2, ": "
    invoke-virtual {v3, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v9}, Landroid/view/Display$Mode;->getPhysicalWidth()I
    move-result v2
    invoke-virtual {v3, v2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    const-string v2, "x"
    invoke-virtual {v3, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v9}, Landroid/view/Display$Mode;->getPhysicalHeight()I
    move-result v2
    invoke-virtual {v3, v2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    const-string v2, " @ "
    invoke-virtual {v3, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v3, v11}, Ljava/lang/StringBuilder;->append(F)Ljava/lang/StringBuilder;
    const-string v2, " Hz"
    invoke-virtual {v3, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v3}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v3
    invoke-static {v0, v3}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    cmpg-float v3, v11, v5
    if-lez v3, :cond_not_best

    move v5, v11          # bestHz = modeHz
    move v6, v10          # bestModeId = modeId

    :cond_not_best
    add-int/lit8 v8, v8, 0x1
    goto :loop_start

    :loop_end

    const/high16 v2, 0x42700000    # 60.0f
    cmpg-float v3, v5, v2
    if-lez v3, :cond_no_high_hz

    invoke-virtual {v1}, Landroid/view/Window;->getAttributes()Landroid/view/WindowManager$LayoutParams;
    move-result-object v2

    iput v6, v2, Landroid/view/WindowManager$LayoutParams;->preferredDisplayModeId:I

    invoke-virtual {v1, v2}, Landroid/view/Window;->setAttributes(Landroid/view/WindowManager$LayoutParams;)V

    sput v5, Lorg/love2d/android/HighRefreshRate;->appliedModeHz:F

    new-instance v3, Ljava/lang/StringBuilder;
    invoke-direct {v3}, Ljava/lang/StringBuilder;-><init>()V
    const-string v4, "Applied preferredDisplayModeId="
    invoke-virtual {v3, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v3, v6}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    const-string v4, " ("
    invoke-virtual {v3, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v3, v5}, Ljava/lang/StringBuilder;->append(F)Ljava/lang/StringBuilder;
    const-string v4, " Hz)"
    invoke-virtual {v3, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v3}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v3
    invoke-static {v0, v3}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    goto :goto_done

    :cond_no_high_hz
    const-string v2, "No high refresh rate modes found (max 60 Hz)"
    invoke-static {v0, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    :goto_done
    :try_end_0
    .catch Ljava/lang/Exception; {:try_start_0 .. :try_end_0} :catch_0

    return-void

    :catch_0
    move-exception v1

    new-instance v2, Ljava/lang/StringBuilder;
    invoke-direct {v2}, Ljava/lang/StringBuilder;-><init>()V
    const-string v3, "Error applying high refresh rate mode: "
    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v1}, Ljava/lang/Exception;->getMessage()Ljava/lang/String;
    move-result-object v1
    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v1
    invoke-static {v0, v1}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I

    return-void
.end method


.method public static applySurface(Landroid/view/Surface;)V
    .locals 5
    .param p0, "surface"

    const-string v0, "HighRefreshRate"

    if-nez p0, :cond_surface_ok
    const-string v1, "applySurface: surface is null, skipping"
    invoke-static {v0, v1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;)I
    return-void

    :cond_surface_ok
    sget v1, Landroid/os/Build$VERSION;->SDK_INT:I
    const/16 v2, 0x1e    # 30
    if-ge v1, v2, :cond_api30_ok

    new-instance v2, Ljava/lang/StringBuilder;
    invoke-direct {v2}, Ljava/lang/StringBuilder;-><init>()V
    const-string v3, "API "
    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    const-string v3, " < 30, skipping Surface.setFrameRate()"
    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v2
    invoke-static {v0, v2}, Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I
    return-void

    :cond_api30_ok
    :try_start_0
    const/high16 v1, 0x42f00000    # 120.0f
    const/4 v2, 0x0                # FRAME_RATE_COMPATIBILITY_DEFAULT

    invoke-virtual {p0, v1, v2}, Landroid/view/Surface;->setFrameRate(FI)V

    sput v1, Lorg/love2d/android/HighRefreshRate;->appliedSurfaceHz:F

    const-string v3, "Applied Surface.setFrameRate(120.0, COMPATIBILITY_DEFAULT)"
    invoke-static {v0, v3}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
    :try_end_0
    .catch Ljava/lang/Exception; {:try_start_0 .. :try_end_0} :catch_0

    return-void

    :catch_0
    move-exception v1

    new-instance v2, Ljava/lang/StringBuilder;
    invoke-direct {v2}, Ljava/lang/StringBuilder;-><init>()V
    const-string v3, "Error calling Surface.setFrameRate(): "
    invoke-virtual {v2, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v1}, Ljava/lang/Exception;->getMessage()Ljava/lang/String;
    move-result-object v1
    invoke-virtual {v2, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v1
    invoke-static {v0, v1}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I

    return-void
.end method


.method public static getAppliedModeHz()F
    .locals 1

    sget v0, Lorg/love2d/android/HighRefreshRate;->appliedModeHz:F
    return v0
.end method


.method public static getAppliedSurfaceHz()F
    .locals 1

    sget v0, Lorg/love2d/android/HighRefreshRate;->appliedSurfaceHz:F
    return v0
.end method

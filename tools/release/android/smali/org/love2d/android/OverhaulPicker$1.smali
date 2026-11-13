.class Lorg/love2d/android/OverhaulPicker$1;
.super Ljava/lang/Object;

.implements Ljava/lang/Runnable;

.annotation system Ldalvik/annotation/EnclosingMethod;
    value = Lorg/love2d/android/OverhaulPicker;->onActivityResult(IILandroid/content/Intent;)V
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x0
    name = null
.end annotation

.field final synthetic this$0:Lorg/love2d/android/OverhaulPicker;

.field final synthetic val$uris:Ljava/util/List;

.method constructor <init>(Lorg/love2d/android/OverhaulPicker;Ljava/util/List;)V
    .locals 0
    .annotation system Ldalvik/annotation/MethodParameters;
        accessFlags = {
            0x8010,
            0x1010
        }
        names = {
            null,
            null
        }
    .end annotation

    .annotation system Ldalvik/annotation/Signature;
        value = {
            "()V"
        }
    .end annotation

    iput-object p2, p0, Lorg/love2d/android/OverhaulPicker$1;->val$uris:Ljava/util/List;

    iput-object p1, p0, Lorg/love2d/android/OverhaulPicker$1;->this$0:Lorg/love2d/android/OverhaulPicker;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public run()V
    .locals 3

    :try_start_0
    iget-object v0, p0, Lorg/love2d/android/OverhaulPicker$1;->this$0:Lorg/love2d/android/OverhaulPicker;

    iget-object v1, p0, Lorg/love2d/android/OverhaulPicker$1;->val$uris:Ljava/util/List;

    invoke-static {v0, v1}, Lorg/love2d/android/OverhaulPicker;->access$000(Lorg/love2d/android/OverhaulPicker;Ljava/util/List;)Ljava/lang/String;

    move-result-object v0
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_0

    goto :goto_0

    :catchall_0
    move-exception v0

    const-string v1, "OverhaulPicker"

    const-string v2, "failed"

    invoke-static {v1, v2, v0}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    const-string v0, "error\n"

    :goto_0
    iget-object v1, p0, Lorg/love2d/android/OverhaulPicker$1;->this$0:Lorg/love2d/android/OverhaulPicker;

    new-instance v2, Lorg/love2d/android/OverhaulPicker$1$1;

    invoke-direct {v2, p0, v0}, Lorg/love2d/android/OverhaulPicker$1$1;-><init>(Lorg/love2d/android/OverhaulPicker$1;Ljava/lang/String;)V

    invoke-virtual {v1, v2}, Lorg/love2d/android/OverhaulPicker;->runOnUiThread(Ljava/lang/Runnable;)V

    return-void
.end method

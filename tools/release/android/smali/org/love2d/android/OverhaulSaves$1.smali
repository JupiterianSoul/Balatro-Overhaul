.class Lorg/love2d/android/OverhaulSaves$1;
.super Ljava/lang/Object;

.implements Ljava/lang/Runnable;

.annotation system Ldalvik/annotation/EnclosingMethod;
    value = Lorg/love2d/android/OverhaulSaves;->onActivityResult(IILandroid/content/Intent;)V
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x0
    name = null
.end annotation

.field final synthetic this$0:Lorg/love2d/android/OverhaulSaves;

.field final synthetic val$uri:Landroid/net/Uri;

.method constructor <init>(Lorg/love2d/android/OverhaulSaves;Landroid/net/Uri;)V
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

    iput-object p2, p0, Lorg/love2d/android/OverhaulSaves$1;->val$uri:Landroid/net/Uri;

    iput-object p1, p0, Lorg/love2d/android/OverhaulSaves$1;->this$0:Lorg/love2d/android/OverhaulSaves;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public run()V
    .locals 3

    :try_start_0
    const-string v0, "export"

    iget-object v1, p0, Lorg/love2d/android/OverhaulSaves$1;->this$0:Lorg/love2d/android/OverhaulSaves;

    invoke-static {v1}, Lorg/love2d/android/OverhaulSaves;->access$000(Lorg/love2d/android/OverhaulSaves;)Ljava/lang/String;

    move-result-object v1

    invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0
    :try_end_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_0

    iget-object v1, p0, Lorg/love2d/android/OverhaulSaves$1;->this$0:Lorg/love2d/android/OverhaulSaves;

    if-eqz v0, :cond_0

    :try_start_1
    iget-object v0, p0, Lorg/love2d/android/OverhaulSaves$1;->val$uri:Landroid/net/Uri;

    invoke-static {v1, v0}, Lorg/love2d/android/OverhaulSaves;->access$100(Lorg/love2d/android/OverhaulSaves;Landroid/net/Uri;)[Ljava/lang/String;

    move-result-object v0

    goto :goto_0

    :cond_0
    iget-object v0, p0, Lorg/love2d/android/OverhaulSaves$1;->val$uri:Landroid/net/Uri;

    invoke-static {v1, v0}, Lorg/love2d/android/OverhaulSaves;->access$200(Lorg/love2d/android/OverhaulSaves;Landroid/net/Uri;)[Ljava/lang/String;

    move-result-object v0
    :try_end_1
    .catchall {:try_start_1 .. :try_end_1} :catchall_0

    goto :goto_0

    :catchall_0
    move-exception v0

    const-string v1, "OverhaulSaves"

    const-string v2, "failed"

    invoke-static {v1, v2, v0}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    const/4 v0, 0x3

    new-array v0, v0, [Ljava/lang/String;

    const/4 v1, 0x0

    const-string v2, "error"

    aput-object v2, v0, v1

    const/4 v1, 0x1

    const/4 v2, 0x0

    aput-object v2, v0, v1

    const/4 v1, 0x2

    aput-object v2, v0, v1

    :goto_0
    iget-object v1, p0, Lorg/love2d/android/OverhaulSaves$1;->this$0:Lorg/love2d/android/OverhaulSaves;

    new-instance v2, Lorg/love2d/android/OverhaulSaves$1$1;

    invoke-direct {v2, p0, v0}, Lorg/love2d/android/OverhaulSaves$1$1;-><init>(Lorg/love2d/android/OverhaulSaves$1;[Ljava/lang/String;)V

    invoke-virtual {v1, v2}, Lorg/love2d/android/OverhaulSaves;->runOnUiThread(Ljava/lang/Runnable;)V

    return-void
.end method

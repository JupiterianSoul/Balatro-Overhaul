.class Lorg/love2d/android/OverhaulSaves$1$1;
.super Ljava/lang/Object;

.implements Ljava/lang/Runnable;

.annotation system Ldalvik/annotation/EnclosingMethod;
    value = Lorg/love2d/android/OverhaulSaves$1;->run()V
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x0
    name = null
.end annotation

.field final synthetic this$1:Lorg/love2d/android/OverhaulSaves$1;

.field final synthetic val$res:[Ljava/lang/String;

.method constructor <init>(Lorg/love2d/android/OverhaulSaves$1;[Ljava/lang/String;)V
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

    iput-object p2, p0, Lorg/love2d/android/OverhaulSaves$1$1;->val$res:[Ljava/lang/String;

    iput-object p1, p0, Lorg/love2d/android/OverhaulSaves$1$1;->this$1:Lorg/love2d/android/OverhaulSaves$1;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public run()V
    .locals 6

    iget-object v0, p0, Lorg/love2d/android/OverhaulSaves$1$1;->val$res:[Ljava/lang/String;

    const/4 v1, 0x0

    aget-object v0, v0, v1

    const-string v2, "ok"

    invoke-virtual {v2, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :cond_0

    iget-object v0, p0, Lorg/love2d/android/OverhaulSaves$1$1;->this$1:Lorg/love2d/android/OverhaulSaves$1;

    iget-object v0, v0, Lorg/love2d/android/OverhaulSaves$1;->this$0:Lorg/love2d/android/OverhaulSaves;

    invoke-static {v0}, Lorg/love2d/android/OverhaulSaves;->access$000(Lorg/love2d/android/OverhaulSaves;)Ljava/lang/String;

    move-result-object v0

    const-string v2, "import"

    invoke-virtual {v2, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    if-eqz v0, :cond_0

    iget-object v0, p0, Lorg/love2d/android/OverhaulSaves$1$1;->this$1:Lorg/love2d/android/OverhaulSaves$1;

    iget-object v0, v0, Lorg/love2d/android/OverhaulSaves$1;->this$0:Lorg/love2d/android/OverhaulSaves;

    invoke-static {v0}, Lorg/love2d/android/OverhaulSaves;->access$300(Lorg/love2d/android/OverhaulSaves;)Landroid/net/Uri;

    move-result-object v0

    goto :goto_0

    :cond_0
    const/4 v0, 0x0

    :goto_0
    iget-object v2, p0, Lorg/love2d/android/OverhaulSaves$1$1;->this$1:Lorg/love2d/android/OverhaulSaves$1;

    iget-object v2, v2, Lorg/love2d/android/OverhaulSaves$1;->this$0:Lorg/love2d/android/OverhaulSaves;

    iget-object v3, p0, Lorg/love2d/android/OverhaulSaves$1$1;->val$res:[Ljava/lang/String;

    aget-object v1, v3, v1

    const/4 v4, 0x1

    aget-object v4, v3, v4

    const/4 v5, 0x2

    aget-object v3, v3, v5

    invoke-static {v2, v1, v4, v3, v0}, Lorg/love2d/android/OverhaulSaves;->access$400(Lorg/love2d/android/OverhaulSaves;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Landroid/net/Uri;)V

    return-void
.end method

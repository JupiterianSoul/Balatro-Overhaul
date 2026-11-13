.class Lorg/love2d/android/OverhaulPicker$1$1;
.super Ljava/lang/Object;

.implements Ljava/lang/Runnable;

.annotation system Ldalvik/annotation/EnclosingMethod;
    value = Lorg/love2d/android/OverhaulPicker$1;->run()V
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x0
    name = null
.end annotation

.field final synthetic this$1:Lorg/love2d/android/OverhaulPicker$1;

.field final synthetic val$text:Ljava/lang/String;

.method constructor <init>(Lorg/love2d/android/OverhaulPicker$1;Ljava/lang/String;)V
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

    iput-object p2, p0, Lorg/love2d/android/OverhaulPicker$1$1;->val$text:Ljava/lang/String;

    iput-object p1, p0, Lorg/love2d/android/OverhaulPicker$1$1;->this$1:Lorg/love2d/android/OverhaulPicker$1;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public run()V
    .locals 2

    iget-object v0, p0, Lorg/love2d/android/OverhaulPicker$1$1;->this$1:Lorg/love2d/android/OverhaulPicker$1;

    iget-object v0, v0, Lorg/love2d/android/OverhaulPicker$1;->this$0:Lorg/love2d/android/OverhaulPicker;

    iget-object v1, p0, Lorg/love2d/android/OverhaulPicker$1$1;->val$text:Ljava/lang/String;

    invoke-static {v0, v1}, Lorg/love2d/android/OverhaulPicker;->access$100(Lorg/love2d/android/OverhaulPicker;Ljava/lang/String;)V

    return-void
.end method

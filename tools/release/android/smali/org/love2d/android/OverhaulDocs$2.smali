.class Lorg/love2d/android/OverhaulDocs$2;
.super Ljava/lang/Object;

.implements Landroid/os/ParcelFileDescriptor$OnCloseListener;

.annotation system Ldalvik/annotation/EnclosingMethod;
    value = Lorg/love2d/android/OverhaulDocs;->notifier(Ljava/lang/String;)Landroid/os/ParcelFileDescriptor$OnCloseListener;
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x0
    name = null
.end annotation

.field final synthetic this$0:Lorg/love2d/android/OverhaulDocs;

.field final synthetic val$documentId:Ljava/lang/String;

.method constructor <init>(Lorg/love2d/android/OverhaulDocs;Ljava/lang/String;)V
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

    iput-object p2, p0, Lorg/love2d/android/OverhaulDocs$2;->val$documentId:Ljava/lang/String;

    iput-object p1, p0, Lorg/love2d/android/OverhaulDocs$2;->this$0:Lorg/love2d/android/OverhaulDocs;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public onClose(Ljava/io/IOException;)V
    .locals 1

    iget-object p1, p0, Lorg/love2d/android/OverhaulDocs$2;->this$0:Lorg/love2d/android/OverhaulDocs;

    iget-object v0, p0, Lorg/love2d/android/OverhaulDocs$2;->val$documentId:Ljava/lang/String;

    invoke-static {p1, v0}, Lorg/love2d/android/OverhaulDocs;->access$000(Lorg/love2d/android/OverhaulDocs;Ljava/lang/String;)V

    return-void
.end method

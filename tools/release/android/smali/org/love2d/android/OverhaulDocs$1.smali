.class Lorg/love2d/android/OverhaulDocs$1;
.super Ljava/lang/Object;

.implements Landroid/os/ParcelFileDescriptor$OnCloseListener;

.annotation system Ldalvik/annotation/EnclosingMethod;
    value = Lorg/love2d/android/OverhaulDocs;->openDocument(Ljava/lang/String;Ljava/lang/String;Landroid/os/CancellationSignal;)Landroid/os/ParcelFileDescriptor;
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x0
    name = null
.end annotation

.field final synthetic this$0:Lorg/love2d/android/OverhaulDocs;

.field final synthetic val$documentId:Ljava/lang/String;

.field final synthetic val$f:Ljava/io/File;

.field final synthetic val$part:Ljava/io/File;

.method constructor <init>(Lorg/love2d/android/OverhaulDocs;Ljava/io/File;Ljava/io/File;Ljava/lang/String;)V
    .locals 0
    .annotation system Ldalvik/annotation/MethodParameters;
        accessFlags = {
            0x8010,
            0x1010,
            0x1010,
            0x1010
        }
        names = {
            null,
            null,
            null,
            null
        }
    .end annotation

    .annotation system Ldalvik/annotation/Signature;
        value = {
            "()V"
        }
    .end annotation

    iput-object p2, p0, Lorg/love2d/android/OverhaulDocs$1;->val$part:Ljava/io/File;

    iput-object p3, p0, Lorg/love2d/android/OverhaulDocs$1;->val$f:Ljava/io/File;

    iput-object p4, p0, Lorg/love2d/android/OverhaulDocs$1;->val$documentId:Ljava/lang/String;

    iput-object p1, p0, Lorg/love2d/android/OverhaulDocs$1;->this$0:Lorg/love2d/android/OverhaulDocs;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public onClose(Ljava/io/IOException;)V
    .locals 2

    if-nez p1, :cond_0

    iget-object v0, p0, Lorg/love2d/android/OverhaulDocs$1;->val$part:Ljava/io/File;

    iget-object v1, p0, Lorg/love2d/android/OverhaulDocs$1;->val$f:Ljava/io/File;

    invoke-virtual {v0, v1}, Ljava/io/File;->renameTo(Ljava/io/File;)Z

    move-result v0

    if-eqz v0, :cond_0

    iget-object p1, p0, Lorg/love2d/android/OverhaulDocs$1;->this$0:Lorg/love2d/android/OverhaulDocs;

    iget-object v0, p0, Lorg/love2d/android/OverhaulDocs$1;->val$documentId:Ljava/lang/String;

    invoke-static {p1, v0}, Lorg/love2d/android/OverhaulDocs;->access$000(Lorg/love2d/android/OverhaulDocs;Ljava/lang/String;)V

    return-void

    :cond_0
    if-eqz p1, :cond_1

    new-instance v0, Ljava/lang/StringBuilder;

    const-string v1, "write not finished, file kept as it was: "

    invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    iget-object v1, p0, Lorg/love2d/android/OverhaulDocs$1;->val$f:Ljava/io/File;

    invoke-virtual {v1}, Ljava/io/File;->getName()Ljava/lang/String;

    move-result-object v1

    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    const-string v1, "OverhaulDocs"

    invoke-static {v1, v0, p1}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    :cond_1
    iget-object p1, p0, Lorg/love2d/android/OverhaulDocs$1;->val$part:Ljava/io/File;

    invoke-virtual {p1}, Ljava/io/File;->delete()Z

    return-void
.end method

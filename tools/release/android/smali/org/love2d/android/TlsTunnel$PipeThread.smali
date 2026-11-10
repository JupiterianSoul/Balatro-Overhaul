.class Lorg/love2d/android/TlsTunnel$PipeThread;
.super Ljava/lang/Thread;
.source "TlsTunnel.java"

.annotation system Ldalvik/annotation/EnclosingClass;
    value = Lorg/love2d/android/TlsTunnel;
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x8
    name = "PipeThread"
.end annotation


.field private final in:Ljava/io/InputStream;

.field private final out:Ljava/io/OutputStream;


.method constructor <init>(Ljava/io/InputStream;Ljava/io/OutputStream;)V
    .locals 1

    const-string v0, "TlsTunnel-down"

    invoke-direct {p0, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/String;)V

    iput-object p1, p0, Lorg/love2d/android/TlsTunnel$PipeThread;->in:Ljava/io/InputStream;

    iput-object p2, p0, Lorg/love2d/android/TlsTunnel$PipeThread;->out:Ljava/io/OutputStream;

    const/4 v0, 0x1

    invoke-virtual {p0, v0}, Ljava/lang/Thread;->setDaemon(Z)V

    return-void
.end method


.method public run()V
    .locals 2

    iget-object v0, p0, Lorg/love2d/android/TlsTunnel$PipeThread;->in:Ljava/io/InputStream;

    iget-object v1, p0, Lorg/love2d/android/TlsTunnel$PipeThread;->out:Ljava/io/OutputStream;

    invoke-static {v0, v1}, Lorg/love2d/android/TlsTunnel;->pipe(Ljava/io/InputStream;Ljava/io/OutputStream;)V

    return-void
.end method

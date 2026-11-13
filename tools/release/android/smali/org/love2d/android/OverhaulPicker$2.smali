.class Lorg/love2d/android/OverhaulPicker$2;
.super Ljava/lang/Object;

.implements Ljava/lang/Runnable;

.annotation system Ldalvik/annotation/EnclosingMethod;
    value = Lorg/love2d/android/OverhaulPicker;->appResult(Landroid/content/Intent;)V
.end annotation

.annotation system Ldalvik/annotation/InnerClass;
    accessFlags = 0x0
    name = null
.end annotation

.field final synthetic this$0:Lorg/love2d/android/OverhaulPicker;

.field final synthetic val$name:Ljava/lang/String;

.field final synthetic val$token:Ljava/lang/String;

.field final synthetic val$uri:Landroid/net/Uri;

.method constructor <init>(Lorg/love2d/android/OverhaulPicker;Landroid/net/Uri;Ljava/lang/String;Ljava/lang/String;)V
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

    iput-object p2, p0, Lorg/love2d/android/OverhaulPicker$2;->val$uri:Landroid/net/Uri;

    iput-object p3, p0, Lorg/love2d/android/OverhaulPicker$2;->val$token:Ljava/lang/String;

    iput-object p4, p0, Lorg/love2d/android/OverhaulPicker$2;->val$name:Ljava/lang/String;

    iput-object p1, p0, Lorg/love2d/android/OverhaulPicker$2;->this$0:Lorg/love2d/android/OverhaulPicker;

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public run()V
    .locals 10

    const-string v0, "\n"

    const-string v1, "error\n"

    const-string v2, "@"

    const-string v3, "ok\n+app_import.zip\n#"

    const-string v4, ".part-app-"

    :try_start_0
    iget-object v5, p0, Lorg/love2d/android/OverhaulPicker$2;->this$0:Lorg/love2d/android/OverhaulPicker;

    invoke-virtual {v5}, Lorg/love2d/android/OverhaulPicker;->getIntent()Landroid/content/Intent;

    move-result-object v6

    const-string v7, "dest"

    invoke-virtual {v6, v7}, Landroid/content/Intent;->getStringExtra(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v6

    invoke-static {v5, v6}, Lorg/love2d/android/OverhaulPicker;->inside(Landroid/content/Context;Ljava/lang/String;)Ljava/io/File;

    move-result-object v5

    if-eqz v5, :cond_4

    invoke-virtual {v5}, Ljava/io/File;->isDirectory()Z

    move-result v6

    if-nez v6, :cond_0

    invoke-virtual {v5}, Ljava/io/File;->mkdirs()Z

    move-result v6

    if-nez v6, :cond_0

    goto/16 :goto_1

    :cond_0
    new-instance v6, Ljava/io/File;

    new-instance v7, Ljava/lang/StringBuilder;

    invoke-direct {v7, v4}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    invoke-static {}, Ljava/lang/System;->nanoTime()J

    move-result-wide v8

    invoke-virtual {v7, v8, v9}, Ljava/lang/StringBuilder;->append(J)Ljava/lang/StringBuilder;

    invoke-virtual {v7}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v4

    invoke-direct {v6, v5, v4}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V

    new-instance v4, Ljava/io/File;

    const-string v7, "app_import.zip"

    invoke-direct {v4, v5, v7}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V

    iget-object v5, p0, Lorg/love2d/android/OverhaulPicker$2;->this$0:Lorg/love2d/android/OverhaulPicker;

    invoke-virtual {v5}, Lorg/love2d/android/OverhaulPicker;->getContentResolver()Landroid/content/ContentResolver;

    move-result-object v5

    iget-object v7, p0, Lorg/love2d/android/OverhaulPicker$2;->val$uri:Landroid/net/Uri;

    invoke-virtual {v5, v7}, Landroid/content/ContentResolver;->openInputStream(Landroid/net/Uri;)Ljava/io/InputStream;

    move-result-object v5
    :try_end_0
    .catch Lorg/love2d/android/OverhaulPicker$TooBig; {:try_start_0 .. :try_end_0} :catch_0
    .catchall {:try_start_0 .. :try_end_0} :catchall_2

    if-nez v5, :cond_1

    goto :goto_1

    :cond_1
    :try_start_1
    new-instance v7, Ljava/io/FileOutputStream;

    invoke-direct {v7, v6}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
    :try_end_1
    .catchall {:try_start_1 .. :try_end_1} :catchall_1

    const-wide/32 v8, 0x6000000

    :try_start_2
    invoke-static {v5, v7, v8, v9}, Lorg/love2d/android/OverhaulPicker;->access$200(Ljava/io/InputStream;Ljava/io/OutputStream;J)V
    :try_end_2
    .catchall {:try_start_2 .. :try_end_2} :catchall_0

    :try_start_3
    invoke-virtual {v7}, Ljava/io/OutputStream;->close()V
    :try_end_3
    .catchall {:try_start_3 .. :try_end_3} :catchall_1

    :try_start_4
    invoke-virtual {v5}, Ljava/io/InputStream;->close()V

    invoke-virtual {v4}, Ljava/io/File;->delete()Z

    invoke-virtual {v6, v4}, Ljava/io/File;->renameTo(Ljava/io/File;)Z

    move-result v4

    if-eqz v4, :cond_3

    new-instance v4, Ljava/lang/StringBuilder;

    invoke-direct {v4, v3}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    iget-object v3, p0, Lorg/love2d/android/OverhaulPicker$2;->val$token:Ljava/lang/String;

    invoke-virtual {v4, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v4, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    iget-object v3, p0, Lorg/love2d/android/OverhaulPicker$2;->val$name:Ljava/lang/String;

    if-eqz v3, :cond_2

    new-instance v3, Ljava/lang/StringBuilder;

    invoke-direct {v3, v2}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V

    iget-object v2, p0, Lorg/love2d/android/OverhaulPicker$2;->val$name:Ljava/lang/String;

    invoke-static {v2}, Lorg/love2d/android/OverhaulPicker;->clean(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v2

    invoke-virtual {v3, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v3, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v3}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    goto :goto_0

    :cond_2
    const-string v0, ""

    :goto_0
    invoke-virtual {v4, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v4}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    move-object v1, v0

    goto :goto_1

    :cond_3
    invoke-virtual {v6}, Ljava/io/File;->delete()Z
    :try_end_4
    .catch Lorg/love2d/android/OverhaulPicker$TooBig; {:try_start_4 .. :try_end_4} :catch_0
    .catchall {:try_start_4 .. :try_end_4} :catchall_2

    goto :goto_1

    :catchall_0
    move-exception v0

    :try_start_5
    invoke-virtual {v7}, Ljava/io/OutputStream;->close()V

    throw v0
    :try_end_5
    .catchall {:try_start_5 .. :try_end_5} :catchall_1

    :catchall_1
    move-exception v0

    :try_start_6
    invoke-virtual {v5}, Ljava/io/InputStream;->close()V

    throw v0
    :try_end_6
    .catch Lorg/love2d/android/OverhaulPicker$TooBig; {:try_start_6 .. :try_end_6} :catch_0
    .catchall {:try_start_6 .. :try_end_6} :catchall_2

    :catchall_2
    move-exception v0

    const-string v2, "OverhaulPicker"

    const-string v3, "app import copy failed"

    invoke-static {v2, v3, v0}, Landroid/util/Log;->w(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I

    goto :goto_1

    :catch_0
    const-string v1, "big\n"

    :cond_4
    :goto_1
    iget-object v0, p0, Lorg/love2d/android/OverhaulPicker$2;->this$0:Lorg/love2d/android/OverhaulPicker;

    new-instance v2, Lorg/love2d/android/OverhaulPicker$2$1;

    invoke-direct {v2, p0, v1}, Lorg/love2d/android/OverhaulPicker$2$1;-><init>(Lorg/love2d/android/OverhaulPicker$2;Ljava/lang/String;)V

    invoke-virtual {v0, v2}, Lorg/love2d/android/OverhaulPicker;->runOnUiThread(Ljava/lang/Runnable;)V

    return-void
.end method

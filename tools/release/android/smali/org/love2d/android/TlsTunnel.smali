.class public Lorg/love2d/android/TlsTunnel;
.super Ljava/lang/Thread;

.annotation system Ldalvik/annotation/MemberClasses;
    value = {
        Lorg/love2d/android/TlsTunnel$PipeThread;
    }
.end annotation

.field private static final TAG:Ljava/lang/String; = "TlsTunnel"

.field private static final PORT:I = 0xad5c

.field public static port:I

.field private static instance:Lorg/love2d/android/TlsTunnel;

.field private client:Ljava/net/Socket;

.method public constructor <init>(Ljava/net/Socket;)V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Thread;-><init>()V

    iput-object p1, p0, Lorg/love2d/android/TlsTunnel;->client:Ljava/net/Socket;

    return-void
.end method

.method public constructor <init>()V
    .locals 0

    invoke-direct {p0}, Ljava/lang/Thread;-><init>()V

    return-void
.end method

.method public static synchronized startTunnel()V
    .locals 2

    sget-object v0, Lorg/love2d/android/TlsTunnel;->instance:Lorg/love2d/android/TlsTunnel;

    if-eqz v0, :cond_create

    invoke-virtual {v0}, Ljava/lang/Thread;->isAlive()Z

    move-result v0

    if-nez v0, :cond_return

    :cond_create
    new-instance v0, Lorg/love2d/android/TlsTunnel;

    invoke-direct {v0}, Lorg/love2d/android/TlsTunnel;-><init>()V

    sput-object v0, Lorg/love2d/android/TlsTunnel;->instance:Lorg/love2d/android/TlsTunnel;

    sget-object v0, Lorg/love2d/android/TlsTunnel;->instance:Lorg/love2d/android/TlsTunnel;

    const/4 v1, 0x1

    invoke-virtual {v0, v1}, Ljava/lang/Thread;->setDaemon(Z)V

    sget-object v0, Lorg/love2d/android/TlsTunnel;->instance:Lorg/love2d/android/TlsTunnel;

    invoke-virtual {v0}, Ljava/lang/Thread;->start()V

    :cond_return
    return-void
.end method

.method private static readLine(Ljava/io/InputStream;)Ljava/lang/String;
    .locals 3

    const/16 v0, 0x40

    new-instance v0, Ljava/lang/StringBuilder;

    const/16 v1, 0x40

    invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(I)V

    :loop_start
    invoke-virtual {p0}, Ljava/io/InputStream;->read()I

    move-result v1

    const/4 v2, -0x1

    if-eq v1, v2, :loop_end

    const/16 v2, 0xa

    if-eq v1, v2, :loop_end

    const/16 v2, 0xd

    if-eq v1, v2, :loop_start

    int-to-char v1, v1

    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(C)Ljava/lang/StringBuilder;

    goto :loop_start

    :loop_end
    invoke-virtual {v0}, Ljava/lang/StringBuilder;->length()I

    move-result v1

    if-lez v1, :return_null

    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    return-object v0

    :return_null
    const/4 v0, 0x0

    return-object v0
.end method

.method static pipe(Ljava/io/InputStream;Ljava/io/OutputStream;)V
    .locals 3

    const/16 v0, 0x2000

    new-array v0, v0, [B

    :loop_start
    :try_start_pipe
    invoke-virtual {p0, v0}, Ljava/io/InputStream;->read([B)I

    move-result v1

    if-lez v1, :loop_end

    const/4 v2, 0x0

    invoke-virtual {p1, v0, v2, v1}, Ljava/io/OutputStream;->write([BII)V

    invoke-virtual {p1}, Ljava/io/OutputStream;->flush()V

    goto :loop_start
    :try_end_pipe
    .catch Ljava/io/IOException; {:try_start_pipe .. :try_end_pipe} :catch_pipe

    :catch_pipe
    :loop_end
    return-void
.end method

.method public run()V
    .locals 12

    const-string v10, "TlsTunnel"

    iget-object v1, p0, Lorg/love2d/android/TlsTunnel;->client:Ljava/net/Socket;

    if-eqz v1, :server_mode

    invoke-direct {p0, v1}, Lorg/love2d/android/TlsTunnel;->handleClient(Ljava/net/Socket;)V

    return-void

    :server_mode

    :try_start_bind
    new-instance v0, Ljava/net/ServerSocket;

    sget v1, Lorg/love2d/android/TlsTunnel;->port:I

    if-nez v1, :port_bind_ok

    const v1, 0xad5c

    :port_bind_ok

    const/4 v2, 0x2

    const-string v3, "127.0.0.1"

    invoke-static {v3}, Ljava/net/InetAddress;->getByName(Ljava/lang/String;)Ljava/net/InetAddress;

    move-result-object v3

    invoke-direct {v0, v1, v2, v3}, Ljava/net/ServerSocket;-><init>(IILjava/net/InetAddress;)V
    :try_end_bind
    .catch Ljava/io/IOException; {:try_start_bind .. :try_end_bind} :catch_bind

    new-instance v1, Ljava/lang/StringBuilder;

    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V

    const-string v2, "Listening on 127.0.0.1:"

    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    sget v2, Lorg/love2d/android/TlsTunnel;->port:I

    if-nez v2, :port_log_ok

    const v2, 0xad5c

    :port_log_ok

    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v1

    invoke-static {v10, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    goto :accept_loop

    :catch_bind
    move-exception v0

    invoke-virtual {v0}, Ljava/io/IOException;->getMessage()Ljava/lang/String;

    move-result-object v0

    new-instance v1, Ljava/lang/StringBuilder;

    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V

    const-string v2, "Bind failed: "

    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v1, v0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    invoke-static {v10, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I

    return-void

    :accept_loop
    invoke-virtual {p0}, Ljava/lang/Thread;->isInterrupted()Z

    move-result v1

    if-nez v1, :accept_done

    const/4 v1, 0x0
    const/4 v2, 0x0
    const/4 v3, 0x0
    const/4 v4, 0x0

    :try_start_accept
    invoke-virtual {v0}, Ljava/net/ServerSocket;->accept()Ljava/net/Socket;

    move-result-object v1

    new-instance v3, Lorg/love2d/android/TlsTunnel;

    invoke-direct {v3, v1}, Lorg/love2d/android/TlsTunnel;-><init>(Ljava/net/Socket;)V

    const/4 v4, 0x1

    invoke-virtual {v3, v4}, Ljava/lang/Thread;->setDaemon(Z)V

    invoke-virtual {v3}, Ljava/lang/Thread;->start()V
    :try_end_accept
    .catch Ljava/lang/Exception; {:try_start_accept .. :try_end_accept} :catch_accept

    goto :accept_loop

    :catch_accept
    move-exception v5

    const-string v6, "Accept failed"

    invoke-static {v10, v6}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I

    const-wide/16 v8, 0x64

    :try_start_sleep
    invoke-static {v8, v9}, Ljava/lang/Thread;->sleep(J)V
    :try_end_sleep
    .catch Ljava/lang/Exception; {:try_start_sleep .. :try_end_sleep} :catch_sleep

    :catch_sleep
    goto :accept_loop

    :accept_done
    :try_start_close_ss
    invoke-virtual {v0}, Ljava/net/ServerSocket;->close()V
    :try_end_close_ss
    .catch Ljava/lang/Exception; {:try_start_close_ss .. :try_end_close_ss} :catch_close_ss

    :catch_close_ss
    return-void
.end method

.method private handleClient(Ljava/net/Socket;)V
    .locals 12

    const-string v10, "TlsTunnel"

    move-object v1, p1

    const/4 v2, 0x0

    const/4 v3, 0x0

    const/4 v4, 0x0

    :try_start_accept

    const-string v3, "Client connected"

    invoke-static {v10, v3}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    invoke-virtual {v1}, Ljava/net/Socket;->getInputStream()Ljava/io/InputStream;

    move-result-object v3

    invoke-virtual {v1}, Ljava/net/Socket;->getOutputStream()Ljava/io/OutputStream;

    move-result-object v4

    invoke-static {v3}, Lorg/love2d/android/TlsTunnel;->readLine(Ljava/io/InputStream;)Ljava/lang/String;

    move-result-object v5

    if-eqz v5, :bad_target

    const-string v6, ":"

    invoke-virtual {v5, v6}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z

    move-result v6

    if-eqz v6, :bad_target

    goto :parse_target

    :bad_target
    const-string v6, "ERROR:bad_target\n"

    const-string v7, "UTF-8"

    invoke-virtual {v6, v7}, Ljava/lang/String;->getBytes(Ljava/lang/String;)[B

    move-result-object v6

    invoke-virtual {v4, v6}, Ljava/io/OutputStream;->write([B)V

    invoke-virtual {v4}, Ljava/io/OutputStream;->flush()V

    invoke-virtual {v1}, Ljava/net/Socket;->close()V

    return-void

    :parse_target
    const/16 v6, 0x3a

    invoke-virtual {v5, v6}, Ljava/lang/String;->lastIndexOf(I)I

    move-result v6

    const/4 v7, 0x0

    invoke-virtual {v5, v7, v6}, Ljava/lang/String;->substring(II)Ljava/lang/String;

    move-result-object v7

    add-int/lit8 v8, v6, 0x1

    invoke-virtual {v5}, Ljava/lang/String;->length()I

    move-result v9

    invoke-virtual {v5, v8, v9}, Ljava/lang/String;->substring(II)Ljava/lang/String;

    move-result-object v8

    invoke-static {v8}, Ljava/lang/Integer;->parseInt(Ljava/lang/String;)I

    move-result v8

    new-instance v5, Ljava/lang/StringBuilder;

    invoke-direct {v5}, Ljava/lang/StringBuilder;-><init>()V

    const-string v6, "TLS connect "

    invoke-virtual {v5, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v5, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v6, ":"

    invoke-virtual {v5, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v5, v8}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    invoke-virtual {v5}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v5

    invoke-static {v10, v5}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    invoke-static {}, Ljavax/net/ssl/SSLSocketFactory;->getDefault()Ljavax/net/SocketFactory;

    move-result-object v5

    check-cast v5, Ljavax/net/ssl/SSLSocketFactory;

    invoke-virtual {v5, v7, v8}, Ljavax/net/ssl/SSLSocketFactory;->createSocket(Ljava/lang/String;I)Ljava/net/Socket;

    move-result-object v2

    check-cast v2, Ljavax/net/ssl/SSLSocket;

    invoke-virtual {v2}, Ljavax/net/ssl/SSLSocket;->startHandshake()V

    const-string v5, "OK\n"

    const-string v6, "UTF-8"

    invoke-virtual {v5, v6}, Ljava/lang/String;->getBytes(Ljava/lang/String;)[B

    move-result-object v5

    invoke-virtual {v4, v5}, Ljava/io/OutputStream;->write([B)V

    invoke-virtual {v4}, Ljava/io/OutputStream;->flush()V

    new-instance v5, Ljava/lang/StringBuilder;

    invoke-direct {v5}, Ljava/lang/StringBuilder;-><init>()V

    const-string v6, "TLS OK "

    invoke-virtual {v5, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v5, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    const-string v6, ":"

    invoke-virtual {v5, v6}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v5, v8}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;

    invoke-virtual {v5}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v5

    invoke-static {v10, v5}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I

    invoke-virtual {v2}, Ljavax/net/ssl/SSLSocket;->getInputStream()Ljava/io/InputStream;

    move-result-object v5

    new-instance v6, Lorg/love2d/android/TlsTunnel$PipeThread;

    invoke-direct {v6, v5, v4}, Lorg/love2d/android/TlsTunnel$PipeThread;-><init>(Ljava/io/InputStream;Ljava/io/OutputStream;)V

    invoke-virtual {v6}, Ljava/lang/Thread;->start()V

    invoke-virtual {v2}, Ljavax/net/ssl/SSLSocket;->getOutputStream()Ljava/io/OutputStream;

    move-result-object v5

    invoke-static {v3, v5}, Lorg/love2d/android/TlsTunnel;->pipe(Ljava/io/InputStream;Ljava/io/OutputStream;)V

    invoke-virtual {v2}, Ljavax/net/ssl/SSLSocket;->close()V

    const-wide/16 v8, 0x1388

    invoke-virtual {v6, v8, v9}, Ljava/lang/Thread;->join(J)V
    :try_end_accept
    .catch Ljava/lang/NumberFormatException; {:try_start_accept .. :try_end_accept} :catch_nfe
    .catch Ljava/lang/Exception; {:try_start_accept .. :try_end_accept} :catch_conn

    goto :finally_block

    :catch_nfe
    move-exception v5

    :try_start_nfe
    const-string v6, "ERROR:bad_port\n"

    const-string v7, "UTF-8"

    invoke-virtual {v6, v7}, Ljava/lang/String;->getBytes(Ljava/lang/String;)[B

    move-result-object v6

    invoke-virtual {v4, v6}, Ljava/io/OutputStream;->write([B)V

    invoke-virtual {v4}, Ljava/io/OutputStream;->flush()V

    invoke-virtual {v1}, Ljava/net/Socket;->close()V
    :try_end_nfe
    .catch Ljava/lang/Exception; {:try_start_nfe .. :try_end_nfe} :catch_conn

    return-void

    :catch_conn
    move-exception v5

    invoke-virtual {v5}, Ljava/lang/Exception;->getMessage()Ljava/lang/String;

    move-result-object v5

    new-instance v6, Ljava/lang/StringBuilder;

    invoke-direct {v6}, Ljava/lang/StringBuilder;-><init>()V

    const-string v7, "Conn: "

    invoke-virtual {v6, v7}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v6, v5}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v6}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v5

    invoke-static {v10, v5}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I

    :finally_block
    if-eqz v1, :skip_local_close

    :try_start_close_local
    invoke-virtual {v1}, Ljava/net/Socket;->close()V
    :try_end_close_local
    .catch Ljava/lang/Exception; {:try_start_close_local .. :try_end_close_local} :catch_close_local

    :catch_close_local
    :skip_local_close

    if-eqz v2, :skip_remote_close

    :try_start_close_remote
    invoke-virtual {v2}, Ljavax/net/ssl/SSLSocket;->close()V
    :try_end_close_remote
    .catch Ljava/lang/Exception; {:try_start_close_remote .. :try_end_close_remote} :catch_close_remote

    :catch_close_remote
    :skip_remote_close

    return-void

.end method

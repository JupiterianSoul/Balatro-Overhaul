import asyncio
import ssl
import sys

PORT = 44380
ALLOWED_PORTS = {443}


async def pipe(reader, writer):
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except (ConnectionError, OSError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def handle(client_reader, client_writer):
    try:
        line = (await asyncio.wait_for(client_reader.readline(), 10)).decode().strip()
        host, _, port = line.rpartition(":")
        port = int(port)
        if not host or port not in ALLOWED_PORTS:
            raise ValueError(f"target not allowed: {line}")
        ctx = ssl.create_default_context()
        server_reader, server_writer = await asyncio.wait_for(
            asyncio.open_connection(host, port, ssl=ctx, server_hostname=host), 15
        )
    except Exception as e:
        client_writer.write(f"ERROR:{e}\n".encode())
        await client_writer.drain()
        client_writer.close()
        return
    client_writer.write(b"OK\n")
    await client_writer.drain()
    await asyncio.gather(pipe(client_reader, server_writer), pipe(server_reader, client_writer))


async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", PORT)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except OSError as e:
        print(f"tls_tunnel: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        pass

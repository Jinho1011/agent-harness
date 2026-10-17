#!/usr/bin/env python3
"""Check the installed Lightpanda MCP against a local login fixture; no model API needed."""
import asyncio
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from threading import Thread
from urllib.parse import parse_qs


class LoginPage(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def respond(self, body, cookie=None):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        if cookie:
            self.send_header('Set-Cookie', cookie)
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        if self.path == '/account':
            if 'session=fixture' not in self.headers.get('Cookie', ''):
                self.respond('<h1>Login required</h1>')
            else:
                self.respond('<h1>ACCOUNTOK</h1><p id="js"></p>'
                             '<script>document.querySelector("#js").textContent="JAVASCRIPTOK"</script>')
        else:
            self.respond('<form method="post" action="/login">'
                         '<input id="username" name="username">'
                         '<input id="password" name="password" type="password">'
                         '<button id="login" type="submit">Login</button></form>')

    def do_POST(self):
        fields = parse_qs(self.rfile.read(int(self.headers['Content-Length'])).decode())
        if fields == {'username': ['fixture-user'], 'password': ['fixture-password']}:
            self.respond('<h1>LOGIN-OK</h1>', 'session=fixture; Path=/; HttpOnly')
        else:
            self.respond('<h1>Login failed</h1>')


async def check(base_url):
    process = await asyncio.create_subprocess_exec(
        'lightpanda', 'mcp', stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL, limit=1024 * 1024,
        env={**os.environ, 'LIGHTPANDA_DISABLE_TELEMETRY': 'true'})
    request_id = 0

    async def rpc(method, params):
        nonlocal request_id
        request_id += 1
        message = {'jsonrpc': '2.0', 'id': request_id, 'method': method, 'params': params}
        process.stdin.write((json.dumps(message) + '\n').encode())
        await process.stdin.drain()
        while True:
            line = await asyncio.wait_for(process.stdout.readline(), timeout=20)
            if not line:
                raise RuntimeError('Lightpanda exited before responding')
            reply = json.loads(line)
            if reply.get('id') == request_id:
                assert 'error' not in reply, reply
                result = reply['result']
                assert not result.get('isError'), result
                return result

    async def call(name, arguments):
        return await rpc('tools/call', {'name': name, 'arguments': arguments})

    try:
        await rpc('initialize', {'protocolVersion': '2025-11-25', 'capabilities': {},
                                'clientInfo': {'name': 'harness-lightpanda-check', 'version': '1.0'}})
        process.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        tools = await rpc('tools/list', {})
        assert {'goto', 'fill', 'click', 'markdown', 'getCookies'} <= {t['name'] for t in tools['tools']}
        print(f'PASS MCP initialize and tools/list ({len(tools["tools"])} tools)', flush=True)
        await call('goto', {'url': base_url})
        await call('fill', {'selector': '#username', 'value': 'fixture-user'})
        await call('fill', {'selector': '#password', 'value': 'fixture-password'})
        await call('click', {'selector': '#login'})
        await call('waitForScript', {'script': 'document.body.textContent.includes("LOGIN-OK")'})
        await call('goto', {'url': base_url + '/account'})
        page = await call('markdown', {})
        text = '\n'.join(c.get('text', '') for c in page.get('content', []))
        assert 'ACCOUNTOK' in text and 'JAVASCRIPTOK' in text, text
        print('PASS form fill, login click, session cookie, JavaScript and authenticated extraction', flush=True)
    finally:
        process.kill()
        await asyncio.wait_for(process.wait(), timeout=5)


if __name__ == '__main__':
    server = ThreadingHTTPServer(('127.0.0.1', 0), LoginPage)
    Thread(target=server.serve_forever, daemon=True).start()
    try:
        asyncio.run(check(f'http://127.0.0.1:{server.server_port}'))
    finally:
        server.shutdown()
        server.server_close()

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/missing.dmg':
            self.send_error(404)
            return
        if self.path == '/redirect.dmg':
            self.send_response(302)
            self.send_header('Location', 'http://localhost:18763/file.dmg')
            self.end_headers()
            return
        if self.path == '/slow.dmg':
            time.sleep(1)
        body = b'<html>not an installer</html>' if self.path == '/html.dmg' else b'MacDownUp fixture\n'
        self.send_response(200)
        self.send_header('Content-Type', 'text/html' if self.path == '/html.dmg' else 'application/octet-stream')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            pass
    def log_message(self, *args):
        pass

ThreadingHTTPServer(('127.0.0.1', 18763), Handler).serve_forever()

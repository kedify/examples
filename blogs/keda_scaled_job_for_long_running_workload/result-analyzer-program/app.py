from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import time

class RequestHandler(BaseHTTPRequestHandler):
    processed_count = 0
    kill_count = 0
    events = []

    def _set_response(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()

    def _record_event(self, event_type):
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
        if event_type == 'processed count':
            self.__class__.processed_count += 1
            count = self.__class__.processed_count
        elif event_type == 'kill count':
            self.__class__.kill_count += 1
            count = self.__class__.kill_count
        event = f"{timestamp} - {event_type} {count}"
        self.__class__.events.append(event)

    def do_GET(self):
        if self.path == '/get/count':
            self._set_response()
            response = json.dumps(self.events).encode()
            self.wfile.write(response)

    def do_POST(self):
        if self.path == '/create/count':
            self._record_event('processed count')
            self._set_response()
            response = json.dumps({'message': 'Count incremented'}).encode()
            self.wfile.write(response)
        elif self.path == '/kill/count':
            self._record_event('kill count')
            self._set_response()
            response = json.dumps({'message': 'Kill incremented'}).encode()
            self.wfile.write(response)
        elif self.path == '/reset':
            self.__class__.processed_count = 0
            self.__class__.kill_count = 0
            self.__class__.events = []
            self._set_response()
            response = json.dumps({'message': 'Reset Successfully'}).encode()
            self.wfile.write(response)

def run(server_class=HTTPServer, handler_class=RequestHandler, port=8080):
    print("Starting server...")
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    print(f'Starting http server on port {port}...')
    httpd.serve_forever()

if __name__ == '__main__':
    run()

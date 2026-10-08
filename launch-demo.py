from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import os, webbrowser, threading, time
ROOT=Path(__file__).resolve().parent
os.chdir(ROOT)
url='http://127.0.0.1:8080/Demo/index.html'
def open_browser():
    time.sleep(.5)
    webbrowser.open(url)
threading.Thread(target=open_browser,daemon=True).start()
print('HeroPath demo:',url)
print('Ctrl+C pour arrêter le serveur.')
ThreadingHTTPServer(('127.0.0.1',8080),SimpleHTTPRequestHandler).serve_forever()

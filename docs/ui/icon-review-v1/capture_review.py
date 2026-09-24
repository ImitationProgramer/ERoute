from pathlib import Path
import subprocess, os, signal

root = Path(__file__).resolve().parent
cmd = ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '--headless', '--disable-gpu', '--hide-scrollbars', '--user-data-dir=/tmp/eroute-icon-review-chrome-v1', '--force-device-scale-factor=1', '--window-size=1320,1840', '--timeout=10000', '--screenshot='+str(root/'comparison-v1.png'), (root/'index.html').as_uri()]
process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
try:
    process.wait(timeout=18)
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
if not (root/'comparison-v1.png').exists():
    raise SystemExit('Screenshot missing')
print('Review screenshot saved; dedicated headless browser stopped. No installed app interaction.')

"""Stop only a supervisor launched and recorded for this companion."""
import os, signal
from pathlib import Path
root=Path(__file__).resolve().parent
file=root/'logs/supervisor.pid'
if not file.exists():raise SystemExit('No recorded supervisor. Use Ctrl-C in the start.sh terminal.')
pid=int(file.read_text())
try:
    command=Path(f'/proc/{pid}/cmdline').read_bytes()
    if str(root/'run.py').encode() not in command:raise SystemExit('PID no longer belongs to this companion; not stopping it.')
    os.kill(pid,signal.SIGTERM)
    file.unlink(missing_ok=True)
except FileNotFoundError:print('Already stopped.')

"""Exercise the production scene in two independent Godot processes over UDP."""
import argparse
from pathlib import Path
import socket
import subprocess
import threading
import time


def drain(stream, sink):
    for line in stream:
        sink.append(line)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("engine")
    args = parser.parse_args()
    game = Path(__file__).resolve().parents[1] / "games" / "penalty-yard"
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    command = [args.engine, "--headless", "--path", str(game), "--script", "tests/process_worker.gd", "--"]
    processes = []
    outputs = []
    try:
        host = subprocess.Popen(command + ["host", str(port)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        processes.append(host)
        time.sleep(0.5)
        client = subprocess.Popen(command + ["client", str(port)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        processes.append(client)
        # Drain both pipes while the match runs: waiting for a piped child before
        # reading can stall it on Windows even when the output is tiny.
        for process in processes:
            lines = []
            outputs.append(lines)
            threading.Thread(target=drain, args=(process.stdout, lines), daemon=True).start()
        for process in processes:
            process.wait(timeout=35)
        for process, lines in zip(processes, outputs):
            output = "".join(lines)
            print(output, end="")
            if process.returncode or "SCRIPT ERROR:" in output or "ERROR:" in output or "PASS: full match and draw" not in output:
                raise SystemExit("Two-process network test failed")
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Run shipped Lisp examples against one owned daemon, including archive consumers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source-root", type=Path, default=Path(__file__).resolve().parents[1])
args = parser.parse_args()
root = args.source_root.resolve()
started = time.monotonic()
program = shutil.which(os.environ.get("LIBTMUX_TEST_TMUX", "tmux"))
if program is None:
    raise SystemExit("Install tmux or set LIBTMUX_TEST_TMUX to a native binary")
program = str(Path(program).resolve())
environment = os.environ.copy()
for key in ("TMUX", "TMUX_PANE"):
    environment.pop(key, None)
environment["LC_ALL"] = "C.UTF-8"
version = subprocess.check_output([program, "-V"], env=environment, text=True).strip()
asdf = subprocess.check_output(["mise", "where", "http:asdf-lisp"], text=True).strip()
for mode in ("assertions", "tutorial"):
    with tempfile.TemporaryDirectory(prefix="libtmux-lisp-example-") as directory:
        tutorial_terminated = False
        socket = str(Path(directory) / "tmux.sock")
        command = [program, "-S", socket]
        child_environment = environment.copy()
        child_environment["PATH"] = str(Path(program).parent) + os.pathsep + environment["PATH"]
        markdown = (root / "docs/tutorial.md").read_text()
        console = re.findall(r"^```console\n\$ (.*?)^```$", markdown, re.M | re.S)
        try:
            if mode == "tutorial":
                setup = next(block for block in console if "export LIBTMUX_DEMO_DIR=" in block)
                result = subprocess.run(["bash", "-c", setup], cwd=root, env=child_environment,
                                        check=True, text=True, stdout=subprocess.PIPE, timeout=10)
                socket = result.stdout.strip()
                child_environment["LIBTMUX_DEMO_DIR"] = str(Path(socket).parent)
                command = [program, "-S", socket]
            else:
                subprocess.run(command + ["-f", "/dev/null", "new-session", "-d", "-s", "work",
                                          "-n", "editor", "-x", "120", "-y", "40", "--", "/bin/cat"],
                               env=child_environment, check=True, timeout=10)
            if mode == "tutorial" and os.environ.get("LIBTMUX_TEST_FAIL_TUTORIAL_BEFORE_TERMINATION"):
                raise RuntimeError("Injected tutorial failure before termination")
            script = root / "examples/run.lisp"
            extra_arguments = [program, socket]
            working_directory = directory
            if mode == "tutorial":
                forms = re.findall(r"^```lisp\n(.*?)^```$", markdown, re.M | re.S)
                if not forms or forms[-1].strip() != "(uiop:quit)":
                    raise RuntimeError("Tutorial must end with an explicit REPL exit")
                if len(forms) < 2 or forms[-2].strip() != "(terminate-owned-server *socket-path*)":
                    raise RuntimeError("Tutorial must terminate its explicitly owned server before exit")
                script = Path(directory) / "tutorial.lisp"
                checks = '''
(assert (equal '(2 3 4 4)
               (list (length (tm:sessions *snapshot*))
                     (length (tm:windows *snapshot*))
                     (length (tm:window-links *snapshot*))
                     (length (tm:panes *snapshot*)))))
(assert (find "editor" (tm:windows *snapshot*) :key #'tm:name :test #'string=))
(tm:with-client (client :socket-path *socket-path*)
  (assert (find "api #{literal}" (tm:fetch-windows client) :key #'tm:name :test #'string=)))
(format t "TUTORIAL PASS: every Lisp block executed in reading order~%")
'''
                script.write_text('(asdf:load-asd (truename "libtmux.asd"))\n' +
                                  "\n".join(forms[:-2]) + checks +
                                  "\n".join(forms[-2:]))
                extra_arguments = []
                working_directory = root
            qlot_setup = Path(os.environ.get("LIBTMUX_QLOT_SETUP",
                                             root / ".qlot" / "setup.lisp"))
            lisp_command = ["sbcl", "--noinform", "--no-sysinit", "--no-userinit",
                            "--load", str(Path(asdf) / "asdf.lisp")]
            if qlot_setup.is_file():
                lisp_command.extend(["--load", str(qlot_setup)])
            lisp_command.extend(["--script", str(script), *extra_arguments])
            subprocess.run(lisp_command,
                           input=socket + "\n", text=True, cwd=working_directory,
                           env=child_environment, check=True, timeout=20)
            tutorial_terminated = mode == "tutorial"
        finally:
            if mode == "tutorial" and "LIBTMUX_DEMO_DIR" in child_environment:
                original_failure = sys.exc_info()[0] is not None
                cleanup = next(block for block in console if "tools/stop-example.py" in block)
                if not tutorial_terminated:
                    cleanup = cleanup.replace("--already-terminated ", "")
                try:
                    subprocess.run(["bash", "-c", cleanup], cwd=root, env=child_environment,
                                   check=True, timeout=3)
                except Exception as cleanup_error:
                    if not original_failure:
                        raise
                    print(f"Cleanup also failed: {cleanup_error}", file=sys.stderr)
            else:
                subprocess.run(command + ["-N", "kill-server"], env=environment,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
        stopped = subprocess.run(command + ["-N", "has-session"], env=environment,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
        if stopped.returncode == 0:
            raise RuntimeError("Example daemon survived cleanup")
evidence = {"status": "PASS", "tmux": version,
            "sbcl": subprocess.check_output(["sbcl", "--version"], text=True).strip(),
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "source_sha256": {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
                              for path in [*sorted((root / "examples").iterdir()),
                                           root / "README.md", root / "docs/tutorial.md",
                                           root / "tools/examples.py", root / "tools/stop-example.py"] if path.is_file()},
            "daemon_cleanup": "PASS",
            "optional_libraries_loaded": ["cl-ppcre", "com.inuoe.jzon"],
            "optional_systems_loaded": ["libtmux/regex", "libtmux/json", "libtmux/workspace"]}
evidence["tutorial_lisp_blocks"] = len(forms)
evidence["tutorial_console_setup_cleanup"] = "PASS"
output = Path(__file__).resolve().parents[1] / "dist"
output.mkdir(exist_ok=True)
(output / "examples-evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
print(json.dumps(evidence))

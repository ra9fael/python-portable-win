"""Portable-environment hook, copied into python/Lib/site-packages by bootstrap.

`import site` executes this module on every interpreter start, so the package
keeps itself healthy no matter how Python was launched: terminal, IDE, `-m`, or
a child process. Nothing here writes outside the package.

Three jobs:
1. repair launchers whose baked-in paths no longer match this location;
2. repair launchers written by pip during this process, right before it exits;
3. make the package the preferred source of `pip` for child processes.
"""

import atexit
import os
import sys
import time
from pathlib import Path

_STARTED = time.time()


def _package_root():
    # sys.prefix is the python/ directory; the package root is its parent.
    return Path(sys.prefix).resolve().parent


def _repair(root):
    """Run scripts/repair.py without importing it as a module.

    pip warns — and will eventually forbid — importing new modules after an
    install has started, so the exit-time repair executes the file instead of
    importing `repair`.
    """
    path = str(root / "scripts" / "repair.py")
    try:
        import runpy

        namespace = runpy.run_path(path, run_name="portable_repair")
        return namespace["repair"](root)
    except Exception:
        try:
            sys.path.insert(0, str(root / "scripts"))
            import repair

            return repair.repair(root)
        except Exception:
            # A failed repair must never break the interpreter that is starting.
            return 0


def _prepare_environment(root):
    python_dir = root / "python"
    scripts_dir = python_dir / "Scripts"

    # Append (never prepend) so host tools keep their usual precedence.
    entries = [p for p in os.environ.get("PATH", "").split(os.pathsep) if p]
    for extra in (str(python_dir), str(scripts_dir)):
        if extra not in entries:
            entries.append(extra)
    os.environ["PATH"] = os.pathsep.join(entries)

    # Environment variables win over any pip.ini in the user profile; pip.ini
    # is only a readable fallback for tools that do not inherit this process.
    defaults = {
        "PIP_USER": "0",
        "PIP_DISABLE_PIP_VERSION_CHECK": "1",
        "PIP_CACHE_DIR": str(python_dir / ".pip_cache"),
        "PIP_CONFIG_FILE": str(python_dir / "pip.ini"),
        "UV_CACHE_DIR": str(python_dir / ".uv_cache"),
    }

    # Mirror settings use pip names; map them for uv without overriding an
    # explicit UV_* value.
    if os.environ.get("PIP_INDEX_URL"):
        defaults.setdefault("UV_INDEX_URL", os.environ["PIP_INDEX_URL"])
    if os.environ.get("PIP_EXTRA_INDEX_URL"):
        defaults.setdefault("UV_EXTRA_INDEX_URL", os.environ["PIP_EXTRA_INDEX_URL"])

    # Optional offline wheelhouse produced by build_release.ps1 -Wheelhouse.
    wheels = root / "wheels"
    if wheels.is_dir():
        defaults["PIP_FIND_LINKS"] = str(wheels)
        defaults.setdefault("UV_FIND_LINKS", str(wheels))

    for key, value in defaults.items():
        os.environ.setdefault(key, value)


def _prepare_tcl(root):
    """Point the embeddable engine's Tcl/Tk at its in-package libraries.

    This matters for tools launched through a shim or `python -m`, where
    activate.ps1 never ran. PBS ships Tcl 9.x and finds it on its own.
    """
    tcl_root = root / "python" / "tcl"
    if not tcl_root.is_dir():
        return
    for pattern, key in (("tcl8.*", "TCL_LIBRARY"), ("tk8.*", "TK_LIBRARY")):
        if key in os.environ:
            continue
        matches = sorted(p for p in tcl_root.glob(pattern) if p.is_dir())
        if matches:
            os.environ[key] = str(matches[-1])


def _repair_written_launchers(root):
    """Convert launchers pip created during this process, before it exits.

    Only files modified after this process started are considered, so a normal
    start/exit costs one directory listing and no repair at all.
    """
    try:
        for exe in (root / "python" / "Scripts").glob("*.exe"):
            try:
                if exe.stat().st_mtime >= _STARTED:
                    _repair(root)
                    return
            except OSError:
                continue
    except Exception:
        pass


def _sync():
    root = _package_root()
    if not (root / "scripts").is_dir():
        return  # not a portable package; leave unrelated interpreters alone

    _prepare_environment(root)
    _prepare_tcl(root)

    marker = root / "python" / ".portable_root"
    try:
        stale = marker.read_text(encoding="utf-8").strip() != str(root)
    except OSError:
        stale = True

    if stale:
        _repair(root)

    atexit.register(_repair_written_launchers, root)


_sync()

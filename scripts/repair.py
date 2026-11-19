"""Recreate console-script launchers for the current package location.

pip/uv generate .exe launchers that embed the absolute path of the interpreter
that installed them. After the package is copied or moved those launchers break.
This script replaces them with the path-relative shim.exe shipped in scripts/bin,
and recreates commands whose launcher is missing altogether.

It is importable on purpose: sitecustomize.py calls repair(root) on interpreter
start (when the location changed) and on exit (when pip wrote new launchers), so
no launcher executable is needed to trigger a repair.
"""

import configparser
import re
import shutil
import sys
import zipfile
from pathlib import Path

NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
ENTRY_RE = re.compile(r"from\s+([\w.]+)\s+import\s+([\w.]+)")
VERSION_SUFFIX_RE = re.compile(r"[\d.]+$")
TAIL_BYTES = 512 * 1024


def read_entry_points(path):
    parser = configparser.ConfigParser(interpolation=None)
    try:
        parser.read(path, encoding="utf-8")
    except (configparser.Error, OSError):
        return

    for section in ("console_scripts", "gui_scripts"):
        if section not in parser.sections():
            continue
        for name, value in parser.items(section):
            raw = value.split("[")[0].strip()
            module, _, attrs = raw.partition(":")
            yield name.strip(), module.strip(), (attrs.strip() or "main"), section == "gui_scripts"


def is_trampoline(path):
    """Identify a pip/uv launcher by the payload appended to the executable.

    Size is not a reliable signal: real binaries (ruff, uv) are also large.
    Both pip and uv append a zip holding __main__.py, uv additionally stores
    UV_TRAMPOLINE_KIND in its resources.
    """
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            handle.seek(max(0, size - TAIL_BYTES))
            tail = handle.read()
    except OSError:
        return False

    if b"UV_TRAMPOLINE_KIND" in tail or b"uv.Trampoline" in tail:
        return True
    if b"__main__.py" not in tail:
        return False

    try:
        with zipfile.ZipFile(path) as archive:
            return "__main__.py" in archive.namelist()
    except (OSError, zipfile.BadZipFile):
        return False


def entry_from_exe(path):
    """Recover module:func from the launcher payload when metadata is missing."""
    try:
        with zipfile.ZipFile(path) as archive:
            source = archive.read("__main__.py").decode("utf-8", "replace")
    except (OSError, KeyError, zipfile.BadZipFile):
        return None

    match = ENTRY_RE.search(source)
    if not match:
        return None
    # Without dist-info there is no gui_scripts section; assume a console tool.
    return match.group(1), match.group(2), False


def find_entry(ep_map, stem):
    key = stem.lower()
    if key in ep_map:
        return ep_map[key]
    return ep_map.get(VERSION_SUFFIX_RE.sub("", key))


def write_entry(scripts_dir, stem, entry):
    """Write <stem>.entry, returning True only when the content changed."""
    module, func, gui = entry
    text = f"module={module}\nfunc={func}\ngui={'true' if gui else 'false'}\n"
    path = scripts_dir / f"{stem}.entry"
    try:
        if path.exists() and path.read_text(encoding="utf-8") == text:
            return False
        path.write_text(text, encoding="utf-8")
        return True
    except OSError:
        return False


def restore_hook(root):
    """Put the project's startup hook back if a package replaced it."""
    source = root / "scripts" / "sitecustomize.py"
    target = root / "python" / "Lib" / "site-packages" / "sitecustomize.py"
    if not source.exists() or not target.parent.exists():
        return False
    try:
        if target.exists() and target.read_bytes() == source.read_bytes():
            return False
        shutil.copyfile(source, target)
        return True
    except OSError:
        return False


def repair(root):
    root = Path(root).resolve()
    shim = root / "scripts" / "bin" / "shim.exe"
    site_packages = root / "python" / "Lib" / "site-packages"
    scripts_dir = root / "python" / "Scripts"

    if not shim.exists() or not site_packages.exists():
        return 0

    ep_map = {}
    for dist_info in sorted(site_packages.glob("*.dist-info")):
        entry_points = dist_info / "entry_points.txt"
        if not entry_points.exists():
            continue
        for name, module, func, gui in read_entry_points(entry_points):
            if NAME_RE.match(name) and module:
                ep_map[name.lower()] = (module, func, gui)

    scripts_dir.mkdir(parents=True, exist_ok=True)
    rebuilt = 0
    unresolved = 0

    # Commands that metadata advertises but whose exe is missing. PBS never
    # ships pip.exe, and users occasionally delete a launcher by hand.
    for name, entry in sorted(ep_map.items()):
        target = scripts_dir / f"{name}.exe"
        if target.exists():
            continue
        try:
            shutil.copyfile(shim, target)
        except OSError as exc:
            print(f"[repair] skipped {target.name}: {exc}", file=sys.stderr)
            unresolved += 1
            continue
        write_entry(scripts_dir, name, entry)
        rebuilt += 1

    for target in sorted(scripts_dir.glob("*.exe")):
        try:
            same_size = target.stat().st_size == shim.stat().st_size
        except OSError:
            same_size = False
        # Already a shim: no need to read half a megabyte of payload.
        replacing = False if same_size else is_trampoline(target)
        entry = find_entry(ep_map, target.stem)

        if entry is None:
            if not replacing:
                # A real binary that happens to live in Scripts: leave it alone.
                continue
            entry = entry_from_exe(target)
            if entry is None:
                print(f"[repair] cannot resolve entry for {target.name}, left as-is", file=sys.stderr)
                unresolved += 1
                continue
        elif not replacing:
            if not same_size:
                # Owns entry-point metadata but is a genuine binary, not our shim.
                continue
            # Already converted: only refresh a stale sidecar.
            write_entry(scripts_dir, target.stem, entry)
            continue

        try:
            shutil.copyfile(shim, target)
        except OSError as exc:
            # Typically a launcher that is still running; retried on next start.
            print(f"[repair] skipped {target.name}: {exc}", file=sys.stderr)
            unresolved += 1
            continue

        write_entry(scripts_dir, target.stem, entry)
        rebuilt += 1

    # Drop sidecars left behind by uninstalled packages.
    for sidecar in sorted(scripts_dir.glob("*.entry")):
        if sidecar.stem.lower() in ep_map:
            continue
        if (scripts_dir / f"{sidecar.stem}.exe").exists():
            continue
        try:
            sidecar.unlink()
        except OSError:
            pass

    (root / "python" / ".portable_root").write_text(str(root), encoding="utf-8")

    if restore_hook(root):
        print("[repair] restored the portable sitecustomize.py hook", file=sys.stderr)

    if rebuilt or unresolved:
        print(f"[repair] {rebuilt} launcher(s) rebuilt in {root}", file=sys.stderr)
    return rebuilt


def main():
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    repair(root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

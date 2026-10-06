"""Make a self-contained stage-3 Windows preview using the pinned Godot runner.

This is a prototype package, not a final exported Steam build.
"""
import argparse
import hashlib
import io
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "games" / "penalty-yard"
ENGINE_NAME = "Godot_v4.5.1-stable_win64.exe"
ENGINE_HASH = "ab84df90ead5a888530faaabe744a27678ef7635068883900174fae37f7fc6178d033b551d88963c7dc2466580915a582bbc79aca97c19085900655761f56a27"
ENGINE_URL = "https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_win64.exe.zip"
LICENSE_URL = "https://raw.githubusercontent.com/godotengine/godot/4.5.1-stable/LICENSE.txt"
COPYRIGHT_URL = "https://raw.githubusercontent.com/godotengine/godot/4.5.1-stable/COPYRIGHT.txt"


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "PocketChaos-prototype"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine-zip", type=Path)
    parser.add_argument("--license-file", type=Path)
    parser.add_argument("--copyright-file", type=Path)
    args = parser.parse_args()
    data = args.engine_zip.read_bytes() if args.engine_zip else download(ENGINE_URL)
    if hashlib.sha512(data).hexdigest() != ENGINE_HASH:
        raise SystemExit("Official engine archive checksum mismatch")
    license_data = args.license_file.read_bytes() if args.license_file else download(LICENSE_URL)
    copyright_data = args.copyright_file.read_bytes() if args.copyright_file else download(COPYRIGHT_URL)
    destination = ROOT / "builds" / "penalty-yard-stage-3-windows.zip"
    destination.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as package:
        for path in sorted(GAME.rglob("*")):
            if not path.is_file():
                continue
            relative = path.relative_to(GAME)
            if any(part in {".godot", ".engine", "tests"} for part in relative.parts):
                continue
            package.write(path, relative.as_posix())
        with zipfile.ZipFile(io.BytesIO(data)) as source:
            package.writestr(".engine/" + ENGINE_NAME, source.read(ENGINE_NAME))
        package.writestr("LICENSE-Godot.txt", license_data)
        package.writestr("COPYRIGHT-Godot.txt", copyright_data)
    print(f"Windows preview: {destination} ({destination.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()

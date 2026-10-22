"""Create an installation ZIP with game-root-relative paths."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]

def build():
    files = sorted(p for p in (ROOT / 'extension').rglob('*') if p.is_file())
    assert files, 'No source files found'
    output = ROOT / 'dist/drift-follow-camera-v0.1.zip'
    output.parent.mkdir(exist_ok=True)
    with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, path.relative_to(ROOT).as_posix())
        for name in ('README.md', 'LICENSE.md', 'NOTICE.md'):
            archive.write(ROOT / name, name)
        for path in sorted((ROOT / 'docs').rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(ROOT).as_posix())
    with ZipFile(output) as archive:
        assert archive.testzip() is None
        for path in files:
            assert archive.read(path.relative_to(ROOT).as_posix()) == path.read_bytes()
    print(output)
    return output

if __name__ == '__main__':
    build()

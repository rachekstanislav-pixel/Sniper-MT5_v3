"""Package a whitelisted source distribution; excludes credentials, DBs and legacy TXT."""
import hashlib
from pathlib import Path
import zipfile
ROOT = Path(__file__).resolve().parents[1]
NAME = 'Sniper_Manager_3.66_News_0.5.0'
FILES = {
    'Sniper_Manager_v3_6_6_NEWS_VIRTUAL.mq5': 'Sniper_Manager_v3_6_6_NEWS_VIRTUAL.mq5',
    'releases/INSTALL_3.66_RU.md': 'README_RU.md',
    'news/service.py': 'news/service.py',
    'news/start_news_windows.cmd': 'news/start_news_windows.cmd',
    'news/fixtures/README.md': 'news/fixtures/README.md',
    'news/fixtures/SYNTHETIC_20261106.tsv': 'news/fixtures/SYNTHETIC_20261106.tsv',
}

def build():
    output = ROOT / 'releases' / (NAME + '.zip')
    contents = {dest: (ROOT/src).read_bytes() for src, dest in FILES.items()}
    manifest = ''.join(hashlib.sha256(data).hexdigest()+'  '+name+'\n' for name,data in sorted(contents.items()))
    contents['SHA256SUMS.txt'] = manifest.encode()
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(contents.items()):
            info = zipfile.ZipInfo(NAME+'/'+name, date_time=(2026,11,8,12,0,0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        for name, data in contents.items():
            assert archive.read(NAME+'/'+name) == data
    return output

if __name__ == '__main__':
    output = build()
    print(output.name, output.stat().st_size, 'bytes')

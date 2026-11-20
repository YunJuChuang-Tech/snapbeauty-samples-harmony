"""Build Harmony host makeup from the sample's own artwork."""
import hashlib
import json
from pathlib import Path
import tempfile
import uuid
import zlib

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'HostAssetsSource'
OUTPUT = ROOT / 'entry/src/main/resources/rawfile/demo-makeup'


def prepare():
    manifest_bytes = (SOURCE / 'sample_makeup/manifest.json').read_bytes()
    source = json.loads(manifest_bytes)
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='makeup-stage-', dir=build) as temporary:
        stage = Path(temporary) / 'assets'
        stage.mkdir()
        images = {}

        def save(data, suffix):
            raw_digest = hashlib.sha256(data).hexdigest()
            compressed = zlib.compress(data, level=6)
            digest = hashlib.sha256(compressed).hexdigest()
            relative = 'decoded/' + digest + suffix + '.zlib'
            path = stage / relative
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(compressed)
            return {
                'file': relative,
                'sha256': digest,
                'rawSha256': raw_digest,
                'bytes': len(data),
                'compressedBytes': len(compressed),
                'encoding': 'zlib',
            }

        for relative, record in source['files'].items():
            path = (SOURCE / relative).resolve()
            if not path.is_relative_to((SOURCE / 'makeup').resolve()):
                raise ValueError('Unsafe makeup path: ' + relative)
            data = path.read_bytes()
            if hashlib.sha256(data).hexdigest() != record['sha256']:
                raise ValueError('Makeup source checksum differs: ' + relative)
            if path.suffix == '.json':
                target = stage / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                continue
            with Image.open(path) as image:
                rgba = np.array(image.convert('RGBA'), dtype=np.uint8)
            color = rgba[:, :, :3].astype(np.uint16)
            alpha = rgba[:, :, 3:4].astype(np.uint16)
            rgba[:, :, :3] = ((color * alpha) // 255).astype(np.uint8)
            item = {'width': int(rgba.shape[1]), 'height': int(rgba.shape[0]),
                    'premultiplied': True, **save(rgba.tobytes(), '.rgba')}
            a = rgba[:, :, 3:4].astype(np.float32) * np.float32(1 / 255)
            c = rgba[:, :, :3].astype(np.float32) * np.float32(1 / 255)
            reciprocal = np.divide(np.float32(1), a, out=np.zeros_like(a), where=a != 0)
            straight = np.minimum(255, np.rint(c * reciprocal * np.float32(255))).astype(np.uint8)
            bgra = np.concatenate([straight[:, :, ::-1], rgba[:, :, 3:4]], axis=2)
            item['argb'] = save(bgra.tobytes(), '.argb')
            images[relative] = item
        (stage / 'resources.json').write_text(json.dumps({'schema': 1, 'images': images}, indent=2) + '\n', encoding='utf-8')
        # CC BY-SA host filter LUTs: decoded once here to opaque RGBA8 for SnapBeautyEngine.registerFilter;
        # their attribution, change notes and licence text ship next to them (host-filters/NOTICE.md).
        filters_source = SOURCE / 'host-filters'
        filters_manifest = json.loads((filters_source / 'manifest.json').read_text(encoding='utf-8'))
        (stage / 'host-filters/luts').mkdir(parents=True)
        for name in ['NOTICE.md', 'LICENSE-CC-BY-SA-4.0.txt', 'RawTherapee-README.txt']:
            (stage / 'host-filters' / name).write_bytes((filters_source / name).read_bytes())
        if hashlib.sha256((filters_source / filters_manifest['license']['file']).read_bytes()).hexdigest() != filters_manifest['license']['sha256']:
            raise ValueError('Host filter licence text differs from its manifest')
        host_filters = []
        for row in filters_manifest['files']:
            png = (filters_source / row['file']).read_bytes()
            if hashlib.sha256(png).hexdigest() != row['sha256']:
                raise ValueError('Host filter checksum differs: ' + row['file'])
            with Image.open(filters_source / row['file']) as image:
                if image.mode != 'RGB' or image.size != (row['width'], row['height']):
                    raise ValueError('Host filter must be an RGB8 LUT: ' + row['file'])
                rgba = np.array(image.convert('RGBA'), dtype=np.uint8)
            relative = 'host-filters/luts/' + row['id'] + '.rgba'
            (stage / relative).write_bytes(rgba.tobytes())
            host_filters.append({'id': row['id'], 'file': relative, 'width': row['width'], 'height': row['height']})
        (stage / 'host-filters/index.json').write_text(json.dumps({'schema': 1, 'filters': host_filters}, indent=2) + '\n', encoding='utf-8')
        catalog = {'skin': [], 'shape': [], 'filters': [], 'makeup': [
            {'key': style['key'], 'label': style['name'], 'icon': '', 'filter': style['filter']}
            for style in source['styles']]}
        (stage / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        files = [p for p in sorted(stage.rglob('*')) if p.is_file()]
        manifest = {'schema': 1, 'sourceSha256': hashlib.sha256(manifest_bytes).hexdigest(), 'files': [
            {'path': p.relative_to(stage).as_posix(), 'bytes': p.stat().st_size,
             'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in files]}
        (stage / 'asset-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        if not OUTPUT.resolve().is_relative_to(ROOT.resolve()):
            raise ValueError('Generated makeup output resolves outside Harmony project')
        if OUTPUT.exists():
            OUTPUT.rename(build / ('makeup-backup-' + uuid.uuid4().hex))
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        stage.rename(OUTPUT)
    print(f'Prepared host makeup: {len(images)} images / {len(source["styles"])} styles from shared sample assets, plus 10 host filters')
    return OUTPUT


if __name__ == '__main__':
    prepare()

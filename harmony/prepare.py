"""Verify the published SDK and prepare host resources. No SDK source imports."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import uuid
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--har', type=Path, help='Optional local copy of the pinned HAR')
    args = parser.parse_args()
    artifact = json.loads((ROOT.parent / 'sdk.lock.json').read_text(encoding='utf-8'))['artifacts']['harmony']
    output = ROOT / '.local/snapbeauty.har'
    output.parent.mkdir(parents=True, exist_ok=True)
    if args.har is None:
        url = f'https://ohpm.openharmony.cn/ohpm/@snapbeauty/core/-/core-{artifact["version"]}.har'
        with urlopen(url, timeout=60) as response:
            data = response.read()
    else:
        data = args.har.read_bytes()
    if len(data) != artifact['bytes'] or hashlib.sha256(data).hexdigest() != artifact['sha256']:
        raise SystemExit('HAR does not match sdk.lock.json; supply the pinned HarmonyOS release artifact')
    import io
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        package = json.load(archive.extractfile('package/oh-package.json5'))
        if package['name'] != '@snapbeauty/core' or package['version'] != artifact['version']:
            raise SystemExit('Unexpected SDK package identity')
        engine_prefix = 'package/src/main/resources/rawfile/engine/'
        if any(name.startswith((engine_prefix + 'makeup/', engine_prefix + 'icons/')) or
               name == engine_prefix + 'catalog.json' for name in archive.getnames()):
            raise SystemExit('SDK must not bundle host makeup or panel artwork')
        index = json.load(archive.extractfile(engine_prefix + 'resources.json'))
        if any(name.startswith('makeup/') for name in index['images']):
            raise SystemExit('SDK image index contains host makeup')
        standard = 'package/src/main/module.json' in archive.getnames()
        # Move the previous generated fallback aside before changing SDK versions.
        # A standard HAR merges its own native library and rawfiles through Hvigor.
        payloads = {
            'package/libs/': ROOT / 'entry/libs',
            'package/src/main/resources/rawfile/engine/': ROOT / 'entry/src/main/resources/rawfile/engine',
        }
        backup = ROOT / '.local' / ('sdk-backup-' + uuid.uuid4().hex)
        for destination in [*payloads.values(), ROOT / 'entry/src/main/resources/rawfile/sdk-notices']:
            if destination.exists():
                if not destination.resolve().is_relative_to(ROOT.resolve()):
                    raise SystemExit(f'Generated payload resolves outside the project: {destination}')
                target = backup / destination.relative_to(ROOT)
                target.parent.mkdir(parents=True, exist_ok=True)
                destination.rename(target)
        for member in archive.getmembers():
            if standard:
                break
            for prefix, destination in payloads.items():
                if not member.name.startswith(prefix) or member.isdir():
                    continue
                relative = member.name[len(prefix):]
                if not member.isfile() or not relative or any(p in ('', '.', '..') for p in relative.split('/')) or '\\' in relative or ':' in relative:
                    raise SystemExit(f'Unsafe HAR entry: {member.name}')
                output_file = destination / relative
                content = archive.extractfile(member).read()
                if output_file.exists() and output_file.read_bytes() != content:
                    raise SystemExit(f'Refusing to overwrite a different payload: {output_file}')
                output_file.parent.mkdir(parents=True, exist_ok=True)
                output_file.write_bytes(content)
        notices = ROOT / 'entry/src/main/resources/rawfile/sdk-notices'
        notices.mkdir(parents=True, exist_ok=True)
        for name in ('NOTICE',):
            (notices / name).write_bytes(archive.extractfile('package/' + name).read())
        (notices / 'Monocypher.txt').write_bytes(archive.extractfile('package/Licenses/Monocypher.txt').read())
    output.write_bytes(data)
    license_file = ROOT / '.local/snapbeauty.license'
    if not license_file.is_file():
        license_file = ROOT / 'SampleLicense/snapbeauty.license'
    staged_license = ROOT / 'entry/src/main/resources/rawfile/snapbeauty.license'
    if license_file.is_file():
        staged_license.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(license_file, staged_license)
    elif staged_license.exists():
        staged_license.unlink()
    from prepare_makeup import prepare
    prepare()
    print(f'Verified {artifact["version"]}: {output}')
    print('Next: run ohpm install from the harmony directory, then build entry/default.')


if __name__ == '__main__':
    main()

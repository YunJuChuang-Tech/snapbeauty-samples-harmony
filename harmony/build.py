"""Build the unsigned sample with an installed API12 SDK and pinned Hvigor 5.7.0."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, required=True, help='SDK root containing 12/ets, 12/native, ...')
    parser.add_argument('--tooling', type=Path, default=ROOT / '.local/tooling')
    args = parser.parse_args()
    from prepare_makeup import prepare
    makeup_assets = prepare()
    artifact = json.loads((ROOT.parent / 'sdk.lock.json').read_text(encoding='utf-8'))['artifacts']['harmony']
    har = ROOT / '.local/snapbeauty.har'
    if har.stat().st_size != artifact['bytes'] or hashlib.sha256(har.read_bytes()).hexdigest() != artifact['sha256']:
        raise SystemExit('Local HAR does not match sdk.lock.json; rerun prepare.py')
    installed = ROOT / 'entry/oh_modules/@snapbeauty/core'
    # Check the package OHPM actually resolved, including public API, rawfiles and SO.
    with tarfile.open(har) as archive:
        standard = 'package/src/main/module.json' in archive.getnames()
        for member in archive.getmembers():
            if not member.isfile():
                continue
            relative = member.name.removeprefix('package/')
            expected = archive.extractfile(member).read()
            if (installed / relative).read_bytes() != expected:
                raise SystemExit(f'Installed HAR content differs from the pinned release: {relative}')
            if not standard and relative.startswith('libs/') and (ROOT / 'entry' / relative).read_bytes() != expected:
                raise SystemExit(f'Host native library differs from the pinned release: {relative}')
    sdk = args.sdk.resolve(strict=True)
    modules = args.tooling.resolve(strict=True) / 'node_modules'
    for name in ('hvigor', 'hvigor-ohos-plugin'):
        if json.loads((modules / '@ohos' / name / 'package.json').read_text())['version'] != '5.7.0':
            raise SystemExit(f'Expected {name} 5.7.0')
    for name in ('ets', 'js', 'native', 'toolchains', 'previewer'):
        metadata = json.loads((sdk / '12' / name / 'oh-uni-package.json').read_text())
        if int(metadata['apiVersion']) != 12 or metadata['version'] != '5.0.0.71':
            raise SystemExit(f'Expected SDK 5.0.0.71/API12: {name}')
    target = ROOT / 'node_modules'
    if not target.exists():
        if os.name == 'nt':
            quote = lambda value: "'" + str(value).replace("'", "''") + "'"
            subprocess.run(['powershell', '-NoProfile', '-Command',
                            f'New-Item -ItemType Junction -Path {quote(target)} -Target {quote(modules)} | Out-Null'], check=True)
        else:
            target.symlink_to(modules, target_is_directory=True)
    elif not target.samefile(modules):
        raise SystemExit(f'Refusing to replace existing node_modules: {target}')
    (ROOT / 'local.properties').write_text(f'sdk.dir={sdk.as_posix()}\n', encoding='utf-8')
    env = os.environ.copy()
    env['OHOS_BASE_SDK_HOME'] = str(sdk)
    env['NODE_PATH'] = str(modules)
    subprocess.run([shutil.which('node'), str(modules / '@ohos/hvigor/bin/hvigor.js'),
                    '--mode', 'module', '-p', 'product=default', '-p', 'module=entry@default',
                    '--no-daemon', '--no-parallel', 'assembleHap'], cwd=ROOT, env=env, check=True)
    output = ROOT / 'entry/build/default/outputs/default/entry-default-unsigned.hap'
    with zipfile.ZipFile(output) as hap:
        names = hap.namelist()
        if 'ets/modules.abc' not in names or not any(n.endswith('libsnapbeauty_demo.so') for n in names):
            raise SystemExit('HAP is missing bytecode or the SDK native library')
        prefix = 'resources/rawfile/engine/'
        manifest = json.loads(hap.read(prefix + 'asset-manifest.json'))
        if manifest['schema'] != 1 or not manifest['files']:
            raise SystemExit('HAP engine resource manifest is invalid')
        for record in manifest['files']:
            data = hap.read(prefix + record['path'])
            if len(data) != record['bytes'] or hashlib.sha256(data).hexdigest() != record['sha256']:
                raise SystemExit(f'HAP resource hash mismatch: {record["path"]}')
        if any(r['path'].startswith(('makeup/', 'icons/')) or r['path'] == 'catalog.json' for r in manifest['files']):
            raise SystemExit('SDK must not bundle host makeup or panel artwork')
        host_prefix = 'resources/rawfile/demo-makeup/'
        host_manifest = json.loads(hap.read(host_prefix + 'asset-manifest.json'))
        for record in host_manifest['files']:
            data = hap.read(host_prefix + record['path'])
            if len(data) != record['bytes'] or hashlib.sha256(data).hexdigest() != record['sha256']:
                raise SystemExit(f'HAP host makeup mismatch: {record["path"]}')
        if hap.read(host_prefix + 'asset-manifest.json') != (makeup_assets / 'asset-manifest.json').read_bytes():
            raise SystemExit('HAP host makeup manifest differs from shared sample assets')
        for asset_prefix, asset_manifest in [(prefix, manifest), (host_prefix, host_manifest)]:
            expected = {asset_prefix + r['path'] for r in asset_manifest['files']} | {asset_prefix + 'asset-manifest.json'}
            if asset_prefix == prefix:
                for name in ('Monocypher.txt', 'SDK-NOTICE.md'):
                    path = 'licenses/' + name
                    if hap.read(prefix + path) != (installed / 'src/main/resources/rawfile/engine' / path).read_bytes():
                        raise SystemExit(f'HAP SDK license differs from the resolved package: {name}')
                    expected.add(prefix + path)
            actual = {name for name in names if name.startswith(asset_prefix) and not name.endswith('/')}
            if actual != expected:
                raise SystemExit('HAP includes stale or unlisted resources: ' + asset_prefix)
        expected_manifest = (installed / 'src/main/resources/rawfile/engine/asset-manifest.json').read_bytes()
        if hap.read(prefix + 'asset-manifest.json') != expected_manifest:
            raise SystemExit('HAP manifest differs from pinned SDK')
        for name, source in [('NOTICE', 'NOTICE'), ('Monocypher.txt', 'Licenses/Monocypher.txt')]:
            if hap.read('resources/rawfile/sdk-notices/' + name) != (installed / source).read_bytes():
                raise SystemExit(f'HAP is missing the SDK notice: {name}')
        module = json.loads(hap.read('module.json'))
        if module['app']['bundleName'] != 'ai.snapbeauty.samples':
            raise SystemExit('Unexpected bundle name')
        library = hap.read('libs/arm64-v8a/libsnapbeauty_demo.so')
        if library[:4] != b'\x7fELF' or library[4] != 2 or int.from_bytes(library[18:20], 'little') != 183:
            raise SystemExit('Expected arm64 ELF native library')
    receipt = {'sdk': 'OpenHarmony 5.0.0.71/API12', 'hvigor': '5.7.0', 'signed': False,
               'deviceValidated': False, 'sdkArtifact': artifact, 'verifiedEngineResources': len(manifest['files']),
               'verifiedHostResources': len(host_manifest['files']),
               'nativeLibrarySha256': hashlib.sha256(library).hexdigest(),
               'output': str(output), 'bytes': output.stat().st_size,
               'sha256': hashlib.sha256(output.read_bytes()).hexdigest()}
    report = ROOT / 'build/build-report.json'
    report.parent.mkdir(exist_ok=True)
    report.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()

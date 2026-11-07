#!/usr/bin/env python3
"""Provision one pinned tmux release on Linux x86_64; never install packages."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import selectors
import shutil
import signal
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request


def sha256(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def binary_record(path, version, env):
    with path.open('rb') as stream:
        header = stream.read(20)
    if len(header) != 20 or header[:6] != b'\x7fELF\x02\x01' or struct.unpack('<H', header[18:20])[0] != 62:
        raise RuntimeError('Artifact is not x86_64 ELF')
    shown = subprocess.check_output([str(path), '-V'], env=env, text=True, timeout=5).strip()
    if shown != 'tmux '+version:
        raise RuntimeError('Unexpected binary version: '+shown)
    return {'path': str(path), 'sha256': sha256(path), 'version_output': shown}


def build_identity(args, cell, env):
    compiler = subprocess.check_output(['cc', '--version'], text=True).splitlines()[0]
    libraries = {name: subprocess.check_output(['pkg-config', '--modversion', name], text=True).strip()
                 for name in ['libevent', 'ncurses']}
    packages = subprocess.check_output(
        ['dpkg-query', '-W', '-f=${Package}=${Version}\n', 'gcc', 'libc6', 'libevent-dev', 'libncurses-dev',
         'autoconf', 'automake', 'byacc', 'make', 'pkg-config'], text=True).splitlines()
    return {'source': cell, 'manifest_sha256': sha256(args.manifest),
            'provisioner_sha256': sha256(__file__), 'compiler': compiler, 'libraries': libraries,
            'packages': sorted(packages), 'environment': {name: env[name] for name in ['CC', 'CFLAGS', 'LC_ALL', 'CONFIG_SITE']},
            'host': {'system': platform.system(), 'machine': platform.machine(),
                     'os_release': platform.freedesktop_os_release(),
                     'image_os': os.environ.get('ImageOS'), 'image_version': os.environ.get('ImageVersion')}}


def command(argv, cwd, env, log, records):
    started = time.monotonic()
    timed_out = False
    with log.open('wb') as output:
        process = subprocess.Popen(argv, cwd=cwd, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        fd = os.pidfd_open(process.pid)
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(fd, selectors.EVENT_READ)
                if not selector.select(300):
                    timed_out = True
                    os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        finally:
            os.close(fd)
    records.append({'argv': argv, 'cwd': str(cwd), 'seconds': time.monotonic()-started,
                    'exit': process.returncode, 'timed_out': timed_out,
                    'log': str(log), 'log_sha256': sha256(log)})
    if timed_out or process.returncode:
        raise RuntimeError(f'{argv[0]} failed; inspect {log.name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--cache-dir', type=Path, required=True)
    parser.add_argument('--jobs', type=int, choices=[1, 2], default=2)
    parser.add_argument('--print-cache-key', action='store_true', help='Print key=VALUE without downloading or building')
    parser.add_argument('--reuse', action='store_true', help='Validate and reuse a matching provisioned binary')
    args = parser.parse_args()
    started = time.monotonic()
    cells = json.loads(args.manifest.read_text())['cells']
    matches = [cell for cell in cells if cell['tmux'] == args.version]
    if len(matches) != 1:
        parser.error('Select one exact version from the manifest')
    cell = matches[0]
    if not re.fullmatch(r'[0-9]+\.[0-9]+[a-z]?', args.version):
        parser.error('Invalid version key')
    if not re.fullmatch('[0-9a-f]{40}', cell['commit']) or not re.fullmatch('[0-9a-f]{64}', cell.get('archive_sha256', '')):
        parser.error('The manifest must pin a full commit and archive SHA256')
    url = f'https://codeload.github.com/tmux/tmux/tar.gz/{cell["commit"]}'
    if cell.get('archive_url') != url:
        parser.error('The archive URL must identify the exact pinned tmux commit')
    output, cache = args.output_dir.resolve(), args.cache_dir.resolve()
    logs = output/'logs'/args.version
    for directory in [logs, output/'provenance', cache/'archives', cache/'builds']:
        directory.mkdir(parents=True, exist_ok=True)
    record = {'tmux': args.version, 'purpose': cell['purpose'], 'scope': 'provisioning-only',
              'native_runtime_evidence': 'UNVERIFIED', 'argv': sys.argv,
              'manifest_sha256': sha256(args.manifest), 'provisioner_sha256': sha256(__file__),
              'source': cell, 'commands': [], 'host': {'system': platform.system(),
              'machine': platform.machine(), 'kernel': platform.release()}, 'jobs': args.jobs}
    build = None
    destination = output/'bin'/args.version/'tmux'
    provenance = output/'provenance'/(args.version+'.json')
    try:
        if platform.system() != 'Linux' or platform.machine() != 'x86_64':
            raise RuntimeError('This matrix requires Linux x86_64')
        needed = ['cc', 'make', 'autoconf', 'automake', 'aclocal', 'autoreconf', 'yacc', 'pkg-config']
        missing = [tool for tool in needed if shutil.which(tool) is None]
        if missing:
            raise RuntimeError('Missing build prerequisites: '+', '.join(missing))
        env = dict(os.environ, CC='cc', CFLAGS='-O2', LC_ALL='C', CONFIG_SITE='/dev/null')
        for name in ['CPPFLAGS', 'LDFLAGS', 'LIBS', 'MAKEFLAGS', 'MFLAGS']:
            env.pop(name, None)
        identity = build_identity(args, cell, env)
        fingerprint = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
        record.update(compiler=identity['compiler'], libraries=identity['libraries'],
                      environment=identity['environment'], build_identity=identity,
                      cache_key=f'tmux-{args.version}-{fingerprint}', reused=False)
        if args.print_cache_key:
            print('key='+record['cache_key'])
            return 0
        if args.reuse and provenance.exists():
            try:
                if provenance.stat().st_size > 1048576:
                    raise RuntimeError('Cached provenance exceeds 1 MiB')
                previous = json.loads(provenance.read_text())
                if previous.get('provisioning') != 'PASS' or previous.get('build_identity') != identity:
                    raise RuntimeError('Cached build identity does not match')
                if sha256(destination) != previous['binary']['sha256']:
                    raise RuntimeError('Cached binary SHA256 mismatch')
                record['binary'] = binary_record(destination, args.version, env)
                record['provisioning'] = 'PASS'
                record['reused'] = True
                record['build_commands'] = previous.get('build_commands', previous['commands'])
                return 0
            except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
                record['cache_rejection'] = str(error)
        archive = cache/'archives'/f'{cell["commit"]}.tar.gz'
        if not archive.exists():
            fd, name = tempfile.mkstemp(prefix=cell['commit']+'-', suffix='.download', dir=cache/'archives')
            temporary = Path(name)
            try:
                with os.fdopen(fd, 'wb') as download_stream, urllib.request.urlopen(url, timeout=30) as response:
                    size = 0
                    while block := response.read(1024 * 1024):
                        size += len(block)
                        if size > 64 * 1024 * 1024:
                            raise RuntimeError('Source archive exceeds 64 MiB')
                        download_stream.write(block)
                if sha256(temporary) != cell['archive_sha256']:
                    raise RuntimeError('Downloaded archive SHA256 mismatch')
                temporary.replace(archive)
            finally:
                temporary.unlink(missing_ok=True)
        if sha256(archive) != cell['archive_sha256']:
            raise RuntimeError('Cached archive SHA256 mismatch')
        record['archive_verified'] = True
        build = Path(tempfile.mkdtemp(prefix=f'tmux-{args.version}-', dir=cache/'builds'))
        with tarfile.open(archive, 'r:gz') as source:
            if any(member.name.split('/')[0] != 'tmux-'+cell['commit'] for member in source.getmembers()):
                raise RuntimeError('Archive root differs from pinned commit')
            source.extractall(build, filter='data')
        source = build/('tmux-'+cell['commit'])
        for stage, argv in [('autogen', ['sh', 'autogen.sh']), ('configure', ['./configure', '--prefix=/usr/local', '--sysconfdir=/etc']), ('make', ['make', f'-j{args.jobs}'])]:
            print(f'{args.version}: {stage}', file=sys.stderr, flush=True)
            command(argv, source, env, logs/(stage+'.log'), record['commands'])
        binary = source/'tmux'
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(binary, destination)
        destination.chmod(0o755)
        record['binary'] = binary_record(destination, args.version, env)
        record['provisioning'] = 'PASS'
    except Exception as error:
        record['provisioning'] = 'FAIL'
        record['failure'] = str(error)
        if args.print_cache_key:
            print(str(error), file=sys.stderr)
    finally:
        if build is not None:
            source = build/('tmux-'+cell['commit'])
            for name in ['config.log', 'config.status', 'config.h', 'Makefile']:
                if (source/name).exists():
                    shutil.copy2(source/name, logs/name)
            shutil.rmtree(build)
            record['build_directory_removed'] = not build.exists()
        if not args.print_cache_key:
            record['whole_seconds'] = time.monotonic()-started
            provenance.write_text(json.dumps(record, indent=2)+'\n')
            print(json.dumps({'provisioning': record.get('provisioning', 'FAIL'), 'reused': record.get('reused', False),
                              'native_runtime_evidence': 'UNVERIFIED', 'binary': record.get('binary'),
                              'provenance': str(provenance), 'failure': record.get('failure')}))
    return 0 if record['provisioning']=='PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())

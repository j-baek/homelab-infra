#!/usr/bin/env python3
"""Operate this local libvirt lab without requiring kubectl on the host."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tarfile
import time
import urllib.request
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / '.local'


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def inventory():
    result = run(['terraform', f'-chdir={ROOT / "terraform"}', 'output', '-json', 'nodes'], capture_output=True, text=True)
    nodes = json.loads(result.stdout)
    if not nodes or len([n for n in nodes.values() if n['role'] == 'server']) != 1:
        raise RuntimeError('Apply the configuration first: expected a node inventory with one server.')
    return nodes


def ssh_args(node):
    args = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5',
            '-o', 'StrictHostKeyChecking=accept-new',
            '-o', f'UserKnownHostsFile={LOCAL / "known_hosts"}']
    if os.environ.get('LAB_SSH_KEY'):
        args += ['-i', os.path.expanduser(os.environ['LAB_SSH_KEY'])]
    return args + [f'{node["user"]}@{node["ip"]}']


def remote(node, command, **kwargs):
    return run(ssh_args(node) + [command], **kwargs)


def kubectl(server, args, **kwargs):
    return remote(server, shlex.join(['sudo', 'k3s', 'kubectl', *args]), **kwargs)


def readiness_errors(nodes, actual):
    expected = {n['name']: n for n in nodes.values()}
    found = {n['metadata']['name']: n for n in actual['items']}
    errors = []
    if set(found) != set(expected):
        errors.append(f'Expected nodes {sorted(expected)}, found {sorted(found)}')
    for name in expected.keys() & found.keys():
        status = found[name].get('status', {})
        if not any(c['type'] == 'Ready' and c['status'] == 'True' for c in status.get('conditions', [])):
            errors.append(f'{name} is not Ready')
        ips = [a['address'] for a in status.get('addresses', []) if a['type'] == 'InternalIP']
        if expected[name]['ip'] not in ips:
            errors.append(f'{name} has unexpected InternalIP: {ips}')
    return errors


def check(nodes, server, wait):
    deadline = time.monotonic() + wait
    while True:
        try:
            for node in nodes.values():
                service = 'k3s' if node['role'] == 'server' else 'k3s-agent'
                remote(node, 'sudo test -f /var/lib/homelab/bootstrap-complete && '
                       f'sudo systemctl is-active --quiet {service}', capture_output=True, text=True, timeout=15)
            result = kubectl(server, ['get', 'nodes', '-o', 'json'], capture_output=True, text=True, timeout=20)
            errors = readiness_errors(nodes, json.loads(result.stdout))
            if errors:
                raise RuntimeError('; '.join(errors))
            kubectl(server, ['get', 'nodes', '-o', 'wide'])
            kubectl(server, ['get', 'pods', '-A'])
            print('PASS: every expected node has completed bootstrap, an active k3s service, and the expected Ready/IP status.')
            return
        except (subprocess.SubprocessError, RuntimeError) as exc:
            if time.monotonic() >= deadline:
                if isinstance(exc, subprocess.CalledProcessError):
                    print((exc.stderr or '').strip(), file=sys.stderr)
                raise
            print('Waiting for bootstrap and node readiness...', flush=True)
            time.sleep(min(10, max(0, deadline - time.monotonic())))


def smoke(server):
    # Keep the manifest in Git so the test is inspectable and can be removed later.
    with (ROOT / 'examples/smoke.yaml').open() as source:
        kubectl(server, ['apply', '-f', '-'], stdin=source)
    kubectl(server, ['-n', 'homelab-smoke', 'rollout', 'status', 'deployment/web', '--timeout=180s'])
    # Ready pods can precede kube-proxy's NodePort rules. Allow bounded convergence.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    deadline = time.monotonic() + 60
    while True:
        try:
            with opener.open(f'http://{server["ip"]}:30080', timeout=10) as response:
                body = response.read().decode()
            if 'Welcome to nginx!' not in body:
                raise RuntimeError('The NodePort returned an unexpected page.')
            break
        except (urllib.error.URLError, TimeoutError):
            if time.monotonic() >= deadline:
                raise
            time.sleep(2)
    print(f'PASS: test application responds at http://{server["ip"]}:30080')


def kubeconfig(server):
    result = remote(server, 'sudo cat /etc/rancher/k3s/k3s.yaml', capture_output=True, text=True)
    content = result.stdout.replace('https://127.0.0.1:6443', f'https://{server["ip"]}:6443')
    path = LOCAL / 'kubeconfig'
    path.write_text(content)
    path.chmod(0o600)
    print(f'Wrote private administrator credentials to {path}. Do not commit or share them.')


def backup(server):
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    directory = LOCAL / 'backups' / stamp
    directory.mkdir(parents=True, mode=0o700)
    # Stop SQLite's writer while archiving. Always attempt to restart k3s on exit.
    command = """set -eu
trap 'systemctl start k3s' EXIT
systemctl stop k3s
tar -C / -czf - var/lib/rancher/k3s/server/db var/lib/rancher/k3s/server/token etc/rancher/k3s
"""
    try:
        with (directory / 'server.tar.gz').open('wb') as destination:
            remote(server, 'sudo sh -c ' + shlex.quote(command), stdout=destination)
        with tarfile.open(directory / 'host.tar.gz', 'w:gz') as archive:
            for name in ['terraform/terraform.tfstate', 'terraform/terraform.tfvars', 'terraform/.terraform.lock.hcl']:
                archive.add(ROOT / name, arcname=name)
    except BaseException:
        (directory / 'INCOMPLETE').write_text('Backup failed; do not restore this set.\n')
        raise
    print(f'Backup written to {directory}. Contains secrets; copy securely off this laptop.')
    print('Application volume data is NOT included. Back up application data separately.')


def main():
    os.umask(0o077)
    LOCAL.mkdir(mode=0o700, exist_ok=True)
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('check', help='Verify SSH, bootstrap, services, and exact node readiness/IPs')
    p.add_argument('--wait', type=int, default=0, help='Retry for this many seconds')
    sub.add_parser('smoke', help='Deploy a small nginx test and verify HTTP from the host')
    sub.add_parser('kubeconfig', help='Save administrator credentials privately in .local/kubeconfig')
    sub.add_parser('backup', help='Briefly stop the server to back up SQLite, its token, and host state')
    p = sub.add_parser('ssh', help='Connect to a node; optional command follows its inventory name')
    p.add_argument('node')
    p.add_argument('args', nargs=argparse.REMAINDER)
    p = sub.add_parser('kubectl', help='Run kubectl on the server with sudo')
    p.add_argument('args', nargs=argparse.REMAINDER)
    # Preserve kubectl flags even when they precede its verb, e.g. -n namespace get pods.
    argv = sys.argv[1:]
    if argv and argv[0] == 'kubectl' and len(argv) > 1:
        args = argparse.Namespace(command='kubectl', args=argv[1:])
    else:
        args = parser.parse_args(argv)
    nodes = inventory()
    server = next(n for n in nodes.values() if n['role'] == 'server')
    if args.command == 'check':
        check(nodes, server, args.wait)
    elif args.command == 'smoke':
        smoke(server)
    elif args.command == 'kubeconfig':
        kubeconfig(server)
    elif args.command == 'backup':
        backup(server)
    elif args.command == 'kubectl':
        kubectl(server, args.args)
    elif args.command == 'ssh':
        if args.node not in nodes:
            parser.error(f'Unknown node. Choose from: {", ".join(nodes)}')
        run(ssh_args(nodes[args.node]) + ([shlex.join(args.args)] if args.args else []))


if __name__ == '__main__':
    try:
        main()
    except (subprocess.SubprocessError, RuntimeError, OSError, ValueError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        sys.exit(1)

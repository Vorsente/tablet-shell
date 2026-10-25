#!/usr/bin/env python3
"""Track files deployed by tablet-shell; prune only previously recorded, unchanged files.

No packages, arbitrary application data, user KDE settings or unknown third-party files
are ever uninstalled here. Old manifests must exist to establish file ownership.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import sys
import tempfile

SCHEMA = 1


def source_map(src, reuse_keyboard=False):
    """Map package-owned source artifacts to their installed relative paths."""
    results = {}

    def add(source, destination):
        s = src / source
        if s.is_file():
            results[destination] = s

    def tree(source, destination):
        base = src / source
        if not base.is_dir():
            return
        for path in base.rglob('*'):
            if path.is_file() and not path.is_symlink():
                results[str(PurePosixPath(destination) / PurePosixPath(path.relative_to(base).as_posix()))] = path

    for name in ('tabletshell', 'tablet-settings', 'tablet-keyboard', 'tablet-greeter'):
        if name == 'tablet-keyboard' and reuse_keyboard:
            continue
        tree('src/' + name, '.local/share/' + name)
    add('src/webapp-runner/webapp.qml', '.local/share/webapps/runner/webapp.qml')
    for base, dest in [
        ('shell/plasmoids', '.local/share/plasma/plasmoids'),
        ('shell/wallpapers', '.local/share/plasma/wallpapers'),
        ('shell/wallpaper-packs', '.local/share/wallpapers'),
        ('shell/look-and-feel', '.local/share/plasma/look-and-feel'),
        ('shell/desktoptheme', '.local/share/plasma/desktoptheme'),
        ('shell/color-schemes', '.local/share/color-schemes'),
        ('shell/icons', '.local/share/icons'),
        ('shell/kwin/scripts', '.local/share/kwin/scripts'),
        ('shell/tablet-mode', '.local/share/tablet-mode'),
        ('system', '.local/share/tablet-shell/system'),
        ('bin', '.local/bin'),
        ('applications', '.local/share/applications'),
        ('systemd', '.config/systemd/user'),
        ('data/typewriter/sounds', '.local/share/typewriter/sounds'),
        ('data/ghostwriter', '.local/share/ghostwriter/themes'),
    ]:
        tree(base, dest)
    add('update.sh', '.local/share/tablet-shell/update.sh')
    add('build/en.json', '.local/share/tablet-i18n/en.json')
    add('build/weather.frag.qsb', '.local/share/plasma/plasmoids/org.ipad.homescreen/contents/ui/shaders/weather.frag.qsb')
    add('src/webapp-runner/webapp.qml', '.local/share/webapps/runner/webapp.qml')
    for name in ('tabletd', 'tablet-tools'):
        add('build/' + name, '.local/share/tabletd/' + name)
    for name in ('tabletshell', 'tablet-settings', 'tablet-keyboard', 'tablet-greeter'):
        if name == 'tablet-keyboard' and reuse_keyboard:
            continue
        add('build/' + name, '.local/share/' + name + '/' + name)
    add('build/webapp-runner', '.local/share/webapps/runner/webapp-runner')
    for name, dest in [('shell', 'tabletshell'), ('keyboard', 'tablet-keyboard')]:
        if name == 'keyboard' and reuse_keyboard:
            continue
        tree('build/sounds/' + name, '.local/share/' + dest + '/sounds')
    # Helpers are deployed as known symlinks, not owned copies.
    links = {'tabletd':'tabletd/tabletd', 'tabletshell':'tabletshell/tabletshell',
             'tablet-settings':'tablet-settings/tablet-settings',
             'tablet-keyboard':'tablet-keyboard/tablet-keyboard',
             'webapp-runner':'webapps/runner/webapp-runner'}
    links.update({name:'tabletd/tablet-tools' for name in
                  ('tablet-tools','wallpaper','webapp-create','screentime-apps')})
    for name, target in links.items():
        # A link is installed only when its backing executable was built. A
        # keyboard fallback deliberately leaves its existing link untouched.
        program = target.split('/')[-1]
        if program in ('tabletd', 'tablet-tools', 'tabletshell', 'tablet-settings',
                       'tablet-keyboard', 'webapp-runner'):
            if program == 'tablet-keyboard' and reuse_keyboard:
                continue
            if not (src / 'build' / program).is_file():
                continue
        results['.local/bin/' + name] = 'symlink:.local/share/' + target
    return results


def safe_rel(path):
    if not isinstance(path, str) or not path or '\\' in path or '\0' in path:
        return False
    p = PurePosixPath(path)
    return (not p.is_absolute() and '..' not in p.parts and
            (path.startswith('.local/share/') or path.startswith('.local/bin/') or
             path.startswith('.config/systemd/user/')))


def digest_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as file:
        for block in iter(lambda: file.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def fingerprint(path, home):
    if path.is_symlink():
        # The installed symlink's *target* is recorded, not followed.
        return 'link:' + os.readlink(path)
    if path.is_file():
        return 'sha256:' + digest_file(path)
    return None


def secure_target(home, rel):
    """Never dereference symlinked parents; prevent removing unexpected locations."""
    if not safe_rel(rel):
        raise ValueError('unsafe path in previous manifest: ' + repr(rel))
    target = home / rel
    cur = home
    for part in PurePosixPath(rel).parts[:-1]:
        cur = cur / part
        if cur.is_symlink():
            raise ValueError('refusing symlinked parent directory: ' + str(cur))
    return target


def write_atomic(path, data):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.managed-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as file:
            json.dump(data, file, ensure_ascii=False, indent=2, sort_keys=True)
            file.write('\n')
            file.flush()
            os.fsync(file.fileno())
        os.chmod(name, 0o600)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


# When a build target is skipped, preserve every installed file belonging to it.
# A compiled frontend and its QML must be from the same revision.
SKIP_PREFIXES = {
    'tabletd': ('.local/share/tabletd/tabletd', '.local/bin/tabletd'),
    'tablet-tools': ('.local/share/tabletd/tablet-tools', '.local/bin/tablet-tools',
                     '.local/bin/wallpaper', '.local/bin/webapp-create', '.local/bin/screentime-apps'),
    'tabletshell': ('.local/share/tabletshell/', '.local/bin/tabletshell'),
    'tablet-settings': ('.local/share/tablet-settings/', '.local/bin/tablet-settings'),
    'tablet-keyboard': ('.local/share/tablet-keyboard/', '.local/bin/tablet-keyboard'),
    'tablet-greeter': ('.local/share/tablet-greeter/',),
    'webapp-runner': ('.local/share/webapps/runner/', '.local/bin/webapp-runner'),
    'shaders': ('.local/share/plasma/plasmoids/org.ipad.homescreen/',),
    'translations': ('.local/share/tablet-i18n/en.json',),
    'sounds-shell': ('.local/share/tabletshell/sounds/',),
    'sounds-keyboard': ('.local/share/tablet-keyboard/sounds/',),
    # Installed lock/input related helpers, icons, service units, and greetd scripts
    # are intentionally retained during update-only runs (not pruned or replaced).
    'input-lock-assets': (
        '.local/bin/lockscreen-sync',
        '.local/share/applications/tablet-keyboard.desktop',
        '.local/share/tablet-shell/system/greeter.sh',
        '.local/share/tablet-shell/system/greeter-launch.sh',
        '.local/share/tablet-shell/system/refresh-greetd.py',
        '.config/systemd/user/lockscreen-sync.service',
        '.config/systemd/user/lockscreen-sync.path',
        '.config/systemd/user/greeter-wallpaper.timer',
        '.config/systemd/user/greeter-wallpaper.path',
    ),
}


def protected(rel, skipped):
    return any(rel.startswith(prefix) if prefix.endswith('/') else rel == prefix
               for component in skipped for prefix in SKIP_PREFIXES[component])


def reconcile(src, home, dry_run=False, reuse_keyboard=False, reuse_components=()):
    skipped = set(reuse_components)
    if reuse_keyboard:
        skipped.add('tablet-keyboard')
    if skipped - SKIP_PREFIXES.keys():
        raise ValueError('unknown skipped component(s): ' + ', '.join(sorted(skipped - SKIP_PREFIXES.keys())))
    if 'tabletshell' in skipped:
        skipped.add('sounds-shell')
    if 'tablet-keyboard' in skipped:
        skipped.add('sounds-keyboard')
    manifest = home / '.local/state/tablet-shell/managed-files.json'
    if manifest.is_file():
        with open(manifest, encoding='utf-8') as f:
            old = json.load(f)
        if old.get('schema') != SCHEMA or not isinstance(old.get('files'), dict):
            raise ValueError('unsupported or invalid managed-files.json; refusing cleanup')
        old_files = old['files']
        for name, val in old_files.items():
            if not safe_rel(name) or not isinstance(val, str) or not val.startswith(('sha256:', 'link:')):
                raise ValueError('invalid entry in managed-files.json; refusing cleanup')
    else:
        old_files = {}
    sources = source_map(src, reuse_keyboard=reuse_keyboard)
    sources = {rel: origin for rel, origin in sources.items() if not protected(rel, skipped)}
    expected = set(sources)
    # Preserve previous manifest ownership and fingerprints for skipped components.
    # This prevents a later successful build from treating current files as obsolete.
    for rel in old_files:
        if protected(rel, skipped):
            expected.add(rel)
    # Ensure all expected targets exist before pruning; do not erase anything
    # if installation was interrupted halfway through.
    missing = [rel for rel in sorted(sources) if not (home / rel).is_file() and not (home / rel).is_symlink()]
    if missing:
        raise ValueError('installation incomplete; refusing cleanup (missing: ' + ', '.join(missing[:4]) + ')')
    new_files = {}
    for rel in sorted(expected):
        target = secure_target(home, rel)
        if protected(rel, skipped) and rel not in sources:
            # Never claim ownership of changed contents until a successful keyboard build.
            new_files[rel] = old_files[rel]
        else:
            new_files[rel] = fingerprint(target, home)
    removed = []
    preserved = []
    for rel, original in sorted(old_files.items()):
        if rel in expected:
            continue
        target = secure_target(home, rel)
        current = fingerprint(target, home)
        if current is None:
            continue
        if current != original:
            preserved.append(rel)
            continue
        if not dry_run:
            target.unlink()
            # Only remove empty ancestors within project-specific managed locations.
            parent = target.parent
            while parent != home and parent != home / '.local/share' and parent != home / '.local/bin' and parent != home / '.config/systemd/user':
                try:
                    parent.rmdir()
                except OSError:
                    break
                parent = parent.parent
        removed.append(rel)
    if not dry_run:
        write_atomic(manifest, {'schema': SCHEMA, 'files': new_files})
    for rel in removed:
        print('Removed obsolete tablet-shell file: ' + rel)
    for rel in preserved:
        print('Preserved modified former tablet-shell file: ' + rel)
    return removed, preserved


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--reuse-keyboard', action='store_true')
    parser.add_argument('--reuse-component', choices=sorted(SKIP_PREFIXES), action='append', default=[])
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error('run as desktop user, not root')
    if not (args.source / 'install.sh').is_file():
        parser.error('not a tablet-shell source tree')
    reconcile(args.source, args.home, args.dry_run, args.reuse_keyboard, args.reuse_component)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError) as e:
        sys.exit('Installed file cleanup stopped safely: ' + str(e))

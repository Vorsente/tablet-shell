const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.join(__dirname, '..');
const updater = path.join(root, 'update.sh');
const uid = process.getuid?.() === 0 ? 65534 : process.getuid?.();
const gid = process.getuid?.() === 0 ? 65534 : process.getgid?.();

function asUserDir(dir) {
    if (process.getuid?.() === 0) fs.chownSync(dir, uid, gid);
}
function fixture() {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tablet-update-test-'));
    asUserDir(tmp);
    const home = path.join(tmp, 'home');
    const source = path.join(tmp, 'source');
    fs.mkdirSync(home); fs.mkdirSync(source);
    asUserDir(home); asUserDir(source);
    const daemonDir = path.join(home, '.local/share/tabletd');
    fs.mkdirSync(daemonDir, {recursive:true});
    fs.writeFileSync(path.join(daemonDir, 'tabletd'), '#!/bin/sh\n', {mode:0o755});
    const confDir = path.join(home, '.config');
    fs.mkdirSync(confDir);
    fs.writeFileSync(path.join(confDir, 'kwinrc'), 'user-custom-settings=true\n');
    fs.writeFileSync(path.join(source, 'build.sh'), '#!/bin/bash\nset -eu\nprintf built > "$HOME/build-complete"\n');
    fs.writeFileSync(path.join(source, 'install.sh'), '#!/bin/bash\nset -eu\ntest -f "$HOME/build-complete"\nprintf "%s" "$*" > "$HOME/install-flags"\n');
    const code = path.join(source, 'src/tabletd');
    fs.mkdirSync(code, {recursive:true});
    fs.writeFileSync(path.join(code, 'tabletd.cpp'), '');
    if (process.getuid?.() === 0) {
        assert.equal(cp.spawnSync('chown', ['-R', `${uid}:${gid}`, home, source]).status, 0);
    }
    return {tmp, home, source};
}
function run(args, home) {
    return cp.spawnSync('bash', [updater, ...args], {
        encoding:'utf8', env:{...process.env, HOME:home}, uid, gid, timeout:30000
    });
}
function check(f, result) {
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const backupRoot = path.join(f.home, '.local/state/tablet-shell');
    const backupDirs = fs.readdirSync(backupRoot).filter(n => n.startsWith('backup-'));
    assert.equal(backupDirs.length, 1);
    assert.equal(fs.readFileSync(path.join(backupRoot, backupDirs[0], 'config/kwinrc'), 'utf8'), 'user-custom-settings=true\n');
    assert.equal(fs.readFileSync(path.join(f.home, '.config/kwinrc'), 'utf8'), 'user-custom-settings=true\n');
    assert.equal(fs.readFileSync(path.join(f.home, 'install-flags'), 'utf8'), '--update-only --no-themes --no-build --no-greeter-update --skip-failed-builds');
}

test('updater builds first, backs up settings, and calls non-destructive install mode', () => {
    const f = fixture();
    try { check(f, run(['--offline', '--from', f.source, '--no-greeter-update'], f.home)); }
    finally { fs.rmSync(f.tmp, {recursive:true,force:true}); }
});

test('updater safely accepts a project ZIP archive', () => {
    const f = fixture();
    try {
        const archive = path.join(f.tmp, 'new.zip');
        const py = 'import pathlib,sys,zipfile; p=pathlib.Path(sys.argv[1]); z=zipfile.ZipFile(sys.argv[2],"w"); [(z.write(f,"tablet-shell/"+f.relative_to(p).as_posix())) for f in p.rglob("*") if f.is_file()]; z.close()';
        assert.equal(cp.spawnSync('python3', ['-c', py, f.source, archive]).status, 0);
        check(f, run(['--from', archive, '--no-greeter-update'], f.home));
    } finally { fs.rmSync(f.tmp, {recursive:true,force:true}); }
});

test('updater rejects ZIP path traversal before extracting or installing', () => {
    const f = fixture();
    try {
        const archive = path.join(f.tmp, 'invalid.zip');
        assert.equal(cp.spawnSync('python3', ['-c', 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],"w"); z.writestr("../escape", "bad"); z.close()', archive]).status, 0);
        const result = run(['--from', archive], f.home);
        assert.notEqual(result.status, 0);
        assert.equal(fs.existsSync(path.join(f.home, 'install-flags')), false);
        assert.match(result.stderr, /Unsafe path/);
    } finally { fs.rmSync(f.tmp, {recursive:true,force:true}); }
});

test('installer has a dedicated update mode and all project user services disable logs', () => {
    const content = fs.readFileSync(path.join(root,'install.sh'),'utf8');
    assert.match(content, /--update-only/);
    assert.match(content, /if \[ -z "\$UPDATE_ONLY" \]; then\n# ---- 4\. themes/);
    for (const unit of fs.readdirSync(path.join(root,'systemd')).filter(n=>n.endsWith('.service'))) {
        const text = fs.readFileSync(path.join(root,'systemd',unit),'utf8');
        assert.match(text, /StandardOutput=null/);
        assert.match(text, /StandardError=null/);
    }
    for (const file of ['install.sh','update.sh','system/greeter.sh']) {
        assert.equal(cp.spawnSync('bash', ['-n', path.join(root,file)]).status, 0, file);
    }
});

test('updater excludes keyboard and greeter even when a mocked build requests a skip', () => {
    const f = fixture();
    try {
        const keyboardDir = path.join(f.home, '.local/share/tablet-keyboard');
        fs.mkdirSync(keyboardDir, {recursive:true});
        fs.writeFileSync(path.join(keyboardDir, 'tablet-keyboard'), 'existing keyboard', {mode:0o755});
        fs.writeFileSync(path.join(f.source, 'build.sh'), `#!/bin/bash
set -e
if [[ "\${TABLET_SHELL_SKIP_FAILED_BUILDS:-}" == 1 ]] && [[ -x "$HOME/.local/share/tablet-keyboard/tablet-keyboard" ]]; then
    mkdir -p build
    mkdir -p build/.skipped
    touch build/.skipped/tablet-keyboard
    touch build/.keyboard-reuse-installed
    touch "$HOME/build-complete"
else
    echo 'synthetic Qt compilation failure' >&2
    exit 1
fi
`);
        if (process.getuid?.() === 0) {
            assert.equal(cp.spawnSync('chown', ['-R', `${uid}:${gid}`, f.home, f.source]).status, 0);
        }
        const result = run(['--offline','--from',f.source,'--no-greeter-update'],f.home);
        assert.equal(result.status,0,result.stderr||result.stdout);
        assert.match(result.stdout, /Keyboard, lock screen and login screen were NOT updated/);
        assert.equal(fs.readFileSync(path.join(keyboardDir, 'tablet-keyboard'),'utf8'), 'existing keyboard');
        assert.equal(fs.readFileSync(path.join(f.home,'install-flags'),'utf8'), '--update-only --no-themes --no-build --no-greeter-update --skip-failed-builds');
        // Legacy keyboard option never overrides the explicit exclusion.
        const strict = run(['--offline','--from',f.source,'--require-keyboard','--no-greeter-update'],f.home);
        assert.equal(strict.status,0,strict.stderr || strict.stdout);
        assert.match(strict.stderr,/keyboard and lock screen are excluded/);
    } finally { fs.rmSync(f.tmp,{recursive:true,force:true}); }
});

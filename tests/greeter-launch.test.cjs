const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const source = fs.readFileSync(path.join(__dirname, '../system/greeter-launch.sh'), 'utf8');
test('greeter startup discards cage/libseat output and never creates a session log', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tablet-greeter-test-'));
    try {
        const marker = path.join(tmp, 'env.txt');
        fs.writeFileSync(path.join(tmp, 'mock-cage.sh'), `#!/bin/sh\nprintf 'libseat backend: %s\\n' "$LIBSEAT_BACKEND"\nprintf 'session: %s\\n' "$XDG_SESSION_TYPE" >&2\nprintf '%s|%s' "$LIBSEAT_BACKEND" "$XDG_SESSION_TYPE" > '${marker}'\n`);
        fs.chmodSync(path.join(tmp, 'mock-cage.sh'), 0o755);
        const updated = source.replace('exec /usr/bin/cage -s -m last -- /usr/local/bin/tablet-greeter', `exec '${tmp}/mock-cage.sh'`);
        const res = cp.spawnSync('sh', ['-c', updated], {encoding:'utf8'});
        assert.equal(res.status, 0);
        assert.equal(res.stdout, '');
        assert.equal(res.stderr, '');
        assert.equal(fs.readFileSync(marker, 'utf8'), 'logind|wayland');
        assert.equal(fs.existsSync(path.join(tmp, 'session.log')), false);
        assert.doesNotMatch(source, />.*session\.log/);
    } finally { fs.rmSync(tmp, {recursive:true, force:true}); }
});
test('installer retains explicit greeter opt-in and refresh without enabling another manager', () => {
    const install = fs.readFileSync(path.join(__dirname, '../install.sh'), 'utf8');
    assert.match(install, /--install-greeter/);
    assert.match(install, /--refresh/);
    assert.match(install, /tablet-shell-greeter/);
    const greeter = fs.readFileSync(path.join(__dirname, '../system/greeter.sh'), 'utf8');
    assert.match(greeter, /install -Dm755.*greeter-launch\.sh/);
    assert.match(greeter, /command = "\/usr\/local\/libexec\/tablet-shell-greeter"/);
    assert.ok(greeter.indexOf('if [ -n "$REFRESH" ]; then\n    say') < greeter.indexOf('systemctl enable greetd.service'));
    for(const f of ['install.sh', 'system/greeter.sh', 'system/greeter-launch.sh']) {
        assert.equal(cp.spawnSync('bash', ['-n', path.join(__dirname, '..', f)]).status, 0, f);
    }
});

test('greeter refresh preserves vt, custom settings and does not create extra command entries', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'tablet-greetd-conf-'));
    try {
        const file = path.join(tmp, 'config.toml');
        fs.writeFileSync(file, '[terminal]\nvt = 7\n\n[default_session]\nuser = "greeter"\ncommand = "sh -c \"tablet-greeter\""\n\n[my_config]\ntheme = "mine"\n');
        const script = path.join(__dirname, '../system/refresh-greetd.py');
        for (let i=0;i<2;i++) assert.equal(cp.spawnSync('python3', [script, file]).status, 0);
        const data = fs.readFileSync(file, 'utf8');
        assert.match(data, /vt = 7/);
        assert.match(data, /theme = "mine"/);
        assert.equal((data.match(/^command =/gm) || []).length, 1);
        assert.match(data, /command = "\/usr\/local\/libexec\/tablet-shell-greeter"/);
    } finally { fs.rmSync(tmp, {recursive:true,force:true}); }
});

test('archive entrypoints remain executable (including the installer itself)', () => {
    for (const file of ['install.sh','build.sh','update.sh','uninstall.sh','scripts/themes.sh','system/greeter.sh','system/greeter-launch.sh']) {
        const st = fs.statSync(path.join(__dirname, '..', file));
        assert.notEqual(st.mode & 0o111, 0, file);
    }
});

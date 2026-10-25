const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const cp = require('node:child_process');
const root = path.join(__dirname,'..');
const read = p => fs.readFileSync(path.join(root,p),'utf8');

test('pen ring exposes only note, screenshot, Krita, picker and recording in all styles', () => {
    const s = read('src/tabletshell/PenRing.qml');
    const ids = [...s.matchAll(/\{ id: "(note|shot|krita|color|record|zoom)", icon:/g)].map(m=>m[1]);
    assert.deepEqual(ids, ['note','shot','krita','color','record']);
    assert.doesNotMatch(s,/view_zoom_in|view_actual_size|zoomed|"Лупа"/);
    assert.match(s,/uiStyle\.pixel/);
    assert.match(s,/Kirigami\.Theme\.textColor/);
    assert.match(s,/color: area\.pressed \? win\.buttonPressedText : win\.buttonText/);
    assert.match(s,/isMask: true/);
    assert.match(s,/launch-krita/);
});

test('settings, control center, transitions, and installer all include coding mode', () => {
    const settings=read('src/tablet-settings/qml/Main.qml');
    for(const key of ['Режим кодинга','codingrc','powerSaver','reduceEffects','brightness','focus','LazyVim']) assert.ok(settings.includes(key), key);
    assert.match(read('src/tabletshell/control.qml'),/coding-mode/);
    const animation=read('src/tabletshell/ModeTransition.qml');
    assert.match(animation,/property real code: 0/);
    assert.match(animation,/if \(a\.code < b\.code\)/);
    assert.match(animation,/if \(a\.code > b\.code\)/);
    assert.match(read('src/tabletshell/main.cpp'),/codingfocus/);
    assert.match(read('install.sh'),/for f in bin\/\*/);
    assert.match(read('install.sh'),/scripts\/install-lazyvim\.sh/);
    assert.match(animation,/LazyVim/);
});

test('GitHub updater validates pinned SHA and checks for unwanted archive entries', () => {
    const s=read('bin/tablet-shell-github-update');
    for(const token of ['github.com','^[0-9a-f]{40}$','MAX_EXTRACTED','MAX_FILES','symlink','--no-greeter-update','--sha']) {
        if (token === 'symlink') assert.match(s,/0o120000/);
        else assert.ok(s.includes(token), token);
    }
    const python = cp.spawnSync('python3', ['-c', 'import ast,sys;ast.parse(open(sys.argv[1], encoding="utf-8").read())',path.join(root,'bin/tablet-shell-github-update')]);
    assert.equal(python.status, 0, python.stderr.toString());
});

test('coding-mode restores energy profile, brightness and previously enabled desktop effects after editor closes', () => {
    const temp=fs.mkdtempSync(path.join(os.tmpdir(),'tablet-coding-test-'));
    try {
        const uid=process.getuid?.()===0 ? 65534 : process.getuid?.();
        const gid=process.getuid?.()===0 ? 65534 : process.getgid?.();
        const home=path.join(temp,'home'), fake=path.join(temp,'fakebin');
        fs.mkdirSync(home); fs.mkdirSync(fake);
        const mock=(name,code)=>{const f=path.join(fake,name);fs.writeFileSync(f,'#!/bin/bash\n'+code,{mode:0o755});};
        mock('kreadconfig6', 'while (($#)); do if [[ "$1" == --default ]]; then shift; echo "$1"; exit 0; fi; shift; done\n');
        mock('kwriteconfig6','exit 0\n');
        mock('nvim', 'exit 0\n');
        mock('konsole', 'printf "editor:%s\\n" "$*" >> "$FAKE_EVENTS"\nexit 0\n');
        const cfg=path.join(home,'.config/tablet-shell-lazyvim'); fs.mkdirSync(cfg,{recursive:true});
        fs.writeFileSync(path.join(cfg,'init.lua'),'-- starter\n');
        mock('powerprofilesctl', 'if [[ "$1" == get ]]; then echo balanced; else echo "power:$2" >> "$FAKE_EVENTS"; fi\n');
        mock('kscreen-doctor', 'if [[ "$1" == -j ]]; then echo \'{"outputs":[{"name":"eDP-1","brightness":0.8}]}\'; else echo "brightness:$1" >> "$FAKE_EVENTS"; fi\n');
        mock('qdbus6', 'case "$*" in *isEffectLoaded*) echo true;; *unloadEffect*) echo "unload:${!#}" >> "$FAKE_EVENTS";; *loadEffect*) echo "load:${!#}" >> "$FAKE_EVENTS";; *CurrentApp*) echo konsole;; esac\n');
        const localbin=path.join(home,'.local/bin');fs.mkdirSync(localbin,{recursive:true});
        fs.writeFileSync(path.join(localbin,'tabletshell'),'#!/bin/bash\nsleep 30\n',{mode:0o755});
        fs.writeFileSync(path.join(temp,'events'),'');
        if(process.getuid?.()===0) assert.equal(cp.spawnSync('chown',['-R',`${uid}:${gid}`,temp]).status,0);
        const result=cp.spawnSync('bash',[path.join(root,'bin/coding-mode')],{uid,gid,encoding:'utf8',timeout:10000,
            env:{...process.env,HOME:home,XDG_CONFIG_HOME:path.join(home,'.config'),LANGUAGE:'en_US',XDG_RUNTIME_DIR:temp,FAKE_EVENTS:path.join(temp,'events'),PATH:fake+':'+process.env.PATH}});
        assert.equal(result.status,0,result.stderr);
        const events=fs.readFileSync(path.join(temp,'events'),'utf8');
        for(const expected of ['editor','power:power-saver','power:balanced','brightness:output.eDP-1.brightness.55','brightness:output.eDP-1.brightness.80','unload:blur','load:blur']) {
            assert.ok(events.includes(expected),`${expected}: ${events}`);
        }
        assert.ok(fs.existsSync(path.join(home,'Projects')));
        assert.ok(!fs.existsSync(path.join(home,'Projects/main.py')), 'must not create/edit a project file');
        assert.match(events, /NVIM_APPNAME=tablet-shell-lazyvim nvim \./);
        assert.match(events, /--fullscreen/);
    } finally {fs.rmSync(temp,{recursive:true,force:true});}
});

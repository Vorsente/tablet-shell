const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');

const root = path.join(__dirname, '..');
const script = path.join(root,'scripts/install-lazyvim.sh');
function fixture() {
    const temp=fs.mkdtempSync(path.join(os.tmpdir(),'tablet-lazyvim-'));
    const home=path.join(temp,'home'), fake=path.join(temp,'fake');
    fs.mkdirSync(home); fs.mkdirSync(fake);
    const uid=process.getuid?.()===0 ? 65534 : process.getuid?.();
    const gid=process.getuid?.()===0 ? 65534 : process.getgid?.();
    const stub=(name,body)=>fs.writeFileSync(path.join(fake,name),'#!/bin/bash\n'+body, {mode:0o755});
    stub('nvim', `if [[ "$1" == --version ]]; then printf 'NVIM v0.12.5\\nLuaJIT 2.1\\n'; else echo sync >> "$MOCK_EVENTS"; fi\n`);
    stub('git', `echo clone >> "$MOCK_EVENTS"\nif [[ "${'${MOCK_CLONE_FAIL:-}'}" == 1 ]]; then exit 128; fi\nmkdir -p -- "${'${!#}'}"; printf '%s\\n' '-- starter' > "${'${!#}'}/init.lua"\n`);
    stub('konsole','exit 0\n');
    const events=path.join(temp,'events');fs.writeFileSync(events,'');
    const nvimUser=path.join(home,'.config/nvim'); fs.mkdirSync(nvimUser,{recursive:true});
    fs.writeFileSync(path.join(nvimUser,'init.lua'),'-- original user config\n');
    if(process.getuid?.()===0) assert.equal(cp.spawnSync('chown',['-R',`${uid}:${gid}`,temp]).status,0);
    return {temp,home,fake,uid,gid,events};
}
function run(f, extra={}) {
    return cp.spawnSync('bash',[script], {encoding:'utf8',timeout:20000,uid:f.uid,gid:f.gid,
        env:{...process.env,HOME:f.home,XDG_CONFIG_HOME:path.join(f.home,'.config'),
            MOCK_EVENTS:f.events,PATH:f.fake+':'+process.env.PATH,...extra}});
}
test('installer provisions isolated LazyVim once and keeps default nvim config untouched',()=>{
    const f=fixture();
    try {
        const first=run(f); assert.equal(first.status,0,first.stderr);
        const second=run(f); assert.equal(second.status,0,second.stderr);
        const isolated=path.join(f.home,'.config/tablet-shell-lazyvim');
        assert.ok(fs.existsSync(path.join(isolated,'init.lua')));
        assert.ok(fs.existsSync(path.join(isolated,'.tablet-shell-plugins-ready')));
        assert.equal(fs.readFileSync(path.join(f.home,'.config/nvim/init.lua'),'utf8'),'-- original user config\n');
        assert.equal(fs.readFileSync(f.events,'utf8'),'clone\nsync\n');
        assert.ok(fs.existsSync(path.join(f.home,'.local/share/konsole/TabletShellCoding.profile')));
    } finally {fs.rmSync(f.temp,{recursive:true,force:true});}
});
test('failed official starter checkout is rolled back without changing default nvim',()=>{
    const f=fixture();
    try {
        const result=run(f,{MOCK_CLONE_FAIL:'1'}); assert.notEqual(result.status,0);
        assert.equal(fs.existsSync(path.join(f.home,'.config/tablet-shell-lazyvim')),false);
        assert.equal(fs.readdirSync(path.join(f.home,'.config')).filter(n=>n.startsWith('.tablet-shell-lazyvim.')).length,0);
        assert.equal(fs.readFileSync(path.join(f.home,'.config/nvim/init.lua'),'utf8'),'-- original user config\n');
    } finally {fs.rmSync(f.temp,{recursive:true,force:true});}
});
test('installer refuses to overwrite a preexisting conflicting lazyvim config',()=>{
    const f=fixture();
    try {
        const dir=path.join(f.home,'.config/tablet-shell-lazyvim');fs.mkdirSync(dir);
        fs.writeFileSync(path.join(dir,'user.lua'),'-- user file');
        if(process.getuid?.()===0) assert.equal(cp.spawnSync('chown',['-R',`${f.uid}:${f.gid}`,dir]).status,0);
        const result=run(f);assert.notEqual(result.status,0);
        assert.ok(fs.existsSync(path.join(dir,'user.lua')));
        assert.equal(fs.readFileSync(f.events,'utf8'),'');
    } finally {fs.rmSync(f.temp,{recursive:true,force:true});}
});

test('coding UI includes LazyVim scene, Konsole activation and package installation',()=>{
    const code=fs.readFileSync(path.join(root,'bin/coding-mode'),'utf8');
    const anim=fs.readFileSync(path.join(root,'src/tabletshell/ModeTransition.qml'),'utf8');
    const installer=fs.readFileSync(path.join(root,'install.sh'),'utf8');
    assert.match(code,/konsole --nofork --fullscreen/);
    assert.match(code,/NVIM_APPNAME=tablet-shell-lazyvim nvim \./);
    assert.match(code,/ModeTransition/);
    assert.match(code,/ModeReady/);
    assert.match(anim,/win\.code \* 8/);
    assert.match(anim,/LazyVim/);
    for(const pkg of ['neovim','konsole','ripgrep','fd','fzf','lazygit','tree-sitter-cli','ttf-jetbrains-mono-nerd','krita','power-profiles-daemon'])
        assert.ok(installer.includes(pkg),`missing ${pkg}`);
});

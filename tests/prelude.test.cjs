const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const cpp=fs.readFileSync(path.join(__dirname,'../src/tabletd/tabletd.cpp'),'utf8');
const block=cpp.slice(cpp.indexOf('const QString prelude ='),cpp.indexOf('.arg(tablet ?',cpp.indexOf('const QString prelude =')));
const prelude=Array.from(block.matchAll(/^\s*("(?:[^"\\]|\\.)*")/gm),m=>JSON.parse(m[1])).join('');
function run(raw) {
    const home="/home/name'quoted\\folder";
    let saved;
    const ctx=vm.createContext({panels:()=>[{widgets:()=>[{type:'org.kde.plasma.icontasks',readConfig:()=>raw}]}],
        ConfigFile:()=>({writeEntry:(k,v)=>saved=v})});
    vm.runInContext(prelude.replace('%1','true').replace('%2','1').replace('%3',JSON.stringify(home)),ctx);
    assert.equal(ctx.HOME,home);
    return {launchers:Array.from(ctx.LAUNCHERS),saved};
}
test('daemon prelude accepts a KConfig string launcher list and quoted home path',()=>{
    const r=run('applications:a.desktop,applications:b.desktop');
    assert.deepEqual(r.launchers,['applications:a.desktop','applications:b.desktop']);
});
test('daemon prelude accepts an array and preserves deliberately empty launchers',()=>{
    assert.deepEqual(run(['applications:a.desktop']).launchers,['applications:a.desktop']);
    assert.deepEqual(run([]).launchers,[]);
});

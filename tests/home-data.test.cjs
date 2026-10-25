const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const qml = fs.readFileSync(path.join(__dirname, '../shell/plasmoids/org.ipad.homescreen/contents/ui/HomeData.qml'), 'utf8');
// Exercise the actual JS function bodies, without a Qt dependency.
const functions = qml.slice(qml.indexOf('    function refreshToday()'), qml.indexOf('    onActiveChanged:'));
function fixture() {
    let now = 1e9;
    const calls = [];
    const data = {todayBusy:false, onlineBusy:false, batteryBusy:false, lastToday:0, lastOnline:0, lastBattery:0, lastWeatherCity:'', active:true};
    const home = {homeDir:'/test', weatherCity:'Moscow', runCommand(args, done) {calls.push({args, done});}};
    class Clock extends Date {constructor() {super(now);} static now() {return now;}}
    const c = vm.createContext({...data, home, Date:Clock}); c.data = c;
    vm.runInContext(functions, c);
    return {c, calls, advance: n => now += n, finish() {for (const x of calls.splice(0)) x.done(x.args[0] === 'sh' ? '72\nCharging' : '{}');}};
}
test('repeated refresh coalesces outstanding requests', () => {
    const f=fixture(); f.c.refresh(); f.c.refresh(); f.c.refresh();
    assert.equal(f.calls.length, 4); f.finish();
    assert.equal(f.c.battery,72); assert.equal(f.c.charging,true);
    f.c.refresh(); assert.equal(f.calls.length,0);
});
test('5 minute refresh does not spawn 30 minute helpers', () => {
    const f=fixture(); f.c.refresh(); f.finish(); f.advance(300000); f.c.refresh();
    assert.equal(f.calls.length,2); assert.ok(f.calls.some(x=>x.args[1]==='dashboard'));
    f.finish(); f.advance(1500000); f.c.refresh(); assert.equal(f.calls.length,4);
});
test('changed weather city bypasses the online cache', () => {
    const f=fixture(); f.c.refresh(); f.finish(); f.c.home.weatherCity='Berlin'; f.c.refresh();
    assert.equal(f.calls.length,1); assert.equal(f.calls[0].args.at(-1),'Berlin');
});
test('invalid responses release request guards and can be retried', () => {
    const f=fixture(); f.c.refresh();
    for(const x of f.calls.splice(0)) x.done('');
    assert.equal(f.c.battery,-1); assert.equal(f.c.onlineBusy,false); assert.equal(f.c.todayBusy,false);
    f.c.refresh(); assert.equal(f.calls.length,3);
});

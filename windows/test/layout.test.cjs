const {test}=require('node:test');
const assert=require('node:assert/strict');
const {notchBounds}=require('../src/layout.cjs');
const area={x:100,y:40,width:1920,height:1040};

test('left and right collapsed notches are vertical and flush with the screen edge',()=>{
  for(const edge of ['left','right']){
    const b=notchBounds(area,edge,3,false,false);
    assert.ok(b.height>b.width);
    assert.equal(edge==='left'?b.x:b.x+b.width,edge==='left'?area.x:area.x+area.width);
    assert.equal(b.y,area.y+Math.round((area.height-b.height)/2));
  }
});
test('top and bottom collapsed notches remain horizontal',()=>{
  for(const edge of ['top','bottom']){
    const b=notchBounds(area,edge,3,false,false);
    assert.ok(b.width>b.height);
    assert.equal(edge==='top'?b.y:b.y+b.height,edge==='top'?area.y:area.y+area.height);
  }
});
test('side panels expand inward and collapse back to a vertical rail',()=>{
  for(const edge of ['left','right']){
    const collapsed=notchBounds(area,edge,3,false,false);
    for(const settings of [false,true]){
      const b=notchBounds(area,edge,3,true,settings);
      assert.ok(b.width>collapsed.width);
      assert.equal(edge==='left'?b.x:b.x+b.width,edge==='left'?collapsed.x:collapsed.x+collapsed.width);
    }
    assert.deepEqual(notchBounds(area,edge,3,false,false),collapsed);
  }
});
test('large account lists and small work areas stay within screen bounds',()=>{
  const small={x:-800,y:20,width:320,height:400};
  for(const edge of ['left','right','top','bottom'])for(const expanded of [false,true])for(const settings of [false,true]){
    const b=notchBounds(small,edge,20,expanded,settings);
    assert.ok(b.x>=small.x&&b.y>=small.y);
    assert.ok(b.x+b.width<=small.x+small.width&&b.y+b.height<=small.y+small.height);
  }
});

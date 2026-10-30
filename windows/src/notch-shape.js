// Same canonical outline and transforms as macOS SideNotchShape.swift.
function notchPath(width,height,edge){
 if(!Number.isFinite(width)||!Number.isFinite(height)||width<=0||height<=0)return '';
 const side=edge==='left'||edge==='right';
 const depth=side?width:height,length=side?height:width;
 const wanted=Math.max(0,Math.min(78.8*44/117,depth/2));
 const curl=Math.max(0,Math.min(103*44/117,length/2,depth-wanted));
 const corner=Math.max(0,Math.min(wanted,(length-2*curl)/2));
 const number=value=>String(Math.round(value*1000)/1000);
 const point=(u,v)=>{
  const [x,y]=edge==='right'?[u,v]:edge==='left'?[depth-u,v]:edge==='bottom'?[v,u]:[v,depth-u];
  return `${number(x)} ${number(y)}`;
 };
 const arc=(radius,sweep,u,v)=>radius>0?`A ${number(radius)} ${number(radius)} 0 0 ${edge==='left'||edge==='bottom'?1-sweep:sweep} ${point(u,v)}`:`L ${point(u,v)}`;
 return [`M ${point(depth,0)}`,arc(curl,1,depth-curl,curl),`L ${point(corner,curl)}`,
  arc(corner,0,0,curl+corner),`L ${point(0,length-curl-corner)}`,
  arc(corner,0,corner,length-curl),`L ${point(depth-curl,length-curl)}`,
  arc(curl,1,depth,length),'Z'].join(' ');
}
if(typeof module!=='undefined')module.exports={notchPath};

const C=require('./codec.js');
const WORDS=[...Array(37)].map((_,i)=>({id:i+1}));
const wordById=id=>WORDS.find(w=>w.id===id);
function sim(bits,T,{fps=30,dur=40,noise=0.05,drop=0,offset=0,aeDepth=0,lag=0.04,low=0.1,high=0.9}){
  const s=[];let t=0,y=low;const ph=Math.random()*6;
  while(t<dur){const dt=1/fps+(Math.random()-0.5)*0.004;
    const k=Math.floor((t-offset)/T);const bit=t<offset?0:bits[((k%bits.length)+bits.length)%bits.length];
    const target=bit?high:low; y+= (target-y)*(1-Math.exp(-dt/lag));
    if(Math.random()>=drop){const g=1-aeDepth*(0.5+0.5*Math.sin(t*0.9+ph));
      s.push({t:100+t,v:Math.min(1,Math.max(0,y*g+(Math.random()-0.5)*2*noise))});}
    t+=dt;}
  return s;}
const cfgs=[{}, {drop:0.15,noise:0.1},{aeDepth:0.4},{aeDepth:0.5,lag:0.08,noise:0.08,offset:0.11},{low:0.25,high:0.7,noise:0.08}];
for(const cfg of cfgs){
  let wo=0,ww=0,wn=0;
  for(let i=0;i<40;i++){const id=1+Math.floor(Math.random()*37);
    const r=C.decodeWord(sim(C.frameFor(id),0.2,{...cfg,dur:14}),wordById); if(!r)wn++;else if(r.word.id===id)wo++;else ww++;}
  const texts=["HELP","NEED WATER","SOS 3F","たすけて","ココにいる","助けて"];
  let to=0,tw=0,tn=0;
  for(const tx of texts)for(let i=0;i<6;i++){
    const exp=C.symbolsToText(C.textToSymbols(tx));
    const r=C.decodeTextMsg(sim(C.textFrameBits(tx),0.15,{...cfg,dur:60}));
    if(!r)tn++;else if(r.text===exp)to++;else{tw++;}}
  console.log(JSON.stringify(cfg),'WORD ok',wo,'wrong',ww,'none',wn,'| TEXT ok',to,'wrong',tw,'none',tn);
}
let fp=0;for(let i=0;i<150;i++){const s=[];for(let t=0;t<60;t+=1/30)s.push({t,v:Math.random()});if(C.decodeTextMsg(s)||C.decodeWord(s,wordById))fp++;}
console.log('false positives (random noise):',fp);
// first-detect latency for HELP text
let lat=[];for(let i=0;i<5;i++){const full=sim(C.textFrameBits("HELP"),0.15,{dur:60});
  for(let end=10;end<=60;end+=1){const sub=full.filter(x=>x.t<100+end);const r=C.decodeTextMsg(sub);if(r){lat.push(end);break;}}}
console.log('HELP text detection latency (s):',lat.join(','));

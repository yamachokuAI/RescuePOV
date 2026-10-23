/* ===== LightComm codec v2 (JS reference; mirrored in Swift) ===== */
const PREAMBLE = [1,0,1,1];
const BIT_DURATION = 0.2;       // 定型語
const TEXT_BIT_DURATION = 0.15; // 自由文字
const FRAME_BITS = 16;
const TEXT_MAX_SYMBOLS = 24;
const DATA_POS = [3,5,6,7,9,10,11,12];

function hammingEncode(byte) {
  const code = new Array(13).fill(0);
  DATA_POS.forEach((pos, i) => { code[pos] = (byte >> (7 - i)) & 1; });
  for (const p of [1,2,4,8]) { let par = 0; for (let pos = 1; pos <= 12; pos++) if ((pos & p) && pos !== p) par ^= code[pos]; code[p] = par; }
  return code.slice(1, 13);
}
function hammingDecode(bits) {
  if (bits.length !== 12) return null;
  const code = [0, ...bits]; let s = 0;
  for (let pos = 1; pos <= 12; pos++) if (code[pos]) s ^= pos;
  let corrected = false;
  if (s !== 0) { if (s > 12) return null; code[s] ^= 1; corrected = true; }
  let v = 0; for (const p of DATA_POS) v = (v << 1) | code[p];
  return { value: v, corrected };
}

/* ---- 文字 <-> シンボル(byte) ---- */
function textToSymbols(str) {
  const out = [];
  for (const ch of Array.from(str)) {
    let c = ch.codePointAt(0), syms;
    if (c >= 0x30A1 && c <= 0x30F3) c -= 0x60;               // カタカナ→ひらがな
    if (c >= 0x20 && c <= 0x7E) syms = [c];
    else if (c >= 0x3041 && c <= 0x3093) syms = [0x80 + (c - 0x3041)];
    else if (c === 0x30FC) syms = [0xD3];
    else if (c === 0x3001) syms = [0xD4];
    else if (c === 0x3002) syms = [0xD5];
    else if (c === 0xFF01) syms = [0xD6];
    else if (c === 0xFF1F) syms = [0xD7];
    else if (c <= 0xFFFF) syms = [0xFF, c >> 8, c & 0xFF];
    else syms = [0x3F];
    if (out.length + syms.length > TEXT_MAX_SYMBOLS) break;
    out.push(...syms);
  }
  return out;
}
function symbolsToText(syms) {
  let s = "";
  for (let i = 0; i < syms.length; i++) {
    const b = syms[i];
    if (b >= 0x20 && b <= 0x7E) s += String.fromCharCode(b);
    else if (b >= 0x80 && b <= 0xD2) s += String.fromCharCode(0x3041 + (b - 0x80));
    else if (b === 0xD3) s += "ー"; else if (b === 0xD4) s += "、"; else if (b === 0xD5) s += "。";
    else if (b === 0xD6) s += "！"; else if (b === 0xD7) s += "？";
    else if (b === 0xFF && i + 2 < syms.length + 0) { s += String.fromCharCode((syms[i+1] << 8) | syms[i+2]); i += 2; }
    else s += "?";
  }
  return s;
}
function textChecksum(n, syms) { let c = n ^ 0x5A; for (const b of syms) c ^= b; return c & 0xFF; }
function textFrameBits(str) {
  const syms = textToSymbols(str);
  const n = syms.length;
  let bits = [...PREAMBLE, ...hammingEncode(0x80 | n)];
  for (const b of syms) bits.push(...hammingEncode(b));
  bits.push(...hammingEncode(textChecksum(n, syms)));
  return bits;
}
function frameFor(id) { return [...PREAMBLE, ...hammingEncode(id)]; }

/* ---- ビット抽出（局所しきい値つき） ---- */
function sampleBits(samples, T, phase, globalThr, globalContrast) {
  const first = samples[0].t, last = samples[samples.length - 1].t;
  const start = first + T * phase / 8;
  const bits = [];
  let idx = 0, k = 0, prev = 0, wlo = 0, whi = 0;
  const half = 1.0; // 局所窓 ±1.0s
  for (;;) {
    const center = start + (k + 0.5) * T;
    const lo = center - T * 0.25, hi = center + T * 0.25;
    if (hi > last) break;
    while (idx < samples.length && samples[idx].t < lo) idx++;
    let j = idx, sum = 0, n = 0;
    while (j < samples.length && samples[j].t <= hi) { sum += samples[j].v; n++; j++; }
    if (n > 0) {
      // 局所min/max
      while (wlo < samples.length && samples[wlo].t < center - half) wlo++;
      if (whi < wlo) whi = wlo;
      while (whi < samples.length && samples[whi].t <= center + half) whi++;
      let mn = 1e9, mx = -1e9;
      for (let q = wlo; q < whi; q++) { const v = samples[q].v; if (v < mn) mn = v; if (v > mx) mx = v; }
      const localOK = (mx - mn) >= Math.max(0.08, 0.4 * globalContrast);
      const thr = localOK ? (mn + mx) / 2 : globalThr;
      prev = (sum / n) > thr ? 1 : 0;
    }
    bits.push(prev); k++;
  }
  return bits;
}
function stats(samples) {
  const sv = samples.map(s => s.v).sort((a,b) => a - b);
  const p10 = sv[Math.floor((sv.length - 1) * 0.10)], p90 = sv[Math.floor((sv.length - 1) * 0.90)];
  return { contrast: p90 - p10, thr: (p10 + p90) / 2 };
}
const preDist = (bits, i) => { let d = 0; for (let b = 0; b < 4; b++) if (bits[i + b] !== PREAMBLE[b]) d++; return d; };

/* ---- 定型語デコード ---- */
function decodeWord(samples, wordById) {
  if (samples.length <= 40) return null;
  const T = BIT_DURATION, first = samples[0], last = samples[samples.length - 1];
  if (last.t - first.t < T * FRAME_BITS * 2) return null;
  const st = stats(samples);
  if (st.contrast < 0.10) return null;
  let best = null, bestScore = 0;
  for (let phase = 0; phase < 8; phase++) {
    const bits = sampleBits(samples, T, phase, st.thr, st.contrast);
    const count = bits.length;
    if (count < FRAME_BITS * 2) continue;
    const starts = new Set();
    for (let i = 0; i <= count - FRAME_BITS; i++) if (preDist(bits, i) <= 1) starts.add(i);
    for (const s of [...starts].sort((a,b) => a - b)) {
      if (starts.has(s - FRAME_BITS)) continue;
      const chain = [s]; let next = s + FRAME_BITS;
      while (starts.has(next)) { chain.push(next); next += FRAME_BITS; }
      if (chain.length < 2) continue;
      const votes = new Array(12).fill(0);
      for (const c of chain) for (let b = 0; b < 12; b++) votes[b] += bits[c + 4 + b] ? 1 : -1;
      const dec = hammingDecode(votes.map(v => v > 0 ? 1 : 0));
      if (!dec) continue;
      const w = wordById(dec.value); if (!w) continue;
      const agreement = votes.reduce((a, v) => a + Math.abs(v), 0) / (12 * chain.length);
      const exactPre = chain.every(c => preDist(bits, c) === 0);
      if (chain.length === 2) { if (agreement < 1.0 || dec.corrected || !exactPre) continue; }
      else if (agreement < 0.8) continue;
      const score = chain.length - (dec.corrected ? 0.5 : 0) + agreement + (exactPre ? 0.75 : 0);
      if (score > bestScore) { bestScore = score; best = { word: w, repeats: chain.length, corrected: dec.corrected, quality: Math.min(1, agreement) }; }
    }
  }
  return best;
}

/* ---- 自由文字デコード ---- */
function decodeTextMsg(samples) {
  if (samples.length <= 60) return null;
  const T = TEXT_BIT_DURATION, first = samples[0], last = samples[samples.length - 1];
  const st = stats(samples);
  if (st.contrast < 0.10) return null;
  let best = null, bestScore = 0;
  for (let phase = 0; phase < 8; phase++) {
    const bits = sampleBits(samples, T, phase, st.thr, st.contrast);
    const count = bits.length;
    if (count < 4 + 12 * 3) continue;
    for (let i = 0; i + 16 <= count; i++) {
      if (preDist(bits, i) > 1) continue;
      const h = hammingDecode(bits.slice(i + 4, i + 16));
      if (!h || h.value < 0x80) continue;
      const n = h.value & 0x7F;
      if (n < 1 || n > TEXT_MAX_SYMBOLS) continue;
      const P = 4 + 12 * (n + 2);
      if (i + P > count) continue;
      const chain = [i];
      for (let j = i + P; j + P <= count && preDist(bits, j) <= 1; j += P) chain.push(j);
      const body = P - 4, votes = new Array(body).fill(0);
      for (const c of chain) for (let b = 0; b < body; b++) votes[b] += bits[c + 4 + b] ? 1 : -1;
      const voted = votes.map(v => v > 0 ? 1 : 0);
      const agreement = votes.reduce((a, v) => a + Math.abs(v), 0) / (body * chain.length);
      const exactPre = chain.every(c => preDist(bits, c) === 0);
      let corrected = 0; const syms = []; let ok = true;
      for (let s = 0; s < n + 2; s++) {
        const d = hammingDecode(voted.slice(s * 12, s * 12 + 12));
        if (!d) { ok = false; break; }
        if (d.corrected) corrected++;
        syms.push(d.value);
      }
      if (!ok) continue;
      const payload = syms.slice(1, n + 1), chk = syms[n + 1];
      if (syms[0] !== (0x80 | n)) continue;
      if (chk !== textChecksum(n, payload)) continue;
      if (chain.length === 1) { if (corrected > 0 || !exactPre) continue; }
      else if (agreement < 0.85) continue;
      const score = chain.length * 2 + n * 0.1 - corrected * 0.3 + (exactPre ? 0.5 : 0);
      if (score > bestScore) { bestScore = score; best = { text: symbolsToText(payload), repeats: chain.length, corrected, quality: Math.min(1, agreement) }; }
    }
  }
  return best;
}
if (typeof module !== 'undefined') module.exports = { frameFor, textFrameBits, decodeWord, decodeTextMsg, textToSymbols, symbolsToText, hammingEncode, hammingDecode, BIT_DURATION, TEXT_BIT_DURATION };

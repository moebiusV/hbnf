// time_xml.js TOOL FILE: parse FILE with a Node XML library and print
// "ok BYTES MS RSS_KIB ELEMENTS ATTRIBUTES TEXT" (see bench/libs/timer.h).  TOOL:
//   fxp   fast-xml-parser: the document as a tree of plain objects (the walk that counts comes after the clock)
//   sax   sax (strict mode): events only; the handlers count elements, attributes and text as they come
const fs = require('fs');
const tool = process.argv[2];
const data = fs.readFileSync(process.argv[3], 'utf8');
const nb = (s) => Buffer.byteLength(s.replace(/[ \t\r\n]/g, ''));
let el = 0, at = 0, tx = 0, tree = null, ms;
if (tool === 'fxp') {
  const { XMLParser } = require('/opt/js-xml/node_modules/fast-xml-parser');
  const p = new XMLParser({ htmlEntities: true /* also turns on &#N; and &#xN;, which it leaves alone otherwise */, ignoreAttributes: false, attributeNamePrefix: '@_', parseTagValue: false,
                            parseAttributeValue: false, ignoreDeclaration: true, ignorePiTags: true });
  const t0 = process.hrtime.bigint();
  tree = p.parse(data);
  ms = Number(process.hrtime.bigint() - t0) / 1e6;
  const walk = (o) => {
    if (typeof o === 'string') { tx += nb(o); return; }
    if (o === null || typeof o !== 'object') return;
    for (const k of Object.keys(o)) {
      const v = o[k];
      if (k === '#text') tx += nb(String(v));
      else if (k.startsWith('@_')) { if (!k.startsWith('@_xmlns')) at++; }
      else if (Array.isArray(v)) for (const x of v) { el++; walk(x); }
      else { el++; walk(v); }
    }
  };
  walk(tree);
} else if (tool === 'sax') {
  const sax = require('/opt/js-xml/node_modules/sax');
  const p = sax.parser(true, {});
  p.onopentag = (n) => { el++; for (const k in n.attributes) if (!k.startsWith('xmlns')) at++; };
  p.ontext = (t) => { tx += nb(t); };
  p.oncdata = (t) => { tx += nb(t); };
  const t0 = process.hrtime.bigint();
  p.write(data).close();
  ms = Number(process.hrtime.bigint() - t0) / 1e6;
} else process.exit(2);
console.log(`ok ${Buffer.byteLength(data)} ${ms.toFixed(2)} ${Math.round(process.resourceUsage().maxRSS)} ${el} ${at} ${tx}`);

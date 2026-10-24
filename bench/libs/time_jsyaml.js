// time_jsyaml.js FILE: parse FILE with js-yaml and print "ok BYTES MS RSS_KIB".
const fs = require('fs');
const yaml = require('/opt/js/node_modules/js-yaml');
const data = fs.readFileSync(process.argv[2], 'utf8');
const t0 = process.hrtime.bigint();
yaml.load(data);
const ms = Number(process.hrtime.bigint() - t0) / 1e6;
console.log(`ok ${Buffer.byteLength(data)} ${ms.toFixed(2)} ${Math.round(process.resourceUsage().maxRSS)}`);

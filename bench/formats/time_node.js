// time_node.js FILE: JSON.parse the file and print "ok BYTES MS RSS_KIB".
const fs = require('fs');
const data = fs.readFileSync(process.argv[2], 'utf8');
const t0 = process.hrtime.bigint();
JSON.parse(data);
const ms = Number(process.hrtime.bigint() - t0) / 1e6;
console.log('ok ' + Buffer.byteLength(data) + ' ' + ms.toFixed(2) + ' ' + process.resourceUsage().maxRSS);

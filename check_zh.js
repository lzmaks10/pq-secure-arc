const fs = require('fs');
const c = fs.readFileSync('ui/index.html', 'utf8');
const r = /[\u4e00-\u9fff]/;
const lines = c.split('\n');
let f = 0;
for (let i = 0; i < lines.length; i++) {
  if (r.test(lines[i])) {
    console.log((i+1) + ': ' + lines[i].trim().substring(0, 100));
    f++;
  }
}
console.log(f === 0 ? '\n✅ NO CHINESE REMAINING!' : '\n❌ FOUND: ' + f + ' lines with Chinese');
console.log(c.includes('lang="en"') ? '✅ lang="en" OK' : '❌ lang MISSING');
// Check line count
console.log('Total lines: ' + lines.length);

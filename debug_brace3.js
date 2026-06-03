const fs = require('fs');
const html = fs.readFileSync('ui/index.html', 'utf8');
const match = html.match(/<script>([\s\S]*?)<\/script>/);
const script = match[1];

let braceDepth = 0;
let inString = false;
let stringChar = '';
let inLineComment = false;
let inBlockComment = false;

const startIdx = 68200;
for (let i = startIdx; i < Math.min(script.length, 100000); i++) {
  const ch = script[i];
  const prev = i > 0 ? script[i-1] : '';
  
  if (inBlockComment) { if (ch === '/' && prev === '*') inBlockComment = false; continue; }
  if (inLineComment) { if (ch === '\n') inLineComment = false; continue; }
  if (prev === '/' && ch === '/') { inLineComment = true; continue; }
  if (prev === '/' && ch === '*') { inBlockComment = true; continue; }
  
  if (inString) {
    if (ch === stringChar && prev !== '\\') inString = false;
    continue;
  }
  if (ch === '"' || ch === "'") { inString = true; stringChar = ch; continue; }
  
  if (ch === '{') {
    braceDepth++;
  }
  else if (ch === '}') {
    braceDepth--;
  }
  
  // Log depth changes near the connectWallet area
  if (braceDepth === 0 || braceDepth < 0) {
    // Check if we found the closing  
    if (i > startIdx + 10) {
      const lineNum = (script.substring(0, i).match(/\n/g) || []).length + 1;
      const ctx = script.substring(Math.max(0,i-10), Math.min(script.length, i+20)).replace(/\n/g, '\\n');
      console.log('Depth', braceDepth, 'at char', i, 'line', lineNum, 'ctx:', ctx);
    }
    if (braceDepth < 0) break;
  }
}

console.log('Final depth:', braceDepth);

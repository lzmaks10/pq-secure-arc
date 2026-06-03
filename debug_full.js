const fs = require('fs');
const html = fs.readFileSync('ui/index.html', 'utf8');
const match = html.match(/<script>([\s\S]*?)<\/script>/);
const script = match[1];

let braceDepth = 0;
let inString = false;
let stringChar = '';
let inLineComment = false;
let inBlockComment = false;

// Trace the ENTIRE script from start
let prevDepth = 0;
for (let i = 0; i < script.length; i++) {
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
  
  // Log every time depth returns to 0
  if (prevDepth !== 1 && braceDepth === 0 && prevDepth !== braceDepth) {
    const lineNum = (script.substring(0, i).match(/\n/g) || []).length + 1;
    const ctx = script.substring(Math.max(0,i-15), Math.min(script.length, i+15)).replace(/\n/g, '\\n');
    console.log('Depth 0 at char', i, 'line', lineNum, 'ctx:', ctx);
  }
  if (braceDepth === -1) {
    const lineNum = (script.substring(0, i).match(/\n/g) || []).length + 1;
    const ctx = script.substring(Math.max(0,i-15), Math.min(script.length, i+15)).replace(/\n/g, '\\n');
    console.log('NEGATIVE at char', i, 'line', lineNum, 'ctx:', ctx);
    break;
  }
  prevDepth = braceDepth;
}

console.log('Final brace depth:', braceDepth);

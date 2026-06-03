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
  
  // Skip template literals inside strings is already handled
  
  if (ch === '{') {
    braceDepth++;
  }
  else if (ch === '}') {
    braceDepth--;
    if (braceDepth < 0) {
      const lineNum = (script.substring(0, i).match(/\n/g) || []).length + 1;
      console.log('NEGATIVE depth', braceDepth, 'at char', i, 'line', lineNum);
      break;
    }
  }
}

console.log('Final brace depth:', braceDepth);

// Now find all the lines where depth transitions
// Let me find where depth increases but never decreases back

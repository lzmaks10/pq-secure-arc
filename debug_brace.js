const fs = require('fs');
const html = fs.readFileSync('ui/index.html', 'utf8');
const match = html.match(/<script>([\s\S]*?)<\/script>/);
if (!match) { console.log('No script found'); process.exit(1); }
const script = match[1];

let braceDepth = 0;
let inString = false;
let stringChar = '';
let inTemplate = false;
let inLineComment = false;
let inBlockComment = false;

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
  if (inTemplate) {
    if (ch === '`' && prev !== '\\') inTemplate = false;
    continue;
  }
  
  if (ch === '"' || ch === "'") { inString = true; stringChar = ch; continue; }
  if (ch === '`') { inTemplate = true; continue; }
  
  if (ch === '{') {
    braceDepth++;
    if (braceDepth === 1) {
      const lineNum = (script.substring(0, i).match(/\n/g) || []).length + 1;
      const context = script.substring(Math.max(0,i-40), Math.min(script.length, i+40));
      console.log('First top-level brace at char', i, 'line', lineNum);
      console.log('Context:', context.replace(/\n/g, '\\n'));
      console.log('');
    }
  }
  else if (ch === '}') {
    braceDepth--;
    if (braceDepth === 0) {
      const lineNum = (script.substring(0, i).match(/\n/g) || []).length + 1;
      console.log('Returned to depth 0 at char', i, 'line', lineNum);
    }
  }
}

console.log('\nFinal brace depth:', braceDepth);

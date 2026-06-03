// Debug script to test global function registration
// Run with: node debug_test.js
const fs = require('fs');
const html = fs.readFileSync('ui/index.html', 'utf8');
const match = html.match(/<script>([\s\S]*?)<\/script>/);
if (!match) { console.log('No script found'); process.exit(1); }
const script = match[1];

// Check for any wrapping that would prevent global scope
// Look for function declarations inside blocks
const lines = script.split('\n');
let inBlock = false;
let braceDepth = 0;
let bracketCount = { '{': 0, '}': 0 };
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
    // Also skip template literals inside strings
    continue;
  }
  
  if (ch === '"' || ch === "'") { inString = true; stringChar = ch; continue; }
  if (ch === '`') { inTemplate = !inTemplate; continue; }
  
  if (ch === '{') bracketCount['{']++;
  else if (ch === '}') bracketCount['}']++;
}

console.log('Opening braces:', bracketCount['{']);
console.log('Closing braces:', bracketCount['}']);
console.log('Net:', bracketCount['{'] - bracketCount['}']);

// Count function declarations
const funcs = script.match(/function\s+\w+/g);
console.log('\nFunction declarations:', funcs ? funcs.length : 0);
funcs?.forEach(f => console.log('  ' + f));

// Check if functions are at the global script level (not inside any block)
// by looking at what comes before the first function
const firstFuncIdx = script.indexOf('function ');
const beforeFirst = script.substring(0, firstFuncIdx);
// Only look at meaningful code, not comments
const codeBeforeFirst = beforeFirst.replace(/\/\/.*/g, '').replace(/\/\*[\s\S]*?\*\//g, '').trim();

// If there's a stray '{' before the first function that never closes, it would scope all functions
console.log('\nFirst function declaration starts at char', firstFuncIdx);

// Let me also check for the bytecode strings which contain many braces
// that might confuse parsers
const bytecodeDecls = script.match(/const \w+_BYTECODE\s*=\s*'[^']+'/g);
console.log('\nBytecode declarations:', bytecodeDecls ? bytecodeDecls.length : 0);
bytecodeDecls?.forEach(b => console.log('  length:', b.length));

// Find any function that's NOT wrapped by DOMContentLoaded or async IIFE
console.log('\nSearching for top-level wrapping...');

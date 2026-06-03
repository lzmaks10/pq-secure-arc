const fs = require('fs');
const html = fs.readFileSync('ui/index.html', 'utf8');
const match = html.match(/<script>([\s\S]*?)<\/script>/);
const script = match[1];
const lines = script.split('\n');

// Print lines 14-16 character by character with state tracking
for (let lineIdx = 13; lineIdx < 16; lineIdx++) {
  const line = lines[lineIdx];
  console.log('\nLine', lineIdx + 1, '(' + line.length + ' chars):');
  console.log('First 50 chars:', line.substring(0, 50));
  console.log('Last 10 chars:', JSON.stringify(line.substring(line.length - 10)));
}

// Now track the string state through lines 14-16
let inString = false;
let stringChar = '';
let pos = 0;
for (let lineIdx = 0; lineIdx < 17; lineIdx++) {
  const line = lines[lineIdx];
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inString) {
      if (ch === stringChar) {
        inString = false;
        if (lineIdx >= 13 && lineIdx <= 16) {
          console.log('  String END at line', lineIdx+1, 'char', i, 'pos', pos+i);
        }
      }
    } else {
      if (ch === "'" || ch === '"') {
        inString = true;
        stringChar = ch;
        if (lineIdx >= 13 && lineIdx <= 16) {
          console.log('  String START at line', lineIdx+1, 'char', i, 'pos', pos+i, 'with', ch);
        }
      }
    }
  }
  pos += line.length + 1;
}

console.log('\nFinal state: inString=' + inString + ' char=' + stringChar);

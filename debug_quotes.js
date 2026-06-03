const fs = require('fs');
const html = fs.readFileSync('ui/index.html', 'utf8');
const match = html.match(/<script>([\s\S]*?)<\/script>/);
const script = match[1];

const lines = script.split('\n');
let pos = 0;
for (let i = 0; i < lines.length && i < 20; i++) {
  const line = lines[i];
  const quoteCount = (line.match(/'/g) || []).length;
  const length = line.length;
  console.log('Line', i+1, 'pos', pos, 'len', length, 'quotes:', quoteCount, '...', line.substring(0, 60));

  // Check for unescaped single quotes inside a single-quoted string
  if (quoteCount > 2 && line.includes('_BYTECODE')) {
    const idx1 = line.indexOf("'");
    const idx2 = line.indexOf("'", idx1 + 1);
    const idx3 = line.indexOf("'", idx2 + 1);
    if (idx3 > 0) {
      console.log('  Extra quote at pos', idx3, 'char around:', line.substring(Math.max(0,idx3-3), idx3+3));
    }
  }
  pos += line.length + 1;
}

const fs = require('fs');
let html = fs.readFileSync('ui/index.html', 'utf8');

// Find the connectWallet function start
const startMarker = 'async function connectWallet() {';
const startIdx = html.indexOf(startMarker);
if (startIdx === -1) { console.log('START NOT FOUND'); process.exit(1); }

// Find the closing brace at the right indentation level
let depth = 0;
let endIdx = startIdx;
let inString = false;
let stringChar = null;
let inTemplate = false;
let inSingleLineComment = false;
let inMultiLineComment = false;

for (let i = startIdx; i < html.length; i++) {
  const ch = html[i];
  const prev = i > 0 ? html[i-1] : '';
  
  // Track string literals
  if (!inSingleLineComment && !inMultiLineComment) {
    if (inTemplate) {
      if (ch === '`' && prev !== '\\') { inTemplate = false; continue; }
      continue;
    }
    if (inString) {
      if (ch === stringChar && prev !== '\\') { inString = false; }
      continue;
    }
    if (ch === '"' || ch === "'") { inString = true; stringChar = ch; continue; }
    if (ch === '`') { inTemplate = true; continue; }
    if (ch === '/' && html[i+1] === '/') { inSingleLineComment = true; continue; }
    if (ch === '/' && html[i+1] === '*') { inMultiLineComment = true; i++; continue; }
  } else if (inSingleLineComment && ch === '\n') { inSingleLineComment = false; }
  else if (inMultiLineComment && ch === '*' && html[i+1] === '/') { inMultiLineComment = false; i++; }
  
  if (!inString && !inTemplate && !inSingleLineComment && !inMultiLineComment) {
    if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) { endIdx = i + 1; break; }
    }
  }
}

if (depth !== 0) { console.log('UNMATCHED BRACES'); process.exit(1); }

const oldFunc = html.substring(startIdx, endIdx);
console.log('Found function:', oldFunc.substring(0, 80) + '...');
console.log('Length:', oldFunc.length);
console.log('Ends with:', oldFunc.substring(oldFunc.length-20));

const newFunc = `async function connectWallet() {
  try {
    if (!window.ethereum) { toast('Please install MetaMask! 🦊', 'error'); return; }
    // Switch to Arc Testnet FIRST — prompt appears immediately
    try {
      await window.ethereum.request({
        method: 'wallet_switchEthereumChain',
        params: [{ chainId: '0x4CEF52' }],
      });
    } catch(e) {
      if (e.code === 4902) {
        await window.ethereum.request({
          method: 'wallet_addEthereumChain',
          params: [{ chainId: '0x4CEF52', chainName: 'Arc Testnet', rpcUrls: ['https://rpc.testnet.arc.network'], nativeCurrency: { name: 'USDC', symbol: 'USDC', decimals: 18 } }],
        });
      }
    }
    provider = new ethers.providers.Web3Provider(window.ethereum);
    await provider.send('eth_requestAccounts', []);
    signer = provider.getSigner();
    userAddr = await signer.getAddress();
    const net = await provider.getNetwork();

    document.getElementById('connectBtn').textContent = \`\u2705 \${userAddr.slice(0,6)}...\${userAddr.slice(-4)}\`;
    document.getElementById('connectBtn').onclick = null;
    document.getElementById('statusBar').classList.remove('hidden');
    document.getElementById('walletAddr').textContent = userAddr;

    document.getElementById('chainBadge').innerHTML = net.chainId === 5042002 ? '\ud83d\udfe2 Arc Testnet' : '\u26a0\ufe0f Wrong chain';
    document.getElementById('liveStatus').innerHTML = '\ud83d\udfe2 Connected';
    document.getElementById('btnGenStealthKey').disabled = false;
    document.getElementById('btnScanInbox').disabled = false;
    privacyRefreshStatus();
    document.getElementById('liveStatus').className = 'text-2xl font-bold mt-1 text-emerald-400';
    toast('\u2705 Wallet connected', 'success');
    setTimeout(refreshAll, 500);
  } catch(e) {
    toast('Connection failed: '+e.message, 'error');
  }
}`;

html = html.substring(0, startIdx) + newFunc + html.substring(endIdx);
fs.writeFileSync('ui/index.html', html, 'utf8');
console.log('✅ connectWallet updated — chain switch now BEFORE account request');

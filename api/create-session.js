const crypto = require('crypto');

const RECIPIENT_WALLET = 'FN74faeP6NUnUqtFwohKKQzbWLbbWjJf3Dw5LGPe1gDt';
const PRICE_USD = 125;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

module.exports = async function handler(req, res) {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, corsHeaders);
    return res.end();
  }

  Object.entries(corsHeaders).forEach(([k, v]) => res.setHeader(k, v));

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { ref } = req.body || {};
    const sessionId = crypto.randomUUID();
    const referenceKey = crypto.randomBytes(32).toString('hex');

    // Fetch SOL price
    const priceRes = await fetch(
      'https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd'
    );
    const priceData = await priceRes.json();
    const solPrice = priceData.solana.usd;
    const solAmount = Math.round((PRICE_USD / solPrice) * 10000) / 10000;

    // Try to store in KV
    try {
      const { kv } = require('@vercel/kv');
      await kv.set(`session:${sessionId}`, {
        ref: ref || null,
        referenceKey,
        solAmount,
        createdAt: Date.now(),
        status: 'pending',
      });
    } catch (kvErr) {
      console.warn('KV not configured, continuing without persistence:', kvErr.message);
    }

    return res.status(200).json({
      sessionId,
      referenceKey,
      solAmount,
      recipientWallet: RECIPIENT_WALLET,
    });
  } catch (err) {
    console.error('create-session error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
};

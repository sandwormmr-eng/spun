const INSTALL_CMD = 'curl -fsSL https://raw.githubusercontent.com/sandwormmr-eng/spun/main/install.sh | bash';

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

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { sessionId } = req.query;
  if (!sessionId) {
    return res.status(400).json({ error: 'Missing sessionId' });
  }

  try {
    let session = null;
    let kv = null;

    try {
      kv = require('@vercel/kv').kv;
      session = await kv.get(`session:${sessionId}`);
    } catch (kvErr) {
      console.warn('KV not configured:', kvErr.message);
    }

    if (!session) {
      return res.status(404).json({ error: 'Session not found' });
    }

    // Already confirmed
    if (session.status === 'confirmed') {
      return res.status(200).json({ confirmed: true, installCmd: INSTALL_CMD });
    }

    // Check Solana for the reference key
    const rpcRes = await fetch('https://api.mainnet-beta.solana.com', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'getSignaturesForAddress',
        params: [session.referenceKey, { limit: 1 }],
      }),
    });

    const rpcData = await rpcRes.json();

    if (rpcData.result && rpcData.result.length > 0) {
      // Payment found — mark confirmed
      if (kv) {
        try {
          session.status = 'confirmed';
          await kv.set(`session:${sessionId}`, session);

          // Increment referral conversions if applicable
          if (session.ref) {
            try {
              const refData = await kv.get(`ref:${session.ref}`);
              if (refData) {
                refData.conversions = (refData.conversions || 0) + 1;
                await kv.set(`ref:${session.ref}`, refData);
              }
            } catch (refErr) {
              console.warn('Failed to update referral:', refErr.message);
            }
          }
        } catch (kvErr) {
          console.warn('Failed to update session in KV:', kvErr.message);
        }
      }

      return res.status(200).json({ confirmed: true, installCmd: INSTALL_CMD });
    }

    return res.status(200).json({ confirmed: false });
  } catch (err) {
    console.error('check-payment error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
};

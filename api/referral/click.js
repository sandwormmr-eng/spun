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
    const { code } = req.body || {};

    if (!code) {
      return res.status(400).json({ error: 'Missing code' });
    }

    try {
      const { kv } = require('@vercel/kv');
      const refData = await kv.get(`ref:${code}`);
      if (refData) {
        refData.clicks = (refData.clicks || 0) + 1;
        await kv.set(`ref:${code}`, refData);
      }
    } catch (kvErr) {
      console.warn('KV not configured:', kvErr.message);
    }

    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('referral/click error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
};

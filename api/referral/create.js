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
    const { secret, code, name, telegramHandle } = req.body || {};

    if (!secret || secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    if (!code) {
      return res.status(400).json({ error: 'Missing referral code' });
    }

    const referral = {
      code,
      name: name || '',
      telegramHandle: telegramHandle || '',
      createdAt: Date.now(),
      clicks: 0,
      conversions: 0,
    };

    try {
      const { kv } = require('@vercel/kv');
      await kv.set(`ref:${code}`, referral);
    } catch (kvErr) {
      console.warn('KV not configured:', kvErr.message);
      return res.status(500).json({ error: 'KV store not available' });
    }

    return res.status(200).json(referral);
  } catch (err) {
    console.error('referral/create error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
};

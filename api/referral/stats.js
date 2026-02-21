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

  try {
    const { code, secret } = req.query;

    if (!secret || secret !== process.env.ADMIN_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    if (!code) {
      return res.status(400).json({ error: 'Missing code' });
    }

    let refData = null;
    try {
      const { kv } = require('@vercel/kv');
      refData = await kv.get(`ref:${code}`);
    } catch (kvErr) {
      console.warn('KV not configured:', kvErr.message);
      return res.status(500).json({ error: 'KV store not available' });
    }

    if (!refData) {
      return res.status(404).json({ error: 'Referral code not found' });
    }

    return res.status(200).json({
      ...refData,
      estimatedEarnings: (refData.conversions || 0) * 25,
    });
  } catch (err) {
    console.error('referral/stats error:', err);
    return res.status(500).json({ error: 'Internal server error' });
  }
};

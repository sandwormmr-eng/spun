# Spun — Deployment Guide

## 1. Deploy to Vercel

1. Go to [vercel.com](https://vercel.com) and sign in with GitHub
2. Click **Add New Project** and import the `spun` repository
3. Vercel auto-detects the config from `vercel.json` — no build settings needed
4. Click **Deploy**

## 2. Set Up Vercel KV (Redis)

1. In your Vercel project dashboard, go to **Storage** tab
2. Click **Create** → **KV Store**
3. Name it (e.g., `spun-kv`) and select a region
4. Click **Connect to Project** to link it to your spun project
5. Vercel automatically adds the `KV_REST_API_URL` and `KV_REST_API_TOKEN` env vars

## 3. Environment Variables

Go to **Settings** → **Environment Variables** and add:

| Variable | Value |
|---|---|
| `ADMIN_SECRET` | Choose a strong random password (e.g., `openssl rand -hex 24`) |

The KV variables are added automatically when you link the KV store (step 2).

## 4. Update DNS

Change your domain's CNAME record:

- **From:** GitHub Pages target (e.g., `sandwormmr-eng.github.io`)
- **To:** `cname.vercel-dns.com`

In Vercel, go to **Settings** → **Domains** → add `spun.sh` and follow the instructions.

## 5. Managing Referral Codes

### Create a referral code

```bash
curl -X POST https://spun.sh/api/referral/create \
  -H "Content-Type: application/json" \
  -d '{
    "secret": "YOUR_ADMIN_SECRET",
    "code": "alice",
    "name": "Alice",
    "telegramHandle": "@alice"
  }'
```

The referral link will be: `https://spun.sh?ref=alice`

### Check referral stats

```bash
curl "https://spun.sh/api/referral/stats?code=alice&secret=YOUR_ADMIN_SECRET"
```

Response:
```json
{
  "code": "alice",
  "name": "Alice",
  "telegramHandle": "@alice",
  "clicks": 42,
  "conversions": 5,
  "estimatedEarnings": 125
}
```

## 6. How Referral Payouts Work

1. When someone visits `spun.sh?ref=CODE`, the code is saved in their browser
2. When they complete a purchase, the conversion is recorded against that code
3. Check stats via the `/api/referral/stats` endpoint to see who earned what
4. Manually send $25 worth of SOL to the referrer's wallet
5. Track payouts externally (spreadsheet, etc.)

## 7. How Payments Work

1. Buyer visits `checkout.html` — the page calls `/api/create-session` which fetches the live SOL price and generates a unique Solana Pay reference
2. Buyer scans the QR code or opens in their wallet app
3. The page polls `/api/check-payment` every 4 seconds
4. When the reference key appears on-chain, the payment is confirmed and the install command is shown
5. If the buyer was referred, the referral conversion count is incremented

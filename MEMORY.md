# Long-term Memory — TradingClaw

## The Board project (Trading Intelligence Platform)
- Building a system for a trading group called **"The Board"**.
- Two initial strategies:
  1) **News Trading** (NFP, CPI, FOMC, PCE): run **T-30 min** pre-event research → deliver bias (LONG/SHORT), rationale, and actionable plan (entry/SL/TP + confidence).
  2) **NYSE Open Breakout (Nasdaq)**: 3-min 9:30 candle; at 9:33 enter on break of that candle’s high/low; run a **9:00 ET** pre-market intelligence cron to assess likely direction for next 15–20 mins.
- Phased rollout: **Advisory → Paper → Live**.
- Goal: interactive dashboard + feedback loop + post-mortems so the system learns from misses.
- Future execution: broker API + WebSocket real-time data; example risk rule: auto-close if move goes >50% against the 9:30 candle range.

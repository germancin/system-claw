# Trailing Stop + TP On/Off Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add classic trailing stop and TP on/off toggle to NewsStraddleEA, bumping version to v2.01.

**Architecture:** Four files modified in sequence — inputs first, then order logic with trailing function, then main EA call site, then UI. No new files created. Trailing runs in OnTick on every tick when a trade is active, using PositionModify to ratchet the SL forward.

**Tech Stack:** MQL5 (MetaTrader 5), CTrade/CPositionInfo standard library.

**Important:** All edits target `C:/Program Files/MetaTrader 5/MQL5/Experts/` (MT5 compile folder). After each task, the user compiles in MT5 to verify. No automated test framework — verification is compile + manual test.

---

## File Map

| File | Path | Action |
|---|---|---|
| `Inputs.mqh` | `C:/Program Files/MetaTrader 5/MQL5/Experts/includes/Inputs.mqh` | Modify: add 2 new inputs |
| `Orders.mqh` | `C:/Program Files/MetaTrader 5/MQL5/Experts/includes/Orders.mqh` | Modify: condition TP, add `ApplyTrailingStop()` |
| `NewsStraddleEA.mq5` | `C:/Program Files/MetaTrader 5/MQL5/Experts/NewsStraddleEA.mq5` | Modify: call trailing, bump version |
| `UI.mqh` | `C:/Program Files/MetaTrader 5/MQL5/Experts/includes/UI.mqh` | Modify: version label, params display |

---

### Task 1: Add new inputs (Inputs.mqh)

**Files:**
- Modify: `C:/Program Files/MetaTrader 5/MQL5/Experts/includes/Inputs.mqh:8-11`

- [ ] **Step 1: Add InpEnableTP and InpTrailingStopPips after InpTPPips (line 8)**

Add these two lines after line 8 (`InpTPPips`), before line 9 (`InpLotSize`):

```mql5
input bool   InpEnableTP           = true;          // Activar Take Profit
input double InpTrailingStopPips   = 2000.0;        // Trailing Stop en pips (0=off)
```

Final file should read (lines 5-13):
```mql5
input string InpNewsTime          = "08:30:00";   // Hora del evento (HH:MM:SS servidor)
input double InpEntryDistPips     = 1000.0;        // Distancia de entrada en pips
input double InpSLPips            = 10000.0;       // Stop Loss en pips
input double InpTPPips            = 10000.0;       // Take Profit en pips
input bool   InpEnableTP          = true;           // Activar Take Profit
input double InpTrailingStopPips  = 2000.0;         // Trailing Stop en pips (0=off)
input double InpLotSize           = 0.10;          // Tamaño de lote
input int    InpMagicNumber       = 202601;        // Magic Number único
input int    InpLeadTimeSeconds   = 10;            // Segundos antes del evento para colocar órdenes
```

- [ ] **Step 2: Verify** — User compiles in MT5. Expected: compiles OK, new inputs appear in EA properties dialog.

---

### Task 2: Condition TP calculation in SetStraddleLevels (Orders.mqh)

**Files:**
- Modify: `C:/Program Files/MetaTrader 5/MQL5/Experts/includes/Orders.mqh:42-50`

- [ ] **Step 1: Wrap TP calculation with InpEnableTP condition**

Replace lines 42-50 in `SetStraddleLevels()`:

```mql5
// Current code (lines 42-50):
   double tpDist = PipsToPrice(InpTPPips);

   g_buyLevel = NormalizeDouble(ask + dist, _Digits);
   g_buySL    = NormalizeDouble(g_buyLevel - slDist, _Digits);
   g_buyTP    = NormalizeDouble(g_buyLevel + tpDist, _Digits);

   g_sellLevel = NormalizeDouble(bid - dist, _Digits);
   g_sellSL    = NormalizeDouble(g_sellLevel + slDist, _Digits);
   g_sellTP    = NormalizeDouble(g_sellLevel - tpDist, _Digits);
```

Replace with:

```mql5
   double tpDist = InpEnableTP ? PipsToPrice(InpTPPips) : 0;

   g_buyLevel = NormalizeDouble(ask + dist, _Digits);
   g_buySL    = NormalizeDouble(g_buyLevel - slDist, _Digits);
   g_buyTP    = InpEnableTP ? NormalizeDouble(g_buyLevel + tpDist, _Digits) : 0;

   g_sellLevel = NormalizeDouble(bid - dist, _Digits);
   g_sellSL    = NormalizeDouble(g_sellLevel + slDist, _Digits);
   g_sellTP    = InpEnableTP ? NormalizeDouble(g_sellLevel - tpDist, _Digits) : 0;
```

- [ ] **Step 2: Verify** — Compiles OK. With `InpEnableTP=false`, logs should show `BuyTP=0` and `SellTP=0`.

---

### Task 3: Add ApplyTrailingStop function (Orders.mqh)

**Files:**
- Modify: `C:/Program Files/MetaTrader 5/MQL5/Experts/includes/Orders.mqh` — append after `SetStraddleLevels()`

- [ ] **Step 1: Add ApplyTrailingStop() at end of Orders.mqh (after line 57)**

```mql5
//+------------------------------------------------------------------+
//| ApplyTrailingStop — mueve SL siguiendo al precio (trailing)       |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   if(InpTrailingStopPips <= 0) return;
   if(g_positionTicket == 0)    return;

   if(!g_posInfo.SelectByTicket(g_positionTicket)) return;

   double currentSL = g_posInfo.StopLoss();
   double currentTP = g_posInfo.TakeProfit();
   double trailDist = PipsToPrice(InpTrailingStopPips);
   double newSL     = 0;

   if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      newSL = NormalizeDouble(bid - trailDist, _Digits);

      if(newSL > currentSL && (newSL - currentSL) >= _Point)
      {
         if(g_trade.PositionModify(g_positionTicket, newSL, currentTP))
            Print("[TRAIL] SL moved: old=", currentSL, " new=", newSL);
         else
            Print("[TRAIL] Modify failed: retcode=", g_trade.ResultRetcode());
      }
   }
   else if(g_posInfo.PositionType() == POSITION_TYPE_SELL)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      newSL = NormalizeDouble(ask + trailDist, _Digits);

      bool shouldModify = false;
      if(currentSL == 0)
         shouldModify = (newSL > 0);
      else
         shouldModify = (newSL < currentSL) && ((currentSL - newSL) >= _Point);

      if(shouldModify)
      {
         if(g_trade.PositionModify(g_positionTicket, newSL, currentTP))
            Print("[TRAIL] SL moved: old=", currentSL, " new=", newSL);
         else
            Print("[TRAIL] Modify failed: retcode=", g_trade.ResultRetcode());
      }
   }
}
```

- [ ] **Step 2: Verify** — Compiles OK.

---

### Task 4: Call ApplyTrailingStop from OnTick (NewsStraddleEA.mq5)

**Files:**
- Modify: `C:/Program Files/MetaTrader 5/MQL5/Experts/NewsStraddleEA.mq5:105-118`

- [ ] **Step 1: Add trailing call inside STATE_TRADE_ACTIVE, after position search loop**

Current code (lines 105-118):
```mql5
   if(g_state == STATE_TRADE_ACTIVE)
   {
      // Buscar posición por magic (más robusto que por ticket)
      bool found = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(g_posInfo.SelectByIndex(i) && g_posInfo.Magic() == InpMagicNumber
            && g_posInfo.Symbol() == _Symbol)
         {
            found = true;
            g_positionTicket = g_posInfo.Ticket();
            break;
         }
      }
```

Add the trailing call after the loop finds the position (after line 118, before `if(!found)`):

```mql5
      if(found)
         ApplyTrailingStop();
```

So the block becomes:
```mql5
   if(g_state == STATE_TRADE_ACTIVE)
   {
      // Buscar posición por magic (más robusto que por ticket)
      bool found = false;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(g_posInfo.SelectByIndex(i) && g_posInfo.Magic() == InpMagicNumber
            && g_posInfo.Symbol() == _Symbol)
         {
            found = true;
            g_positionTicket = g_posInfo.Ticket();
            break;
         }
      }

      if(found)
         ApplyTrailingStop();

      if(!found)
      {
```

- [ ] **Step 2: Verify** — Compiles OK.

---

### Task 5: Bump version (NewsStraddleEA.mq5)

**Files:**
- Modify: `C:/Program Files/MetaTrader 5/MQL5/Experts/NewsStraddleEA.mq5:1-9`

- [ ] **Step 1: Update header and version property**

Replace lines 1-9:
```mql5
//+------------------------------------------------------------------+
//|                                              NewsStraddleEA.mq5  |
//|      Pre-News Straddle (Market Orders) | v2.01                   |
//|      v2.01: Trailing Stop clásico + TP on/off                    |
//|                                        github.com/germancin      |
//+------------------------------------------------------------------+
#property copyright "germancin"
#property link      "https://github.com/germancin/system-claw"
#property version   "2.01"
```

- [ ] **Step 2: Verify** — Compiles OK.

---

### Task 6: Update UI (UI.mqh)

**Files:**
- Modify: `C:/Program Files/MetaTrader 5/MQL5/Experts/includes/UI.mqh:63,67-68`

- [ ] **Step 1: Update version in title label (line 63)**

```mql5
   CreateLabel("NewsEA_Title",  "═══ NEWS STRADDLE EA v2.01 ═══",                    baseX, baseY + 40,  clrGold,          11);
```

- [ ] **Step 2: Update params line to show TP and trailing status (lines 67-68)**

Replace:
```mql5
   CreateLabel("NewsEA_Params", StringFormat("Dist: %.1f | SL: %.1f | TP: %.1f pips",
               InpEntryDistPips, InpSLPips, InpTPPips),                               baseX, baseY + 116, C'100,200,255',    8);
```

With:
```mql5
   CreateLabel("NewsEA_Params", StringFormat("Dist:%.0f | SL:%.0f | TP:%s | Trail:%s",
               InpEntryDistPips, InpSLPips,
               InpEnableTP ? StringFormat("%.0f", InpTPPips) : "OFF",
               InpTrailingStopPips > 0 ? StringFormat("%.0f", InpTrailingStopPips) : "OFF"),
               baseX, baseY + 116, C'100,200,255', 8);
```

- [ ] **Step 3: Verify** — Compiles OK. Panel shows correct TP/Trail status.

---

### Task 7: Manual integration test

No automated tests — this is MQL5. User tests in MT5.

- [ ] **Test A: Trailing ON + TP ON** — Attach EA to chart, set `InpTrailingStopPips=2000`, `InpEnableTP=true`. Open a trade. Verify in Experts tab: `[TRAIL] SL moved` logs appear as price moves. Verify TP is set on the position.

- [ ] **Test B: Trailing ON + TP OFF** — Set `InpEnableTP=false`. Open a trade. Verify position has no TP (0). Verify trailing moves SL. Position should only close when SL is hit.

- [ ] **Test C: Trailing OFF** — Set `InpTrailingStopPips=0`. Verify EA works exactly as v2.00 — no trailing logs, SL and TP fixed.

- [ ] **Test D: UI check** — Verify panel shows "v2.01", params line shows correct TP/Trail status for each combination.

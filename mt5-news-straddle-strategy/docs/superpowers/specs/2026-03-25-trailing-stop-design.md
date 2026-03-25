# Trailing Stop + TP On/Off — NewsStraddleEA v2.01

## Summary

Add a classic trailing stop and a toggle to enable/disable the fixed Take Profit. The trailing stop follows the price like a shadow, always keeping the SL a fixed distance behind the highest (BUY) or lowest (SELL) price reached. The TP toggle lets the user choose between capping profit at a fixed level or letting the trailing stop manage the exit with no ceiling.

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `InpEnableTP` | `bool` | `true` | `true` = send fixed TP to broker. `false` = no TP (trailing manages exit). // Activar Take Profit |
| `InpTrailingStopPips` | `double` | `2000.0` | Trailing distance in pips. `0` = trailing disabled, EA works as before. // Trailing Stop en pips (0=off) |

## Trailing Stop Logic

**When:** `STATE_TRADE_ACTIVE` and `InpTrailingStopPips > 0`, checked every tick in `OnTick()`.

**Pre-requisite:** The position must be selected before reading its properties. `ApplyTrailingStop()` must call `g_posInfo.SelectByTicket(g_positionTicket)` first. If selection fails, return without action.

**Algorithm (BUY position):**
1. Select position via `g_posInfo.SelectByTicket(g_positionTicket)`
2. Read position type via `g_posInfo.PositionType()` to determine BUY or SELL
3. Read current Bid price (Bid is used to close a BUY)
4. Calculate `newSL = NormalizeDouble(Bid - PipsToPrice(InpTrailingStopPips), _Digits)`
5. Read `currentSL = g_posInfo.StopLoss()` and `currentTP = g_posInfo.TakeProfit()`
6. If `newSL > currentSL` → call `g_trade.PositionModify(g_positionTicket, newSL, currentTP)`
7. On success: `Print("[TRAIL] SL moved: old=", currentSL, " new=", newSL)`
8. On failure: `Print("[TRAIL] Modify failed: retcode=", g_trade.ResultRetcode())` — do nothing, retry next tick
9. Otherwise (newSL <= currentSL), do nothing (SL never moves backwards)

**Algorithm (SELL position):**
1. Same selection as BUY
2. Read current Ask price (Ask is used to close a SELL)
3. Calculate `newSL = NormalizeDouble(Ask + PipsToPrice(InpTrailingStopPips), _Digits)`
4. Read `currentSL = g_posInfo.StopLoss()` and `currentTP = g_posInfo.TakeProfit()`
5. **Guard:** If `currentSL == 0` (no SL set), treat any valid `newSL > 0` as an improvement → modify
6. If `currentSL > 0` and `newSL < currentSL` → call `g_trade.PositionModify(g_positionTicket, newSL, currentTP)`
7. Same logging as BUY
8. Otherwise, do nothing

**TP preservation:** When calling `PositionModify`, always pass the current TP from the position. When `InpEnableTP == false`, this will be `0` (no TP), and `PositionModify` with TP=0 keeps it at zero. This is intentional.

**Throttling:** To avoid excessive broker calls on volatile instruments, only call `PositionModify` when the difference between `newSL` and `currentSL` is at least 1 point (`_Point`). This prevents micro-adjustments every tick while still maintaining precision.

**Key properties:**
- The SL only moves in the favorable direction, never backwards
- The original SL (from `InpSLPips`) serves as initial protection until trailing overtakes it
- With trailing = 2000 and SL = 5000, the trailing takes over almost immediately since 2000 < 5000
- Breakeven is reached when price moves exactly `InpTrailingStopPips` pips from entry
- All computed SL values are normalized with `NormalizeDouble(..., _Digits)`

## TP On/Off Logic

**Where:** `SetStraddleLevels()` in `Orders.mqh`.

- If `InpEnableTP == true` → calculate TP as current code does (`g_buyTP`, `g_sellTP`)
- If `InpEnableTP == false` → set `g_buyTP = 0` and `g_sellTP = 0` (MT5 interprets 0 as no TP)

The market order in `OnTick()` already passes `g_buyTP`/`g_sellTP`, so sending 0 means no TP is placed.

## Files Modified

| File | Changes |
|---|---|
| `Inputs.mqh` | Add `InpEnableTP` and `InpTrailingStopPips` with MQL5-style comments |
| `Globals.mqh` | No changes needed |
| `Orders.mqh` | Condition TP calculation on `InpEnableTP`. Add `ApplyTrailingStop()` function. |
| `NewsStraddleEA.mq5` | Call `ApplyTrailingStop()` from `OnTick()` inside `STATE_TRADE_ACTIVE` block, before the position-closed detection. Bump `#property version` to `"2.01"` and update header comment. |
| `UI.mqh` | Update version in title label (`"═══ NEWS STRADDLE EA v2.01 ═══"` at line 63). Update params line to show trailing/TP status. |

## UI Changes

- Version label in `UI.mqh` line 63: `"═══ NEWS STRADDLE EA v2.01 ═══"`
- Version in `NewsStraddleEA.mq5` line 3 and line 9
- Params line updated to show: `"Dist: X | SL: X | TP: X (or OFF) | Trail: X (or OFF)"`

## Edge Cases

- **Trailing = 0:** No trailing, EA works exactly as v2.00.
- **TP enabled + trailing:** Trailing protects on the way up, TP caps the profit. Whichever hits first closes the trade.
- **TP disabled + trailing = 0:** Position stays open with only the fixed SL. Not recommended but allowed.
- **PositionModify fails:** Log the error, do not change state. The position stays open with its current SL. Retry on next tick naturally.
- **Spread considerations:** Using Bid for BUY trailing and Ask for SELL trailing accounts for the spread correctly.
- **SELL with currentSL == 0:** Guard handles this — any valid newSL is accepted as improvement.
- **Micro-movements:** Throttled by requiring minimum 1 point difference to avoid excessive PositionModify calls.

## Example Scenario

Note: values below are in price units for clarity. The EA uses `PipsToPrice()` internally to convert pips to price distance (e.g., on BTCUSD with 2 decimals, 2000 pips × 0.01 = $20 trailing distance).

BUY BTCUSD at $70,000 | SL=5000 pips ($50) → SL at $69,950 | Trailing=2000 pips ($20) | TP=OFF

```
Bid $70,010 → newSL=$69,990 > $69,950 → modify to $69,990
Bid $70,030 → newSL=$70,010 > $69,990 → modify to $70,010
Bid $70,020 → newSL=$70,000 < $70,010 → no move (never backwards)
Bid $70,050 → newSL=$70,030 > $70,010 → modify to $70,030 (profit locked: $30)
Bid drops to $70,030 → SL hit → closed at +$30 profit
```

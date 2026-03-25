//+------------------------------------------------------------------+
//| Orders.mqh — Calcula niveles de entrada (sin órdenes pendientes)  |
//+------------------------------------------------------------------+

const string LINE_BUY  = "NewsEA_BuyLevel";
const string LINE_SELL = "NewsEA_SellLevel";

void DrawTriggerLines()
{
   // Línea BUY — verde
   ObjectDelete(0, LINE_BUY);
   ObjectCreate(0, LINE_BUY, OBJ_HLINE, 0, 0, g_buyLevel);
   ObjectSetInteger(0, LINE_BUY, OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, LINE_BUY, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, LINE_BUY, OBJPROP_WIDTH, 1);
   ObjectSetString(0, LINE_BUY, OBJPROP_TEXT, "BUY Trigger " + DoubleToString(g_buyLevel, _Digits));

   // Línea SELL — roja
   ObjectDelete(0, LINE_SELL);
   ObjectCreate(0, LINE_SELL, OBJ_HLINE, 0, 0, g_sellLevel);
   ObjectSetInteger(0, LINE_SELL, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, LINE_SELL, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, LINE_SELL, OBJPROP_WIDTH, 1);
   ObjectSetString(0, LINE_SELL, OBJPROP_TEXT, "SELL Trigger " + DoubleToString(g_sellLevel, _Digits));

   ChartRedraw();
}

void RemoveTriggerLines()
{
   ObjectDelete(0, LINE_BUY);
   ObjectDelete(0, LINE_SELL);
   ChartRedraw();
}

void SetStraddleLevels()
{
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist = PipsToPrice(InpEntryDistPips);
   double slDist = PipsToPrice(InpSLPips);
   double tpDist = InpEnableTP ? PipsToPrice(InpTPPips) : 0;

   g_buyLevel = NormalizeDouble(ask + dist, _Digits);
   g_buySL    = NormalizeDouble(g_buyLevel - slDist, _Digits);
   g_buyTP    = InpEnableTP ? NormalizeDouble(g_buyLevel + tpDist, _Digits) : 0;

   g_sellLevel = NormalizeDouble(bid - dist, _Digits);
   g_sellSL    = NormalizeDouble(g_sellLevel + slDist, _Digits);
   g_sellTP    = InpEnableTP ? NormalizeDouble(g_sellLevel - tpDist, _Digits) : 0;

   Print("[LEVELS] Ask=", ask, " Bid=", bid);
   Print("[LEVELS] BuyLevel=", g_buyLevel, " BuySL=", g_buySL, " BuyTP=", g_buyTP);
   Print("[LEVELS] SellLevel=", g_sellLevel, " SellSL=", g_sellSL, " SellTP=", g_sellTP);

   DrawTriggerLines();
}

//+------------------------------------------------------------------+
//| ApplyTrailingStop — mueve SL siguiendo al precio (trailing)       |
//+------------------------------------------------------------------+
void ApplyTrailingStop()
{
   if(InpTrailingStopPips <= 0) return;
   if(g_positionTicket == 0)    return;

   if(!g_posInfo.SelectByTicket(g_positionTicket)) return;

   double currentSL  = g_posInfo.StopLoss();
   double currentTP  = g_posInfo.TakeProfit();
   double openPrice  = g_posInfo.PriceOpen();
   double trailDist  = PipsToPrice(InpTrailingStopPips);
   double newSL      = 0;

   if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      newSL = NormalizeDouble(bid - trailDist, _Digits);

      // Solo activar trailing cuando newSL >= precio de entrada (breakeven o mejor)
      if(newSL >= openPrice && newSL > currentSL && (newSL - currentSL) >= _Point)
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

      // Solo activar trailing cuando newSL <= precio de entrada (breakeven o mejor)
      bool shouldModify = false;
      if(newSL <= openPrice)
      {
         if(currentSL == 0)
            shouldModify = (newSL > 0);
         else
            shouldModify = (newSL < currentSL) && ((currentSL - newSL) >= _Point);
      }

      if(shouldModify)
      {
         if(g_trade.PositionModify(g_positionTicket, newSL, currentTP))
            Print("[TRAIL] SL moved: old=", currentSL, " new=", newSL);
         else
            Print("[TRAIL] Modify failed: retcode=", g_trade.ResultRetcode());
      }
   }
}

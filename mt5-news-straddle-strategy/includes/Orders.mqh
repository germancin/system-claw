//+------------------------------------------------------------------+
//| Orders.mqh — Colocación de órdenes straddle                      |
//+------------------------------------------------------------------+

bool PlaceStraddleOrders()
{
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist = PipsToPrice(InpEntryDistPips);
   double bS   = NormalizeDouble(ask + dist, _Digits);
   double sS   = NormalizeDouble(bid - dist, _Digits);

   // Calcular SL
   double slDist = PipsToPrice(InpSLPips);
   double buySL  = NormalizeDouble(bS - slDist, _Digits);
   double sellSL = NormalizeDouble(sS + slDist, _Digits);

   Print("[ORDERS] Ask=", ask, " Bid=", bid, " Dist=", dist, " BuyStop=", bS, " SellStop=", sS,
         " BuySL=", buySL, " SellSL=", sellSL, " Digits=", _Digits, " Point=", _Point, " PipFactor=", g_pipFactor);

   if(!g_trade.BuyStop(InpLotSize, bS, _Symbol, buySL, 0)) return false;
   g_buyOrderTicket = g_trade.ResultOrder();

   if(!g_trade.SellStop(InpLotSize, sS, _Symbol, sellSL, 0))
   {
      g_trade.OrderDelete(g_buyOrderTicket);
      return false;
   }
   g_sellOrderTicket = g_trade.ResultOrder();
   return true;
}

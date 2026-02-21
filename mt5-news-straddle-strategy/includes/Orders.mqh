//+------------------------------------------------------------------+
//| Orders.mqh — Colocación de órdenes y gestión de TP                |
//+------------------------------------------------------------------+

bool PlaceStraddleOrders()
{
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist = PipsToPrice(InpEntryDistPips);
   double bS   = NormalizeDouble(ask + dist, _Digits);
   double sS   = NormalizeDouble(bid - dist, _Digits);

   Print("[ORDERS] Ask=", ask, " Bid=", bid, " Dist=", dist, " BuyStop=", bS, " SellStop=", sS, " Digits=", _Digits, " Point=", _Point, " PipFactor=", g_pipFactor);

   // Órdenes limpias: SL=0, TP=0
   if(!g_trade.BuyStop(InpLotSize, bS, _Symbol, 0, 0)) return false;
   g_buyOrderTicket = g_trade.ResultOrder();

   if(!g_trade.SellStop(InpLotSize, sS, _Symbol, 0, 0))
   {
      g_trade.OrderDelete(g_buyOrderTicket);
      return false;
   }
   g_sellOrderTicket = g_trade.ResultOrder();
   return true;
}

void SetTakeProfitOnly()
{
   if(g_positionTicket == 0 || !g_useTP) return;
   if(!g_posInfo.SelectByTicket(g_positionTicket)) return;

   double tpD    = PipsToPrice(InpTPPips);
   double openP  = g_posInfo.PriceOpen();
   double tp     = (g_posInfo.PositionType() == POSITION_TYPE_BUY) ? openP + tpD : openP - tpD;
   double tpNorm = NormalizeDouble(tp, _Digits);

   // Pone TP con SL=0. UNA sola vez.
   if(g_trade.PositionModify(g_positionTicket, 0, tpNorm))
      Print("[TP] TP puesto en ", tpNorm);
   else
      Print("[TP] Error al poner TP: ", g_trade.ResultRetcodeDescription());
}

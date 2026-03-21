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

   // Calcular TP si está activo
   double tpDist = g_useTP ? PipsToPrice(InpTPPips) : 0;
   double buyTP  = g_useTP ? NormalizeDouble(bS + tpDist, _Digits) : 0;
   double sellTP = g_useTP ? NormalizeDouble(sS - tpDist, _Digits) : 0;

   Print("[ORDERS] Ask=", ask, " Bid=", bid, " Dist=", dist, " BuyStop=", bS, " SellStop=", sS,
         " BuyTP=", buyTP, " SellTP=", sellTP, " Digits=", _Digits, " Point=", _Point, " PipFactor=", g_pipFactor);

   // Órdenes con TP real si está ON
   if(!g_trade.BuyStop(InpLotSize, bS, _Symbol, 0, buyTP)) return false;
   g_buyOrderTicket = g_trade.ResultOrder();

   if(!g_trade.SellStop(InpLotSize, sS, _Symbol, 0, sellTP))
   {
      g_trade.OrderDelete(g_buyOrderTicket);
      return false;
   }
   g_sellOrderTicket = g_trade.ResultOrder();
   return true;
}

void SetVirtualTP()
{
   if(g_positionTicket == 0 || !g_useTP) return;
   if(!g_posInfo.SelectByTicket(g_positionTicket)) return;

   double tpD    = PipsToPrice(InpTPPips);
   double openP  = g_posInfo.PriceOpen();
   double tp     = (g_posInfo.PositionType() == POSITION_TYPE_BUY) ? openP + tpD : openP - tpD;
   g_virtualTP   = NormalizeDouble(tp, _Digits);

   // Enviar TP real al broker para que sea visible en chart y posición
   double curSL = g_posInfo.StopLoss();
   if(g_trade.PositionModify(g_positionTicket, curSL, g_virtualTP))
      Print("[TP] Enviado al broker: ", g_virtualTP);
   else
      Print("[TP] Error al enviar al broker: ", GetLastError());
}

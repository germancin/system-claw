//+------------------------------------------------------------------+
//| TrailingLogic.mqh — Gestión del trade activo y trailing stop      |
//|                                                                    |
//| LÓGICA v1.15:                                                      |
//|   - Si TP OFF → El EA no toca nada. Control manual total.         |
//|   - Si TP ON  → Monitorea TP internamente.                        |
//|   - Cuando precio toca TP Virtual → Trailing arranca ese tick.    |
//|   - SL = precio_actual - InpTrailingPips (sube, nunca baja).      |
//+------------------------------------------------------------------+

void ManageTrade()
{
   if(g_positionTicket == 0 || !g_posInfo.SelectByTicket(g_positionTicket)) return;

   // Si TP está OFF → El EA no toca nada. Tú controlas manualmente.
   if(!g_useTP) return;

   // Si TP Virtual no se ha dibujado aún, hacerlo
   if(g_virtualTP == 0) { SetVirtualTP(); return; }

   // Detectar si el precio tocó el TP Virtual
   if(!g_tpReached)
   {
      if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid >= g_virtualTP)
         {
            g_tpReached = true;
            Print("[VIRTUAL TP] Tocado en BUY. Trailing activo desde: ", bid);
         }
      }
      else  // SELL
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(ask <= g_virtualTP)
         {
            g_tpReached = true;
            Print("[VIRTUAL TP] Tocado en SELL. Trailing activo desde: ", ask);
         }
      }
      
      // Si NO ha tocado TP virtual → esperamos
      if(!g_tpReached) return;
   }

   // TRAILING ACTIVO (después de tocar TP Virtual)
   double curSL  = g_posInfo.StopLoss();
   double trailD = PipsToPrice(InpTrailingPips);

   if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double newSL = NormalizeDouble(bid - trailD, _Digits);
      if(newSL > curSL)
      {
         g_trade.PositionModify(g_positionTicket, newSL, 0);
         Print("[TRAILING] BUY SL movido a ", newSL);
      }
   }
   else
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double newSL = NormalizeDouble(ask + trailD, _Digits);
      if(newSL < curSL)
      {
         g_trade.PositionModify(g_positionTicket, newSL, 0);
         Print("[TRAILING] SELL SL movido a ", newSL);
      }
   }
}

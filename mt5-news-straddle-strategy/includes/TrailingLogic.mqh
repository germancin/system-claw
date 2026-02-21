//+------------------------------------------------------------------+
//| TrailingLogic.mqh — Gestión del trade activo y trailing stop      |
//|                                                                    |
//| REGLAS:                                                            |
//|   - Si TP OFF → El EA no toca nada. Control manual.               |
//|   - Si TP ON  → Solo pone TP. No toca SL.                        |
//|   - Si TP ON y precio toca TP → Nace el Trailing Stop.           |
//|   - SL manual del usuario NUNCA se borra.                         |
//+------------------------------------------------------------------+

void ManageTrade()
{
   if(g_positionTicket == 0 || !g_posInfo.SelectByTicket(g_positionTicket)) return;

   // Si TP está OFF → El EA no toca nada. Tú controlas manualmente.
   if(!g_useTP) return;

   // Si TP está ON pero no se ha puesto aún, ponerlo
   double curTP = g_posInfo.TakeProfit();
   if(curTP == 0) { SetTakeProfitOnly(); return; }

   // ¿Ya tocó el TP? Solo entonces nace el Trailing.
   if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(!g_tpReached && bid >= curTP)
      {
         g_tpReached = true;
         Print("[TRAILING] TP ALCANZADO en BUY. Activando trailing ahora.");
      }
   }
   else
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(!g_tpReached && ask <= curTP)
      {
         g_tpReached = true;
         Print("[TRAILING] TP ALCANZADO en SELL. Activando trailing ahora.");
      }
   }

   // Si NO ha tocado TP → No hacemos nada. Respetamos SL manual si existe.
   if(!g_tpReached) return;

   // SOLO AQUÍ NACE EL TRAILING (después de tocar TP)
   double curSL  = g_posInfo.StopLoss();
   double trailD = PipsToPrice(InpTrailingPips);

   if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double newSL = NormalizeDouble(bid - trailD, _Digits);
      if(newSL > curSL || curSL == 0)
      {
         g_trade.PositionModify(g_positionTicket, newSL, curTP);
         Print("[TRAILING] BUY SL movido a ", newSL);
      }
   }
   else
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double newSL = NormalizeDouble(ask + trailD, _Digits);
      if(newSL < curSL || curSL == 0)
      {
         g_trade.PositionModify(g_positionTicket, newSL, curTP);
         Print("[TRAILING] SELL SL movido a ", newSL);
      }
   }
}

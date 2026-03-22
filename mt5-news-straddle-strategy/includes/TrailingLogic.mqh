//+------------------------------------------------------------------+
//| TrailingLogic.mqh — Gestión del trade activo y trailing stop      |
//|                                                                    |
//| LÓGICA v1.17:                                                      |
//|   - Si TP OFF → El EA no toca nada. Control manual total.         |
//|   - Si TP ON  → Monitorea TP internamente (Virtual TP).           |
//|   - Cuando precio toca TP Virtual → se quita TP del broker        |
//|     para evitar cierre automático, y trailing toma control.        |
//|   - SL = precio_actual - InpTrailingPips (sube, nunca baja).      |
//+------------------------------------------------------------------+

void ManageTrade()
{
   if(g_positionTicket == 0 || !g_posInfo.SelectByTicket(g_positionTicket)) return;

   // Si TP está OFF → El EA no toca nada. Tú controlas manualmente.
   if(!g_useTP) return;

   // Si TP Virtual no se ha calculado aún, hacerlo
   if(g_virtualTP == 0) { SetVirtualTP(); return; }

   // Detectar si el precio tocó el TP Virtual
   if(!g_tpReached)
   {
      if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         Print("[DEBUG] Esperando TP Virtual BUY | Bid=", bid, " | VirtualTP=", g_virtualTP,
               " | Faltan=", DoubleToString(g_virtualTP - bid, _Digits), " pts");
         if(bid >= g_virtualTP)
         {
            g_tpReached = true;
            // FIX: quitar TP del broker para que no cierre la posición automáticamente
            double curSL = g_posInfo.StopLoss();
            if(g_trade.PositionModify(g_positionTicket, curSL, 0))
               Print("[VIRTUAL TP HIT] BUY tocado en ", bid, " | TP removido del broker | Trailing ARRANCA");
            else
               Print("[VIRTUAL TP HIT] BUY tocado en ", bid, " | ERROR al quitar TP del broker: ", GetLastError());
         }
      }
      else  // SELL
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         Print("[DEBUG] Esperando TP Virtual SELL | Ask=", ask, " | VirtualTP=", g_virtualTP,
               " | Faltan=", DoubleToString(ask - g_virtualTP, _Digits), " pts");
         if(ask <= g_virtualTP)
         {
            g_tpReached = true;
            // FIX: quitar TP del broker para que no cierre la posición automáticamente
            double curSL = g_posInfo.StopLoss();
            if(g_trade.PositionModify(g_positionTicket, curSL, 0))
               Print("[VIRTUAL TP HIT] SELL tocado en ", ask, " | TP removido del broker | Trailing ARRANCA");
            else
               Print("[VIRTUAL TP HIT] SELL tocado en ", ask, " | ERROR al quitar TP del broker: ", GetLastError());
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
      Print("[TRAILING CHECK] BUY | Bid=", bid, " | CurSL=", curSL, " | NewSL=", newSL,
            " | Mover=", (newSL > curSL ? "SI" : "NO - precio no avanzó"));
      if(newSL > curSL)
      {
         if(g_trade.PositionModify(g_positionTicket, newSL, 0))
            Print("[TRAILING MOVED] BUY SL: ", curSL, " → ", newSL, " | Bid=", bid);
         else
            Print("[TRAILING ERROR] No se pudo mover SL. Error: ", GetLastError());
      }
   }
   else
   {
      double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double newSL = NormalizeDouble(ask + trailD, _Digits);
      Print("[TRAILING CHECK] SELL | Ask=", ask, " | CurSL=", curSL, " | NewSL=", newSL,
            " | Mover=", (newSL < curSL ? "SI" : "NO - precio no avanzó"));
      if(newSL < curSL)
      {
         if(g_trade.PositionModify(g_positionTicket, newSL, 0))
            Print("[TRAILING MOVED] SELL SL: ", curSL, " → ", newSL, " | Ask=", ask);
         else
            Print("[TRAILING ERROR] No se pudo mover SL. Error: ", GetLastError());
      }
   }
}

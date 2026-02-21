//+------------------------------------------------------------------+
//| TrailingLogic.mqh — Gestión del trade activo y trailing stop      |
//|                                                                    |
//| NUEVA LÓGICA (v1.11 - TP VIRTUAL):                                |
//|   - Si TP OFF → El EA no toca nada. Control manual.               |
//|   - Si TP ON  → Dibuja línea verde (TP Virtual). NO va al broker.|
//|   - Cuando precio toca TP Virtual → Pone SL breakeven + buffer.   |
//|   - Desde ahí activa Trailing Stop para seguir subiendo.          |
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
            
            // Poner SL en breakeven + buffer (5000 pips = $50 para BTC)
            double openP = g_posInfo.PriceOpen();
            double buffer = PipsToPrice(5000);  // $50 buffer para spread
            double breakeven = NormalizeDouble(openP + buffer, _Digits);
            
            g_trade.PositionModify(g_positionTicket, breakeven, 0);
            Print("[VIRTUAL TP] Tocado en BUY. SL en breakeven+buffer: ", breakeven);
         }
      }
      else  // SELL
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(ask <= g_virtualTP)
         {
            g_tpReached = true;
            
            // Poner SL en breakeven - buffer
            double openP = g_posInfo.PriceOpen();
            double buffer = PipsToPrice(5000);
            double breakeven = NormalizeDouble(openP - buffer, _Digits);
            
            g_trade.PositionModify(g_positionTicket, breakeven, 0);
            Print("[VIRTUAL TP] Tocado en SELL. SL en breakeven-buffer: ", breakeven);
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

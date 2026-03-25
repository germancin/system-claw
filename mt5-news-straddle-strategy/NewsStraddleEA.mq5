//+------------------------------------------------------------------+
//|                                              NewsStraddleEA.mq5  |
//|      Pre-News Straddle (Market Orders) | v2.01                   |
//|      v2.01: Trailing Stop clásico + TP on/off                    |
//|                                        github.com/germancin      |
//+------------------------------------------------------------------+
#property copyright "germancin"
#property link      "https://github.com/germancin/system-claw"
#property version   "2.01"

//--- Standard Library
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//--- EA Modules
#include "includes/Inputs.mqh"
#include "includes/Globals.mqh"
#include "includes/UI.mqh"
#include "includes/Orders.mqh"

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   InitPipFactor();
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(50);

   long fillType = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillType & SYMBOL_FILLING_IOC) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((fillType & SYMBOL_FILLING_FOK) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   g_eventTime = ParseEventTime(InpNewsTime);
   g_state = STATE_ARMED;
   Print("[INIT] EA armado para ", InpNewsTime, " | Filling=", fillType);

   InitUI();
   EventSetMillisecondTimer(500);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick — Monitorea niveles y abre market order al cruzar          |
//+------------------------------------------------------------------+
void OnTick()
{
   // Monitorear niveles — abrir market order cuando el precio cruza
   if(g_state == STATE_MONITORING)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(ask >= g_buyLevel)
      {
         Print("[MARKET] Ask=", ask, " cruzó BuyLevel=", g_buyLevel, " — abriendo BUY");
         bool ok = g_trade.Buy(InpLotSize, _Symbol, ask, g_buySL, g_buyTP);
         Print("[MARKET] Buy OK=", ok,
               " | retcode=", g_trade.ResultRetcode(),
               " | desc=", g_trade.ResultRetcodeDescription());

         if(ok)
         {
            g_positionTicket = g_trade.ResultOrder();
            g_state = STATE_TRADE_ACTIVE;
         }
         else
         {
            Print("[MARKET] ERROR — deteniendo EA");
            g_state = STATE_IDLE;
         }
         g_buyLevel = 0;
         g_sellLevel = 0;
         RemoveTriggerLines();
      }
      else if(bid <= g_sellLevel)
      {
         Print("[MARKET] Bid=", bid, " cruzó SellLevel=", g_sellLevel, " — abriendo SELL");
         bool ok = g_trade.Sell(InpLotSize, _Symbol, bid, g_sellSL, g_sellTP);
         Print("[MARKET] Sell OK=", ok,
               " | retcode=", g_trade.ResultRetcode(),
               " | desc=", g_trade.ResultRetcodeDescription());

         if(ok)
         {
            g_positionTicket = g_trade.ResultOrder();
            g_state = STATE_TRADE_ACTIVE;
         }
         else
         {
            Print("[MARKET] ERROR — deteniendo EA");
            g_state = STATE_IDLE;
         }
         g_buyLevel = 0;
         g_sellLevel = 0;
         RemoveTriggerLines();
      }
   }

   // Monitorear trade activo — detectar cierre
   else if(g_state == STATE_TRADE_ACTIVE)
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
         HistorySelect(TimeCurrent() - 86400, TimeCurrent());
         for(int d = HistoryDealsTotal() - 1; d >= 0; d--)
         {
            ulong dTicket = HistoryDealGetTicket(d);
            if(HistoryDealGetInteger(dTicket, DEAL_MAGIC) == InpMagicNumber &&
               HistoryDealGetString(dTicket, DEAL_SYMBOL) == _Symbol &&
               HistoryDealGetInteger(dTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
               double profit = HistoryDealGetDouble(dTicket, DEAL_PROFIT);
               long   reason = HistoryDealGetInteger(dTicket, DEAL_REASON);
               string reasonStr = (reason == DEAL_REASON_SL) ? "SL" :
                                  (reason == DEAL_REASON_TP) ? "TP" :
                                  (reason == DEAL_REASON_EXPERT) ? "EA" : "MANUAL/OTRO";
               Print("[CERRADA] Motivo=", reasonStr, " | Profit=", DoubleToString(profit, 2));
               break;
            }
         }

         g_state = STATE_IDLE;
         g_positionTicket = 0;
      }
   }
}

//+------------------------------------------------------------------+
//| OnTimer — Countdown + activar monitoreo                           |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_state == STATE_ARMED && TimeCurrent() >= g_eventTime - InpLeadTimeSeconds)
   {
      SetStraddleLevels();
      g_state = STATE_MONITORING;
      Print("[TIMER] Monitoreo activo");
   }
   UpdateUI();
}

//+------------------------------------------------------------------+
//| OnChartEvent — CANCEL y MINIMIZE                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &l, const double &d, const string &s)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(s == BTN_MINIMIZE) { ToggleMinimize(); return; }

   if(s == BTN_CANCEL)
   {
      // Cerrar posición si existe
      if(g_positionTicket != 0 && g_posInfo.SelectByTicket(g_positionTicket))
      {
         g_trade.PositionClose(g_positionTicket);
         Print("[CANCEL] Posición cerrada: ", g_positionTicket);
      }

      g_state = STATE_IDLE;
      g_positionTicket = 0;
      g_buyLevel = 0;
      g_sellLevel = 0;
      RemoveTriggerLines();
      Print("[CANCEL] Todo cancelado");
   }
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanupUI();
   EventKillTimer();
}

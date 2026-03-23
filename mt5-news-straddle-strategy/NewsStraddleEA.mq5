//+------------------------------------------------------------------+
//|                                              NewsStraddleEA.mq5  |
//|      Pre-News Straddle (Standard Stops) + Trailing | v1.18       |
//|      Update: Virtual TP + Breakeven + Trailing (unlimited upside) |
//|      v1.16: Botón minimizar/restaurar panel UI (esquina superior) |
//|      v1.17: Fix trailing - quita TP broker al tocar VirtualTP     |
//|             + logs detallados de trailing y cierre de posición    |
//|      v1.18: Fix compile error HistorySelectByPosition             |
//|             + logs detallados en detección de entry/order delete  |
//|                                        github.com/germancin      |
//+------------------------------------------------------------------+
#property copyright "germancin"
#property link      "https://github.com/germancin/system-claw"
#property version   "1.18"

//--- Standard Library
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

//--- EA Modules
#include "includes/Inputs.mqh"
#include "includes/Globals.mqh"
#include "includes/UI.mqh"
#include "includes/Orders.mqh"
#include "includes/TrailingLogic.mqh"

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   InitPipFactor();
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(50);

   // Detectar filling mode del broker
   long fillType = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillType & SYMBOL_FILLING_IOC) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((fillType & SYMBOL_FILLING_FOK) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   Print("[INIT] Filling mode: ", fillType);

   g_useTP = InpUseTP;
   
   // Auto-arm: parse event time and set state to ARMED
   g_eventTime = ParseEventTime(InpNewsTime);
   g_state = STATE_ARMED;
   Print("[INIT] EA armado automáticamente para ", InpNewsTime);
   
   InitUI();
   EventSetMillisecondTimer(500);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   // Detectar si una orden pendiente se activó
   if(g_state == STATE_ORDERS_PLACED)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(g_posInfo.SelectByIndex(i) && g_posInfo.Magic() == InpMagicNumber)
         {
            g_positionTicket = g_posInfo.Ticket();
            g_state = STATE_TRADE_ACTIVE;
            g_tpReached = false;

            string posDir = (g_posInfo.PositionType() == POSITION_TYPE_BUY) ? "BUY" : "SELL";
            Print("[ENTRY] Posición ", posDir, " detectada. Ticket=", g_positionTicket,
                  " | BuyOrderTicket=", g_buyOrderTicket,
                  " | SellOrderTicket=", g_sellOrderTicket);

            // Borrar la orden opuesta
            if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
            {
               bool ok = g_trade.OrderDelete(g_sellOrderTicket);
               Print("[ENTRY] Eliminando SellStop ticket=", g_sellOrderTicket, " | OK=", ok, " Err=", GetLastError());
            }
            else
            {
               bool ok = g_trade.OrderDelete(g_buyOrderTicket);
               Print("[ENTRY] Eliminando BuyStop ticket=", g_buyOrderTicket, " | OK=", ok, " Err=", GetLastError());
            }

            // Poner TP Virtual si está ON (línea verde, no va al broker)
            if(g_useTP) SetVirtualTP();
         }
      }
   }

   // Gestionar trade activo
   if(g_state == STATE_TRADE_ACTIVE)
   {
      if(g_posInfo.SelectByTicket(g_positionTicket))
         ManageTrade();
      else
      {
         // Posición cerrada — buscar en historial para loggear resultado
         HistorySelect(TimeCurrent() - 86400, TimeCurrent());
         int total = HistoryDealsTotal();
         bool found = false;
         for(int d = total - 1; d >= 0; d--)
         {
            ulong dTicket = HistoryDealGetTicket(d);
            if(HistoryDealGetInteger(dTicket, DEAL_POSITION_ID) == (long)g_positionTicket &&
               HistoryDealGetInteger(dTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
               double profit   = HistoryDealGetDouble(dTicket, DEAL_PROFIT);
               double closeP   = HistoryDealGetDouble(dTicket, DEAL_PRICE);
               long   reason   = HistoryDealGetInteger(dTicket, DEAL_REASON);
               string reasonStr = (reason == DEAL_REASON_SL)     ? "SL"     :
                                  (reason == DEAL_REASON_TP)     ? "TP"     :
                                  (reason == DEAL_REASON_EXPERT) ? "EA"     : "MANUAL/OTRO";
               Print("[POSICION CERRADA] Ticket=", g_positionTicket,
                     " | Precio=", closeP,
                     " | Motivo=", reasonStr,
                     " | Profit=", DoubleToString(profit, 2),
                     " | Trailing fue activado=", (g_tpReached ? "SI" : "NO"));
               found = true;
               break;
            }
         }
         if(!found)
            Print("[POSICION CERRADA] Ticket=", g_positionTicket,
                  " | No encontrada en historial | Trailing fue activado=", (g_tpReached ? "SI" : "NO"));

         g_state = STATE_IDLE;
         g_positionTicket = 0;
         g_tpReached = false;
      }
   }
}

//+------------------------------------------------------------------+
//| OnTimer                                                           |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_state == STATE_ARMED && TimeCurrent() >= g_eventTime - InpLeadTimeSeconds)
   {
      if(PlaceStraddleOrders())
         g_state = STATE_ORDERS_PLACED;
      else
         g_state = STATE_IDLE;
   }
   UpdateUI();
}

//+------------------------------------------------------------------+
//| OnChartEvent — Click del botón CANCEL                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &l, const double &d, const string &s)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   // MINIMIZE — Colapsar/expandir panel
   if(s == BTN_MINIMIZE) { ToggleMinimize(); return; }

   // CANCEL ALL — Cerrar posiciones + borrar órdenes pendientes
   if(s == BTN_CANCEL)
   {
      // Borrar órdenes pendientes
      g_trade.OrderDelete(g_buyOrderTicket);
      g_trade.OrderDelete(g_sellOrderTicket);
      
      // Cerrar posición abierta si existe
      if(g_positionTicket != 0 && g_posInfo.SelectByTicket(g_positionTicket))
      {
         g_trade.PositionClose(g_positionTicket);
         Print("[CANCEL] Posición cerrada: ", g_positionTicket);
      }
      
      // Resetear estado
      g_state = STATE_IDLE;
      g_positionTicket = 0;
      g_tpReached = false;
      g_buyOrderTicket = 0;
      g_sellOrderTicket = 0;
      g_virtualTP = 0;
      
      Print("[CANCEL] Todo cancelado y reseteado");
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

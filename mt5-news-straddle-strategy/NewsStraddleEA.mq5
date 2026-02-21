//+------------------------------------------------------------------+
//|                                              NewsStraddleEA.mq5  |
//|      Pre-News Straddle (Standard Stops) + Trailing | v1.11       |
//|      Update: Auto-arm on init, single CANCEL button               |
//|                                        github.com/germancin      |
//+------------------------------------------------------------------+
#property copyright "germancin"
#property link      "https://github.com/germancin/system-claw"
#property version   "1.11"

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

            Print("[ENTRY] Posición detectada. Ticket: ", g_positionTicket);

            // Borrar la orden opuesta
            if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
               g_trade.OrderDelete(g_sellOrderTicket);
            else
               g_trade.OrderDelete(g_buyOrderTicket);

            // Poner TP si está ON. No tocamos SL.
            if(g_useTP) SetTakeProfitOnly();
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

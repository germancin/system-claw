//+------------------------------------------------------------------+
//|                                              NewsStraddleEA.mq5  |
//|      Pre-News Straddle (Standard Stops) + Trailing | v1.10       |
//|      Update: Separated into include files for clean code          |
//|                                        github.com/germancin      |
//+------------------------------------------------------------------+
#property copyright "germancin"
#property link      "https://github.com/germancin/system-claw"
#property version   "1.10"

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
//| OnChartEvent — Clicks de botones                                  |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &l, const double &d, const string &s)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   // ARMAR
   if(s == BTN_ARM)
   {
      g_eventTime = ParseEventTime(InpNewsTime);
      g_state = STATE_ARMED;
      Print("[UI] ARMADO para ", InpNewsTime);
   }

   // CANCELAR
   if(s == BTN_CANCEL)
   {
      g_trade.OrderDelete(g_buyOrderTicket);
      g_trade.OrderDelete(g_sellOrderTicket);
      g_state = STATE_IDLE;
      g_positionTicket = 0;
      g_tpReached = false;
      Print("[UI] CANCELADO");
   }

   // TP ON/OFF
   if(s == BTN_TP)
   {
      g_useTP = !g_useTP;
      ObjectSetString(0, BTN_TP, OBJPROP_TEXT, g_useTP ? "TP ON" : "TP OFF");
      ObjectSetInteger(0, BTN_TP, OBJPROP_BGCOLOR, g_useTP ? C'30,100,200' : clrGray);

      if(g_state == STATE_TRADE_ACTIVE)
      {
         if(g_useTP)
         {
            SetTakeProfitOnly();
         }
         else
         {
            // Quitar TP, dejar SL como esté (manual o 0)
            double keepSL = g_posInfo.SelectByTicket(g_positionTicket) ? g_posInfo.StopLoss() : 0;
            g_trade.PositionModify(g_positionTicket, keepSL, 0);
         }
      }
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

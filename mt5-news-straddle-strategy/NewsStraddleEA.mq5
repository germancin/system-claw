//+------------------------------------------------------------------+
//|                                              NewsStraddleEA.mq5  |
//|      Pre-News Straddle (Standard Stops) + Trailing | v1.02       |
//|      Update: Fixed immediate SL triggering (Trailing gap fix)    |
//|                                        github.com/germancin      |
//+------------------------------------------------------------------+
#property copyright "germancin"
#property link      "https://github.com/germancin/system-claw"
#property version   "1.02"
#property description "Pre-News Straddle EA with Trailing Stop"
#property description "Uses Standard Buy/Sell Stop orders"

//+------------------------------------------------------------------+
//| SECTION 1: Includes & Inputs                                      |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

input string InpNewsTime          = "08:30:00";   // Hora del evento (HH:MM:SS, hora del servidor)
input double InpEntryDistPips     = 15.0;         // Distancia de entrada en pips
input double InpTrailingPips      = 15.0;         // Distancia del Trailing Stop en pips (Aumentado para evitar saltos inmediatos)
input bool   InpUseTP             = false;        // Usar Take Profit (ON/OFF)
input double InpTPPips            = 30.0;         // Take Profit en pips (solo si TP activo)
input double InpLotSize           = 0.01;         // Tamaño de lote
input int    InpMagicNumber       = 202601;       // Magic Number único del EA
input int    InpLeadTimeSeconds   = 10;           // Segundos antes del evento para colocar órdenes

//+------------------------------------------------------------------+
//| SECTION 2: Global Variables & State Machine                       |
//+------------------------------------------------------------------+
enum ENUM_EA_STATE
{
   STATE_IDLE = 0,            // Esperando ARMAR
   STATE_ARMED,               // Evento programado, esperando T-10s
   STATE_ORDERS_PLACED,       // Órdenes colocadas
   STATE_TRADE_ACTIVE,        // Posición abierta, trailing activo
   STATE_DONE                 // Posición cerrada, listo para rearmar
};

ENUM_EA_STATE g_state = STATE_IDLE;
CTrade        g_trade;
CPositionInfo g_posInfo;
COrderInfo    g_orderInfo;

datetime      g_eventTime       = 0;       
ulong         g_buyOrderTicket  = 0;       
ulong         g_sellOrderTicket = 0;       
ulong         g_positionTicket  = 0;       
bool          g_useTP           = false;   
double        g_pipFactor       = 0;       

// Nombres de objetos UI
const string  BG_PANEL          = "NewsEA_BgPanel";
const string  BTN_ARM           = "NewsEA_BtnArm";
const string  BTN_CANCEL        = "NewsEA_BtnCancel";
const string  BTN_TP            = "NewsEA_BtnTP";
const string  LBL_STATE         = "NewsEA_LblState";
const string  LBL_EVENT         = "NewsEA_LblEvent";
const string  LBL_PARAMS        = "NewsEA_LblParams";
const string  LBL_TITLE         = "NewsEA_LblTitle";
const string  LBL_COUNTDOWN     = "NewsEA_LblCountdown";
const string  LBL_VOLINFO       = "NewsEA_LblVolInfo";
const string  LBL_STOPSINFO     = "NewsEA_LblStopsInfo";

const int     MAX_RETRIES       = 3;
const int     RETRY_SLEEP_MS    = 100;

//+------------------------------------------------------------------+
//| SECTION 3: Utility Functions                                      |
//+------------------------------------------------------------------+

double PipsToPrice(double pips)
{
   return NormalizeDouble(pips * g_pipFactor, _Digits);
}

void InitPipFactor()
{
   if(_Digits == 5 || _Digits == 3)
      g_pipFactor = 10.0 * _Point;   
   else
      g_pipFactor = _Point;          
}

datetime ParseEventTime(string timeStr)
{
   string parts[];
   int count = StringSplit(timeStr, ':', parts);
   if(count < 2) return 0;
   
   int hours   = (int)StringToInteger(parts[0]);
   int minutes = (int)StringToInteger(parts[1]);
   int seconds = (count >= 3) ? (int)StringToInteger(parts[2]) : 0;
   
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = hours;
   dt.min  = minutes;
   dt.sec  = seconds;
   return StructToTime(dt);
}

string StateToString(ENUM_EA_STATE state)
{
   switch(state)
   {
      case STATE_IDLE:           return "IDLE - Esperando ARMAR";
      case STATE_ARMED:          return "ARMED - Esperando T-" + IntegerToString(InpLeadTimeSeconds) + "s";
      case STATE_ORDERS_PLACED:  return "ORDERS PLACED - Monitoreando";
      case STATE_TRADE_ACTIVE:   return "TRADE ACTIVE - Trailing ON";
      case STATE_DONE:           return "DONE - Listo para rearmar";
      default:                   return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| SECTION 4: Order Management                                       |
//+------------------------------------------------------------------+

bool PlaceStraddleOrders()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist = PipsToPrice(InpEntryDistPips);
   
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * _Point;
   if(dist < minDist && stopsLevel > 0) dist = minDist * 1.1;
   
   double buyStopPrice  = NormalizeDouble(ask + dist, _Digits);
   double sellStopPrice  = NormalizeDouble(bid - dist, _Digits);
   
   double sl = 0;
   double tp = 0;
   
   Print("[INFO] Colocando Straddle: Buy Stop=", buyStopPrice, " Sell Stop=", sellStopPrice);
   
   // BUY
   bool buyPlaced = false;
   for(int i = 0; i < MAX_RETRIES; i++)
   {
      if(g_trade.BuyStop(InpLotSize, buyStopPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "NewsEA Buy"))
      {
         uint retcode = g_trade.ResultRetcode();
         if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED)
         {
            g_buyOrderTicket = g_trade.ResultOrder();
            buyPlaced = true;
            break;
         }
      }
      Sleep(RETRY_SLEEP_MS);
   }
   
   if(!buyPlaced) return false;
   
   // SELL
   bool sellPlaced = false;
   for(int i = 0; i < MAX_RETRIES; i++)
   {
      if(g_trade.SellStop(InpLotSize, sellStopPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "NewsEA Sell"))
      {
         uint retcode = g_trade.ResultRetcode();
         if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED)
         {
            g_sellOrderTicket = g_trade.ResultOrder();
            sellPlaced = true;
            break;
         }
      }
      Sleep(RETRY_SLEEP_MS);
   }
   
   if(!sellPlaced)
   {
      DeleteOrderSafe(g_buyOrderTicket);
      return false;
   }
   
   return true;
}

bool DeleteOrderSafe(ulong ticket)
{
   if(ticket == 0) return true;
   for(int i = 0; i < MAX_RETRIES; i++)
   {
      if(g_trade.OrderDelete(ticket)) return true;
      Sleep(RETRY_SLEEP_MS);
   }
   return false;
}

bool CheckForExecution()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Magic() == InpMagicNumber && g_posInfo.Symbol() == _Symbol)
         {
            g_positionTicket = g_posInfo.Ticket();
            if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
               DeleteOrderSafe(g_sellOrderTicket);
            else
               DeleteOrderSafe(g_buyOrderTicket);
               
            if(g_useTP) SetTakeProfit();
            
            // NO aplicar trailing inmediato para dejar respirar el precio al entrar
            return true;
         }
      }
   }
   return false;
}

void SetTakeProfit()
{
   if(g_positionTicket == 0 || !g_useTP) return;
   if(!g_posInfo.SelectByTicket(g_positionTicket)) return;
   double currentSL = g_posInfo.StopLoss();
   double openPrice = g_posInfo.PriceOpen();
   double tpDist    = PipsToPrice(InpTPPips);
   double newTP = (g_posInfo.PositionType() == POSITION_TYPE_BUY) ? openPrice + tpDist : openPrice - tpDist;
   g_trade.PositionModify(g_positionTicket, currentSL, NormalizeDouble(newTP, _Digits));
}

void CancelAll()
{
   DeleteOrderSafe(g_buyOrderTicket);
   DeleteOrderSafe(g_sellOrderTicket);
   g_positionTicket = 0;
}

//+------------------------------------------------------------------+
//| SECTION 5: Trailing Stop Logic (LA SOLUCION ESTA AQUI)            |
//+------------------------------------------------------------------+

void ApplyTrailingStop()
{
   if(g_positionTicket == 0) return;
   if(!g_posInfo.SelectByTicket(g_positionTicket)) return;
   
   double currentSL = g_posInfo.StopLoss();
   double currentTP = g_posInfo.TakeProfit();
   double openPrice = g_posInfo.PriceOpen();
   double trailDist = PipsToPrice(InpTrailingPips);
   double newSL     = 0;
   
   if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      newSL = NormalizeDouble(bid - trailDist, _Digits);
      
      // REGLA DE ORO: Solo poner el SL si el precio ya se movió a tu favor
      // Si el precio actual (bid) no es mayor que el precio de entrada + distancia, no ponemos SL todavía
      if(bid < openPrice + (trailDist * 0.5)) return; 

      if(newSL > currentSL || currentSL == 0)
      {
         g_trade.PositionModify(g_positionTicket, newSL, currentTP);
      }
   }
   else if(g_posInfo.PositionType() == POSITION_TYPE_SELL)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      newSL = NormalizeDouble(ask + trailDist, _Digits);
      
      if(ask > openPrice - (trailDist * 0.5)) return;

      if(newSL < currentSL || currentSL == 0)
      {
         g_trade.PositionModify(g_positionTicket, newSL, currentTP);
      }
   }
}

bool IsPositionOpen()
{
   if(g_positionTicket == 0) return false;
   return g_posInfo.SelectByTicket(g_positionTicket);
}

//+------------------------------------------------------------------+
//| SECTION 6: UI / Chart Objects                                     |
//+------------------------------------------------------------------+

void CreateBackgroundPanel(int x, int y, int width, int height)
{
   ObjectDelete(0, BG_PANEL);
   ObjectCreate(0, BG_PANEL, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, BG_PANEL, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, BG_PANEL, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, BG_PANEL, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, BG_PANEL, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, BG_PANEL, OBJPROP_BGCOLOR, C'25,25,35');
   ObjectSetInteger(0, BG_PANEL, OBJPROP_ZORDER, 50);
}

void CreateButton(string name, string text, int x, int y, int width, int height, color bgColor, color txtColor)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 100);
}

void CreateLabel(string name, string text, int x, int y, color txtColor, int fontSize = 9)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}

void InitUI()
{
   int baseX = 20; int baseY = 40;
   CreateBackgroundPanel(baseX - 10, baseY - 10, 340, 181);
   CreateButton(BTN_ARM, "▶ ARMAR", baseX, baseY, 100, 30, C'35,134,54', clrWhite);
   CreateButton(BTN_CANCEL, "■ CANCELAR", baseX+110, baseY, 100, 30, C'207,34,46', clrWhite);
   CreateButton(BTN_TP, "TP OFF", baseX+220, baseY, 100, 30, clrGray, clrWhite);
   CreateLabel(LBL_TITLE, "═══ NEWS STRADDLE EA ═══", baseX, baseY + 40, clrGold, 11);
   CreateLabel(LBL_STATE, "Estado: IDLE", baseX, baseY + 60, clrWhite);
   CreateLabel(LBL_EVENT, "Evento: " + InpNewsTime, baseX, baseY + 78, clrSilver);
   CreateLabel(LBL_COUNTDOWN, "", baseX, baseY + 96, clrYellow);
   ChartRedraw();
}

void UpdateUI()
{
   ObjectSetString(0, LBL_STATE, OBJPROP_TEXT, "Estado: " + StateToString(g_state));
   if(g_state == STATE_ARMED)
   {
      long secs = (long)(g_eventTime - TimeCurrent());
      ObjectSetString(0, LBL_COUNTDOWN, OBJPROP_TEXT, StringFormat("⏱ T-%02d:%02d", (int)(secs/60), (int)(secs%60)));
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| SECTION 7: Main Handlers                                          |
//+------------------------------------------------------------------+

int OnInit()
{
   InitPipFactor();
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_state = STATE_IDLE;
   g_useTP = InpUseTP;
   InitUI();
   EventSetMillisecondTimer(500);
   g_eventTime = ParseEventTime(InpNewsTime);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(g_state == STATE_ORDERS_PLACED)
   {
      if(CheckForExecution()) g_state = STATE_TRADE_ACTIVE;
   }
   if(g_state == STATE_TRADE_ACTIVE)
   {
      if(IsPositionOpen()) ApplyTrailingStop();
      else { g_state = STATE_DONE; CancelAll(); }
   }
}

void OnTimer()
{
   if(g_state == STATE_ARMED)
   {
      if(TimeCurrent() >= g_eventTime - InpLeadTimeSeconds)
      {
         if(PlaceStraddleOrders()) g_state = STATE_ORDERS_PLACED;
         else g_state = STATE_IDLE;
      }
   }
   UpdateUI();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(sparam == BTN_ARM) { g_eventTime = ParseEventTime(InpNewsTime); g_state = STATE_ARMED; }
   if(sparam == BTN_CANCEL) { CancelAll(); g_state = STATE_IDLE; }
}

void OnDeinit(const int reason) { EventKillTimer(); ObjectDelete(0, BG_PANEL); }

//+------------------------------------------------------------------+
//|                                              NewsStraddleEA.mq5  |
//|      Pre-News Straddle (Standard Stops) + Trailing | v1.09       |
//|      v1.08: Nuclear SL ban + Filling Mode + ForceSLZero          |
//|      v1.09: Restored full UI panel (labels, countdown, colors)   |
//|                                        github.com/germancin      |
//+------------------------------------------------------------------+
#property copyright "germancin"
#property link      "https://github.com/germancin/system-claw"
#property version   "1.09"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

input string InpNewsTime          = "08:30:00";
input double InpEntryDistPips     = 15.0;
input double InpTrailingPips      = 15.0;
input bool   InpUseTP             = false;
input double InpTPPips            = 30.0;
input double InpLotSize           = 0.01;
input int    InpMagicNumber       = 202601;
input int    InpLeadTimeSeconds   = 10;

enum ENUM_EA_STATE { STATE_IDLE, STATE_ARMED, STATE_ORDERS_PLACED, STATE_TRADE_ACTIVE, STATE_DONE };
ENUM_EA_STATE g_state = STATE_IDLE;
CTrade g_trade;
CPositionInfo g_posInfo;
COrderInfo g_orderInfo;
datetime g_eventTime = 0; ulong g_buyOrderTicket = 0; ulong g_sellOrderTicket = 0; ulong g_positionTicket = 0;
bool g_useTP = false; double g_pipFactor = 0;
bool g_tpReached = false; 

const string BG_PANEL="Bg", BTN_ARM="Arm", BTN_CANCEL="Can", BTN_TP="Tp", LBL_STATE="St", LBL_COUNT="Co";

double PipsToPrice(double pips) { return NormalizeDouble(pips * g_pipFactor, _Digits); }
void InitPipFactor() { g_pipFactor = (_Digits==5 || _Digits==3) ? 10.0*_Point : _Point; }

datetime ParseEventTime(string t) {
   string p[]; StringSplit(t,':',p); MqlDateTime dt; TimeCurrent(dt);
   dt.hour=(int)StringToInteger(p[0]); dt.min=(int)StringToInteger(p[1]);
   dt.sec=(int)p.Size()>=3?(int)StringToInteger(p[2]):0; return StructToTime(dt);
}

bool PlaceStraddleOrders() {
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK), bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double dist=PipsToPrice(InpEntryDistPips);
   double bS=NormalizeDouble(ask+dist,_Digits), sS=NormalizeDouble(bid-dist,_Digits);
   if(!g_trade.BuyStop(InpLotSize,bS,_Symbol,0,0)) return false;
   g_buyOrderTicket=g_trade.ResultOrder();
   if(!g_trade.SellStop(InpLotSize,sS,_Symbol,0,0)) { g_trade.OrderDelete(g_buyOrderTicket); return false; }
   g_sellOrderTicket=g_trade.ResultOrder();
   return true;
}

//+------------------------------------------------------------------+
//| FORCE SL TO ZERO - The nuclear option                             |
//| This function ONLY sets SL=0, preserving whatever TP exists       |
//+------------------------------------------------------------------+
void ForceSLZero()
{
   if(g_positionTicket == 0) return;
   if(!g_posInfo.SelectByTicket(g_positionTicket)) return;
   double currentSL = g_posInfo.StopLoss();
   double currentTP = g_posInfo.TakeProfit();
   
   if(currentSL != 0)
   {
      Print("[NUCLEAR] SL detectado en ", currentSL, " — FORZANDO A CERO");
      for(int i = 0; i < 5; i++)
      {
         if(g_trade.PositionModify(g_positionTicket, 0, currentTP))
         {
            if(g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
            {
               Print("[NUCLEAR] SL eliminado exitosamente");
               return;
            }
         }
         Print("[NUCLEAR] Reintento ", i+1, " Code: ", g_trade.ResultRetcode());
         Sleep(50);
      }
      Print("[NUCLEAR] FALLO al eliminar SL después de 5 intentos");
   }
}

void SetTakeProfitOnly() {
   if(g_positionTicket==0 || !g_useTP) return;
   if(!g_posInfo.SelectByTicket(g_positionTicket)) return;
   double tpD=PipsToPrice(InpTPPips), openP=g_posInfo.PriceOpen();
   double tp=(g_posInfo.PositionType()==POSITION_TYPE_BUY)?openP+tpD:openP-tpD;
   double tpNorm = NormalizeDouble(tp,_Digits);
   
   Print("[TP] Poniendo TP en ", tpNorm, " con SL=0");
   
   for(int i = 0; i < 5; i++)
   {
      if(g_trade.PositionModify(g_positionTicket, 0, tpNorm))
      {
         if(g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
         {
            Print("[TP] TP puesto exitosamente. Verificando SL...");
            // INMEDIATAMENTE verificar que el SL siga en 0
            ForceSLZero();
            return;
         }
      }
      Print("[TP] Reintento ", i+1, " Code: ", g_trade.ResultRetcode());
      Sleep(50);
   }
}

void ManageTrade() {
   if(g_positionTicket==0 || !g_posInfo.SelectByTicket(g_positionTicket)) return;
   
   // ============================================================
   // REGLA 1: Si TP está OFF → SL debe ser 0 SIEMPRE. Punto.
   // ============================================================
   if(!g_useTP)
   {
      ForceSLZero();
      return;
   }

   // ============================================================
   // REGLA 2: TP está ON. Asegurar que el TP esté puesto.
   // ============================================================
   double curTP = g_posInfo.TakeProfit();
   if(curTP == 0) { SetTakeProfitOnly(); return; }

   // ============================================================
   // REGLA 3: ¿Ya tocó el TP? Solo entonces nace el Trailing.
   // ============================================================
   if(g_posInfo.PositionType()==POSITION_TYPE_BUY) {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(!g_tpReached && bid >= curTP) {
         g_tpReached = true;
         Print("[TRAILING] TP ALCANZADO en BUY. Activando trailing ahora.");
      }
   } else {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(!g_tpReached && ask <= curTP) {
         g_tpReached = true;
         Print("[TRAILING] TP ALCANZADO en SELL. Activando trailing ahora.");
      }
   }

   // ============================================================
   // REGLA 4: Si NO ha tocado TP → FORZAR SL=0. No importa qué.
   // ============================================================
   if(!g_tpReached)
   {
      ForceSLZero();
      return;
   }

   // ============================================================
   // REGLA 5: SOLO AQUÍ NACE EL TRAILING (después de tocar TP)
   // ============================================================
   double curSL=g_posInfo.StopLoss(), trailD=PipsToPrice(InpTrailingPips);
   
   if(g_posInfo.PositionType()==POSITION_TYPE_BUY) {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double newSL=NormalizeDouble(bid-trailD,_Digits);
      if(newSL>curSL || curSL==0) {
         g_trade.PositionModify(g_positionTicket, newSL, curTP);
         Print("[TRAILING] BUY SL movido a ", newSL);
      }
   } else {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double newSL=NormalizeDouble(ask+trailD,_Digits);
      if(newSL<curSL || curSL==0) {
         g_trade.PositionModify(g_positionTicket, newSL, curTP);
         Print("[TRAILING] SELL SL movido a ", newSL);
      }
   }
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
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 100);
}

void CreateLabel(string name, string text, int x, int y, color txtColor, int fontSize = 9)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtColor);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

string StateToString(ENUM_EA_STATE state)
{
   switch(state)
   {
      case STATE_IDLE:           return("IDLE - Esperando ARMAR");
      case STATE_ARMED:          return("ARMED - Esperando T-" + IntegerToString(InpLeadTimeSeconds) + "s");
      case STATE_ORDERS_PLACED:  return("ORDERS PLACED - Monitoreando");
      case STATE_TRADE_ACTIVE:   return("TRADE ACTIVE - Trailing ON");
      case STATE_DONE:           return("DONE - Listo para rearmar");
      default:                   return("UNKNOWN");
   }
}

void InitUI()
{
   int baseX = 20, baseY = 40;
   
   // Background Panel
   ObjectDelete(0, BG_PANEL);
   ObjectCreate(0, BG_PANEL, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, BG_PANEL, OBJPROP_XDISTANCE, baseX - 10);
   ObjectSetInteger(0, BG_PANEL, OBJPROP_YDISTANCE, baseY - 10);
   ObjectSetInteger(0, BG_PANEL, OBJPROP_XSIZE, 340);
   ObjectSetInteger(0, BG_PANEL, OBJPROP_YSIZE, 181);
   ObjectSetInteger(0, BG_PANEL, OBJPROP_BGCOLOR, C'25,25,35');
   ObjectSetInteger(0, BG_PANEL, OBJPROP_BORDER_COLOR, C'60,60,80');
   ObjectSetInteger(0, BG_PANEL, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, BG_PANEL, OBJPROP_ZORDER, 50);
   
   // Buttons
   CreateButton(BTN_ARM, "▶ ARMAR", baseX, baseY, 100, 30, C'35,134,54', clrWhite);
   CreateButton(BTN_CANCEL, "■ CANCELAR", baseX + 110, baseY, 100, 30, C'207,34,46', clrWhite);
   CreateButton(BTN_TP, "TP OFF", baseX + 220, baseY, 100, 30, clrGray, clrWhite);
   
   // Labels
   CreateLabel("NewsEA_Title", "═══ NEWS STRADDLE EA v1.08 ═══", baseX, baseY + 40, clrGold, 11);
   CreateLabel(LBL_STATE, "Estado: IDLE", baseX, baseY + 62, clrWhite, 9);
   CreateLabel("NewsEA_Event", "Evento: " + InpNewsTime, baseX, baseY + 80, clrSilver, 9);
   CreateLabel(LBL_COUNT, "", baseX, baseY + 98, clrYellow, 9);
   CreateLabel("NewsEA_Params", StringFormat("Dist: %.1f | Trail: %.1f | TP: %.1f pips", InpEntryDistPips, InpTrailingPips, InpTPPips), baseX, baseY + 116, C'100,200,255', 8);
   CreateLabel("NewsEA_Rule", "Regla: SL=0 hasta que TP sea tocado", baseX, baseY + 134, C'255,200,100', 8);
   
   ChartRedraw();
}

void UpdateUI()
{
   ObjectSetString(0, LBL_STATE, OBJPROP_TEXT, "Estado: " + StateToString(g_state));
   
   if(g_state == STATE_ARMED && g_eventTime > 0)
   {
      long secs = (long)(g_eventTime - TimeCurrent());
      if(secs > 0)
         ObjectSetString(0, LBL_COUNT, OBJPROP_TEXT, StringFormat("⏱ T-%02d:%02d", (int)(secs/60), (int)(secs%60)));
      else
         ObjectSetString(0, LBL_COUNT, OBJPROP_TEXT, "⏱ COLOCANDO ORDENES...");
   }
   else if(g_state == STATE_TRADE_ACTIVE)
   {
      string tpStatus = g_tpReached ? "TRAILING ACTIVO" : (g_useTP ? "Esperando TP..." : "SIN TP - Libre");
      ObjectSetString(0, LBL_COUNT, OBJPROP_TEXT, tpStatus);
   }
   else
   {
      ObjectSetString(0, LBL_COUNT, OBJPROP_TEXT, "");
   }
   
   ChartRedraw();
}

int OnInit() {
   InitPipFactor();
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(50);
   
   // CRITICO: Detectar filling mode del broker para que PositionModify funcione
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

void OnTick() {
   if(g_state==STATE_ORDERS_PLACED) {
      for(int i=PositionsTotal()-1;i>=0;i--) if(g_posInfo.SelectByIndex(i) && g_posInfo.Magic()==InpMagicNumber) {
         g_positionTicket=g_posInfo.Ticket(); g_state=STATE_TRADE_ACTIVE; g_tpReached = false;
         Print("[ENTRY] Posición detectada. Ticket: ", g_positionTicket);
         if(g_posInfo.PositionType()==POSITION_TYPE_BUY) g_trade.OrderDelete(g_sellOrderTicket); else g_trade.OrderDelete(g_buyOrderTicket);
         
         // Poner TP si está ON, y FORZAR SL=0 inmediatamente
         if(g_useTP) SetTakeProfitOnly();
         ForceSLZero(); // SIEMPRE forzar SL=0 al entrar
      }
   }
   if(g_state==STATE_TRADE_ACTIVE) {
      if(g_posInfo.SelectByTicket(g_positionTicket)) ManageTrade();
      else { g_state=STATE_IDLE; g_positionTicket=0; g_tpReached = false; }
   }
}

void OnTimer() {
   if(g_state==STATE_ARMED && TimeCurrent()>=g_eventTime-InpLeadTimeSeconds) {
      if(PlaceStraddleOrders()) g_state=STATE_ORDERS_PLACED;
      else g_state=STATE_IDLE;
   }
   UpdateUI();
}

void OnChartEvent(const int id,const long &l,const double &d,const string &s) {
   if(id==CHARTEVENT_OBJECT_CLICK) {
      if(s==BTN_ARM) { g_eventTime=ParseEventTime(InpNewsTime); g_state=STATE_ARMED; Print("[UI] ARMADO para ", InpNewsTime); }
      if(s==BTN_CANCEL) { g_trade.OrderDelete(g_buyOrderTicket); g_trade.OrderDelete(g_sellOrderTicket); g_state=STATE_IDLE; g_positionTicket=0; g_tpReached=false; Print("[UI] CANCELADO"); }
      if(s==BTN_TP) {
         g_useTP=!g_useTP;
         ObjectSetString(0,BTN_TP,OBJPROP_TEXT,g_useTP?"TP ON":"TP OFF");
         ObjectSetInteger(0,BTN_TP,OBJPROP_BGCOLOR,g_useTP?C'30,100,200':clrGray);
         if(g_state==STATE_TRADE_ACTIVE) {
            if(g_useTP) {
               SetTakeProfitOnly();  // Pone TP con SL=0
               ForceSLZero();        // DOBLE SEGURO: forzar SL=0 otra vez
            } else {
               // Quitar todo
               g_trade.PositionModify(g_positionTicket, 0, 0);
               ForceSLZero();        // TRIPLE SEGURO
            }
         }
      }
   }
}

void OnDeinit(const int r) { ObjectsDeleteAll(0, "NewsEA"); ObjectDelete(0, BG_PANEL); ObjectDelete(0, BTN_ARM); ObjectDelete(0, BTN_CANCEL); ObjectDelete(0, BTN_TP); ObjectDelete(0, LBL_STATE); ObjectDelete(0, LBL_COUNT); EventKillTimer(); }

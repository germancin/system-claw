//+------------------------------------------------------------------+
//|                                              NewsStraddleEA.mq5  |
//|      Pre-News Straddle (Standard Stops) + Trailing | v1.06       |
//|      Update: FORCED ZERO SL UNTIL TP TOUCHED + FIX TP SEND       |
//|                                        github.com/germancin      |
//+------------------------------------------------------------------+
#property copyright "germancin"
#property link      "https://github.com/germancin/system-claw"
#property version   "1.06"

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
bool g_tpReached = false; // Flag crítica para saber si ya tocamos el TP una vez

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
   // Órdenes sin SL ni TP (se ponen al abrir la posición)
   if(!g_trade.BuyStop(InpLotSize,bS,_Symbol,0,0)) return false;
   g_buyOrderTicket=g_trade.ResultOrder();
   if(!g_trade.SellStop(InpLotSize,sS,_Symbol,0,0)) { g_trade.OrderDelete(g_buyOrderTicket); return false; }
   g_sellOrderTicket=g_trade.ResultOrder();
   return true;
}

void SetTakeProfitOnly() {
   if(g_positionTicket==0 || !g_useTP) return;
   if(!g_posInfo.SelectByTicket(g_positionTicket)) return;
   double tpD=PipsToPrice(InpTPPips), openP=g_posInfo.PriceOpen();
   double tp=(g_posInfo.PositionType()==POSITION_TYPE_BUY)?openP+tpD:openP-tpD;
   // MANDAR EL TP SOLO. El SL se queda en 0.
   g_trade.PositionModify(g_positionTicket, 0, NormalizeDouble(tp,_Digits));
}

void ApplyTrailingStop() {
   if(g_positionTicket==0 || !g_posInfo.SelectByTicket(g_positionTicket)) return;
   
   double curSL=g_posInfo.StopLoss(), openP=g_posInfo.PriceOpen(), trailD=PipsToPrice(InpTrailingPips), curTP=g_posInfo.TakeProfit();
   
   // SI NO HAY TP DEFINIDO (BOTON OFF), NO HACEMOS NI VERGA.
   if(curTP == 0) return; 

   if(g_posInfo.PositionType()==POSITION_TYPE_BUY) {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      // REGLA: Si el precio todavía no ha llegado al TP, el SL debe seguir siendo 0.
      if(!g_tpReached && bid >= curTP) g_tpReached = true; 
      
      if(!g_tpReached) {
         if(curSL != 0) g_trade.PositionModify(g_positionTicket, 0, curTP); // FORZAR SL 0 SI EL BROKER PONE ALGO
         return;
      }
      
      // SOLO SI YA TOCAMOS EL TP, ACTIVAMOS TRAILING
      double newSL=NormalizeDouble(bid-trailD,_Digits);
      if(newSL>curSL || curSL==0) g_trade.PositionModify(g_positionTicket, newSL, curTP);
   } else {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(!g_tpReached && ask <= curTP) g_tpReached = true;

      if(!g_tpReached) {
         if(curSL != 0) g_trade.PositionModify(g_positionTicket, 0, curTP);
         return;
      }

      double newSL=NormalizeDouble(ask+trailD,_Digits);
      if(newSL<curSL || curSL==0) g_trade.PositionModify(g_positionTicket, newSL, curTP);
   }
}

void InitUI() {
   ObjectCreate(0,BG_PANEL,OBJ_RECTANGLE_LABEL,0,0,0); ObjectSetInteger(0,BG_PANEL,OBJPROP_XSIZE,340); ObjectSetInteger(0,BG_PANEL,OBJPROP_YSIZE,150);
   ObjectSetInteger(0,BG_PANEL,OBJPROP_BGCOLOR,C'25,25,35'); ObjectSetInteger(0,BG_PANEL,OBJPROP_XDISTANCE,20); ObjectSetInteger(0,BG_PANEL,OBJPROP_YDISTANCE,40);
   ObjectCreate(0,BTN_ARM,OBJ_BUTTON,0,0,0); ObjectSetString(0,BTN_ARM,OBJPROP_TEXT,"▶ ARMAR"); ObjectSetInteger(0,BTN_ARM,OBJPROP_XDISTANCE,30); ObjectSetInteger(0,BTN_ARM,OBJPROP_YDISTANCE,50);
   ObjectSetInteger(0,BTN_ARM,OBJPROP_XSIZE,100); ObjectSetInteger(0,BTN_ARM,OBJPROP_YSIZE,30);
   ObjectCreate(0,BTN_TP,OBJ_BUTTON,0,0,0); ObjectSetString(0,BTN_TP,OBJPROP_TEXT,"TP OFF"); ObjectSetInteger(0,BTN_TP,OBJPROP_XDISTANCE,240); ObjectSetInteger(0,BTN_TP,OBJPROP_YDISTANCE,50);
   ObjectSetInteger(0,BTN_TP,OBJPROP_XSIZE,80); ObjectSetInteger(0,BTN_TP,OBJPROP_YSIZE,30);
}

int OnInit() { InitPipFactor(); g_trade.SetExpertMagicNumber(InpMagicNumber); g_useTP=InpUseTP; InitUI(); EventSetMillisecondTimer(500); return INIT_SUCCEEDED; }
void OnTick() {
   if(g_state==STATE_ORDERS_PLACED) {
      for(int i=PositionsTotal()-1;i>=0;i--) if(g_posInfo.SelectByIndex(i) && g_posInfo.Magic()==InpMagicNumber) {
         g_positionTicket=g_posInfo.Ticket(); g_state=STATE_TRADE_ACTIVE; g_tpReached = false;
         if(g_posInfo.PositionType()==POSITION_TYPE_BUY) g_trade.OrderDelete(g_sellOrderTicket); else g_trade.OrderDelete(g_buyOrderTicket);
         if(g_useTP) SetTakeProfitOnly();
      }
   }
   if(g_state==STATE_TRADE_ACTIVE) {
      if(g_posInfo.SelectByTicket(g_positionTicket)) ApplyTrailingStop();
      else { g_state=STATE_IDLE; g_positionTicket=0; g_tpReached = false; }
   }
}
void OnTimer() { if(g_state==STATE_ARMED && TimeCurrent()>=g_eventTime-InpLeadTimeSeconds) { if(PlaceStraddleOrders()) g_state=STATE_ORDERS_PLACED; else g_state=STATE_IDLE; } }
void OnChartEvent(const int id,const long &l,const double &d,const string &s) {
   if(id==CHARTEVENT_OBJECT_CLICK) {
      if(s==BTN_ARM) { g_eventTime=ParseEventTime(InpNewsTime); g_state=STATE_ARMED; }
      if(s==BTN_TP) { g_useTP=!g_useTP; ObjectSetString(0,BTN_TP,OBJPROP_TEXT,g_useTP?"TP ON":"TP OFF"); ObjectSetInteger(0,BTN_TP,OBJPROP_BGCOLOR,g_useTP?C'30,100,200':clrGray); if(g_state==STATE_TRADE_ACTIVE) SetTakeProfitOnly(); }
   }
}
void OnDeinit(const int r) { ObjectsDeleteAll(0); EventKillTimer(); }

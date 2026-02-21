//+------------------------------------------------------------------+
//| Globals.mqh — Variables globales, estados y utilidades             |
//+------------------------------------------------------------------+

enum ENUM_EA_STATE { STATE_IDLE, STATE_ARMED, STATE_ORDERS_PLACED, STATE_TRADE_ACTIVE, STATE_DONE };

ENUM_EA_STATE g_state = STATE_IDLE;
CTrade        g_trade;
CPositionInfo g_posInfo;
COrderInfo    g_orderInfo;

datetime g_eventTime       = 0;
ulong    g_buyOrderTicket  = 0;
ulong    g_sellOrderTicket = 0;
ulong    g_positionTicket  = 0;
bool     g_useTP           = false;
double   g_pipFactor       = 0;
bool     g_tpReached       = false;
double   g_virtualTP       = 0;  // TP Virtual (no va al broker, solo monitoreo interno)

//--- Utilidades
double PipsToPrice(double pips) { return NormalizeDouble(pips * g_pipFactor, _Digits); }

void InitPipFactor()
{
   g_pipFactor = (_Digits == 5 || _Digits == 3) ? 10.0 * _Point : _Point;
}

datetime ParseEventTime(string t)
{
   string p[];
   StringSplit(t, ':', p);
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = (int)StringToInteger(p[0]);
   dt.min  = (int)StringToInteger(p[1]);
   dt.sec  = ArraySize(p) >= 3 ? (int)StringToInteger(p[2]) : 0;
   return StructToTime(dt);
}

string StateToString(ENUM_EA_STATE state)
{
   switch(state)
   {
      case STATE_IDLE:           return("IDLE - Esperando ARMAR");
      case STATE_ARMED:          return("ARMED - Esperando T-" + IntegerToString(InpLeadTimeSeconds) + "s");
      case STATE_ORDERS_PLACED:  return("ORDERS PLACED - Monitoreando");
      case STATE_TRADE_ACTIVE:   return("TRADE ACTIVE");
      case STATE_DONE:           return("DONE - Listo para rearmar");
      default:                   return("UNKNOWN");
   }
}

//+------------------------------------------------------------------+
//|                                              NewsStraddleEA.mq5  |
//|                    Pre-News Stop-Limit Straddle (10s) + Trailing |
//|                                        github.com/germancin      |
//+------------------------------------------------------------------+
#property copyright "germancin"
#property link      "https://github.com/germancin/system-claw"
#property version   "1.00"
#property description "Pre-News Stop-Limit Straddle EA with Trailing Stop"
#property description "Places Buy/Sell Stop-Limit orders before news events"

//+------------------------------------------------------------------+
//| SECTION 1: Includes & Inputs                                      |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

input string InpNewsTime          = "08:30:00";   // Hora del evento (HH:MM:SS, hora del servidor)
input double InpEntryDistPips     = 15.0;         // Distancia de entrada en pips
input double InpTrailingPips      = 5.0;          // Distancia del Trailing Stop en pips
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
   STATE_ORDERS_PLACED,       // Órdenes Stop-Limit colocadas
   STATE_TRADE_ACTIVE,        // Posición abierta, trailing activo
   STATE_DONE                 // Posición cerrada, listo para rearmar
};

ENUM_EA_STATE g_state = STATE_IDLE;
CTrade        g_trade;
CPositionInfo g_posInfo;
COrderInfo    g_orderInfo;

datetime      g_eventTime       = 0;       // Hora del evento parseada
ulong         g_buyOrderTicket  = 0;       // Ticket de la orden Buy Stop-Limit
ulong         g_sellOrderTicket = 0;       // Ticket de la orden Sell Stop-Limit
ulong         g_positionTicket  = 0;       // Ticket de la posición activa
bool          g_useTP           = false;   // Estado actual del toggle TP
double        g_pipFactor       = 0;       // Factor de conversión de pips

// Nombres de objetos UI
const string  BTN_ARM           = "NewsEA_BtnArm";
const string  BTN_CANCEL        = "NewsEA_BtnCancel";
const string  BTN_TP            = "NewsEA_BtnTP";
const string  LBL_STATE         = "NewsEA_LblState";
const string  LBL_EVENT         = "NewsEA_LblEvent";
const string  LBL_PARAMS        = "NewsEA_LblParams";
const string  LBL_TITLE         = "NewsEA_LblTitle";
const string  LBL_COUNTDOWN     = "NewsEA_LblCountdown";

// Constantes de reintentos
const int     MAX_RETRIES       = 3;
const int     RETRY_SLEEP_MS    = 100;

// Fallback: usar Stop orders si Stop-Limit no está disponible
bool          g_useStopLimit    = true;    // true = Stop-Limit, false = Stop (fallback)

//+------------------------------------------------------------------+
//| SECTION 3: Utility Functions                                      |
//+------------------------------------------------------------------+

//--- Conversión de pips a precio según el símbolo
double PipsToPrice(double pips)
{
   return NormalizeDouble(pips * g_pipFactor, _Digits);
}

//--- Inicializar el factor de conversión de pips
void InitPipFactor()
{
   if(_Digits == 5 || _Digits == 3)
      g_pipFactor = 10.0 * _Point;   // Forex estándar y JPY
   else
      g_pipFactor = _Point;          // Índices, metales, CFDs
}

//--- Parsear hora HH:MM:SS a datetime del día actual
datetime ParseEventTime(string timeStr)
{
   string parts[];
   int count = StringSplit(timeStr, ':', parts);
   
   if(count < 2)
   {
      Print("[ERROR] ParseEventTime: Formato inválido '", timeStr, "'. Usar HH:MM:SS");
      return 0;
   }
   
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

//--- Obtener nombre del estado como string
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

//--- Validar que el símbolo soporta Stop-Limit orders
bool ValidateSymbolOrderMode()
{
   long orderMode = SymbolInfoInteger(_Symbol, SYMBOL_ORDER_MODE);
   
   if((orderMode & SYMBOL_ORDER_STOP_LIMIT) == 0)
   {
      Print("[ERROR] El símbolo ", _Symbol, " NO soporta órdenes Stop-Limit");
      return false;
   }
   return true;
}

//--- Validar el tamaño de lote
bool ValidateLotSize()
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(InpLotSize < minLot || InpLotSize > maxLot)
   {
      Print("[ERROR] LotSize ", InpLotSize, " fuera de rango [", minLot, " - ", maxLot, "]");
      return false;
   }
   
   // Validar que el lote es múltiplo del step
   double remainder = MathMod(InpLotSize, stepLot);
   if(remainder > 0.0000001)
   {
      Print("[WARNING] LotSize ", InpLotSize, " no es múltiplo de ", stepLot, ". Ajustar.");
   }
   return true;
}

//--- Validar distancia mínima de stops del broker
bool ValidateStopsLevel(double distPips)
{
   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double stopsPoints = stopsLevel * _Point;
   double distPrice = PipsToPrice(distPips);
   
   if(stopsLevel > 0 && distPrice < stopsPoints)
   {
      Print("[WARNING] Distancia ", distPips, " pips (", distPrice, ") menor que STOPS_LEVEL del broker (",
            stopsLevel, " points = ", stopsPoints, ")");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| SECTION 4: Order Management                                       |
//+------------------------------------------------------------------+

//--- Colocar las dos órdenes Stop-Limit (straddle)
bool PlaceStraddleOrders()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double dist = PipsToPrice(InpEntryDistPips);
   
   // Buy Stop-Limit: stopPrice y limitPrice arriba del Ask
   double buyStopPrice  = NormalizeDouble(ask + dist, _Digits);
   double buyLimitPrice = buyStopPrice;  // Ejecución al toque
   
   // Sell Stop-Limit: stopPrice y limitPrice abajo del Bid
   double sellStopPrice  = NormalizeDouble(bid - dist, _Digits);
   double sellLimitPrice = sellStopPrice;  // Ejecución al toque
   
   // SL y TP iniciales (0 = sin SL/TP al colocar la orden pendiente)
   double sl = 0;
   double tp = 0;
   
   Print("[INFO] Colocando Straddle: Ask=", ask, " Bid=", bid, " Dist=", dist);
   Print("[INFO] Buy Stop-Limit: Stop=", buyStopPrice, " Limit=", buyLimitPrice);
   Print("[INFO] Sell Stop-Limit: Stop=", sellStopPrice, " Limit=", sellLimitPrice);
   
   // Determinar tipo de orden según soporte del broker
   ENUM_ORDER_TYPE buyType, sellType;
   string orderMode;
   
   if(g_useStopLimit)
   {
      buyType  = ORDER_TYPE_BUY_STOP_LIMIT;
      sellType = ORDER_TYPE_SELL_STOP_LIMIT;
      orderMode = "Stop-Limit";
   }
   else
   {
      buyType  = ORDER_TYPE_BUY_STOP;
      sellType = ORDER_TYPE_SELL_STOP;
      orderMode = "Stop (fallback)";
   }
   
   Print("[INFO] Modo de órdenes: ", orderMode);
   
   // --- Colocar Buy order con reintentos
   bool buyPlaced = false;
   for(int i = 0; i < MAX_RETRIES; i++)
   {
      bool result = false;
      
      if(g_useStopLimit)
      {
         result = g_trade.OrderOpen(_Symbol, buyType, InpLotSize,
                           buyLimitPrice, buyStopPrice, sl, tp,
                           ORDER_TIME_GTC, 0, "NewsEA Buy");
      }
      else
      {
         // Buy Stop: solo necesita el precio de activación
         result = g_trade.BuyStop(InpLotSize, buyStopPrice, _Symbol, sl, tp,
                          ORDER_TIME_GTC, 0, "NewsEA Buy");
      }
      
      uint retcode = g_trade.ResultRetcode();
      if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED)
      {
         g_buyOrderTicket = g_trade.ResultOrder();
         Print("[OK] Buy ", orderMode, " colocada. Ticket: ", g_buyOrderTicket);
         buyPlaced = true;
         break;
      }
      
      Print("[RETRY ", i+1, "/", MAX_RETRIES, "] Buy falló. Code: ", retcode,
            " Desc: ", g_trade.ResultRetcodeDescription());
      
      if(retcode != TRADE_RETCODE_REQUOTE && retcode != TRADE_RETCODE_PRICE_OFF)
         break;  // Error no recuperable
      
      Sleep(RETRY_SLEEP_MS);
   }
   
   if(!buyPlaced)
   {
      Print("[ERROR] No se pudo colocar Buy después de ", MAX_RETRIES, " intentos");
      return false;
   }
   
   // --- Colocar Sell order con reintentos
   bool sellPlaced = false;
   for(int i = 0; i < MAX_RETRIES; i++)
   {
      bool result = false;
      
      if(g_useStopLimit)
      {
         result = g_trade.OrderOpen(_Symbol, sellType, InpLotSize,
                           sellLimitPrice, sellStopPrice, sl, tp,
                           ORDER_TIME_GTC, 0, "NewsEA Sell");
      }
      else
      {
         // Sell Stop: solo necesita el precio de activación
         result = g_trade.SellStop(InpLotSize, sellStopPrice, _Symbol, sl, tp,
                           ORDER_TIME_GTC, 0, "NewsEA Sell");
      }
      
      uint retcode = g_trade.ResultRetcode();
      if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED)
      {
         g_sellOrderTicket = g_trade.ResultOrder();
         Print("[OK] Sell ", orderMode, " colocada. Ticket: ", g_sellOrderTicket);
         sellPlaced = true;
         break;
      }
      
      Print("[RETRY ", i+1, "/", MAX_RETRIES, "] Sell falló. Code: ", retcode,
            " Desc: ", g_trade.ResultRetcodeDescription());
      
      if(retcode != TRADE_RETCODE_REQUOTE && retcode != TRADE_RETCODE_PRICE_OFF)
         break;
      
      Sleep(RETRY_SLEEP_MS);
   }
   
   if(!sellPlaced)
   {
      Print("[ERROR] No se pudo colocar Sell. Eliminando Buy pendiente...");
      DeleteOrderSafe(g_buyOrderTicket);
      g_buyOrderTicket = 0;
      return false;
   }
   
   return true;
}

//--- Eliminar una orden pendiente de forma segura con reintentos
bool DeleteOrderSafe(ulong ticket)
{
   if(ticket == 0) return true;
   
   for(int i = 0; i < MAX_RETRIES; i++)
   {
      if(g_trade.OrderDelete(ticket))
      {
         uint retcode = g_trade.ResultRetcode();
         if(retcode == TRADE_RETCODE_DONE)
         {
            Print("[OK] Orden ", ticket, " eliminada correctamente");
            return true;
         }
      }
      
      Print("[RETRY ", i+1, "/", MAX_RETRIES, "] Fallo al eliminar orden ", ticket,
            " Code: ", g_trade.ResultRetcode());
      Sleep(RETRY_SLEEP_MS);
   }
   
   Print("[ERROR] No se pudo eliminar orden ", ticket, " después de ", MAX_RETRIES, " intentos");
   return false;
}

//--- Verificar si alguna orden se convirtió en posición
bool CheckForExecution()
{
   // Escanear posiciones filtrando por Magic Number y símbolo
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_posInfo.SelectByIndex(i))
      {
         if(g_posInfo.Magic() == InpMagicNumber && g_posInfo.Symbol() == _Symbol)
         {
            g_positionTicket = g_posInfo.Ticket();
            
            ENUM_POSITION_TYPE posType = g_posInfo.PositionType();
            Print("[INFO] Posición detectada. Ticket: ", g_positionTicket,
                  " Tipo: ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"));
            
            // Eliminar la orden contraria
            if(posType == POSITION_TYPE_BUY)
            {
               Print("[INFO] Eliminando orden Sell pendiente...");
               DeleteOrderSafe(g_sellOrderTicket);
               g_sellOrderTicket = 0;
            }
            else
            {
               Print("[INFO] Eliminando orden Buy pendiente...");
               DeleteOrderSafe(g_buyOrderTicket);
               g_buyOrderTicket = 0;
            }
            
            // Establecer TP si está activo
            if(g_useTP)
               SetTakeProfit();
            
            // Aplicar trailing stop inicial
            ApplyTrailingStop();
            
            return true;
         }
      }
   }
   return false;
}

//--- Establecer Take Profit en la posición activa
void SetTakeProfit()
{
   if(g_positionTicket == 0 || !g_useTP) return;
   
   if(!g_posInfo.SelectByTicket(g_positionTicket)) return;
   
   double currentSL = g_posInfo.StopLoss();
   double openPrice = g_posInfo.PriceOpen();
   double tpDist    = PipsToPrice(InpTPPips);
   double newTP     = 0;
   
   if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
      newTP = NormalizeDouble(openPrice + tpDist, _Digits);
   else
      newTP = NormalizeDouble(openPrice - tpDist, _Digits);
   
   for(int i = 0; i < MAX_RETRIES; i++)
   {
      if(g_trade.PositionModify(g_positionTicket, currentSL, newTP))
      {
         if(g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
         {
            Print("[OK] TP establecido en ", newTP);
            return;
         }
      }
      Print("[RETRY ", i+1, "] Fallo al establecer TP. Code: ", g_trade.ResultRetcode());
      Sleep(RETRY_SLEEP_MS);
   }
   Print("[ERROR] No se pudo establecer TP después de ", MAX_RETRIES, " intentos");
}

//--- Cancelar todas las órdenes y posiciones del EA (cleanup)
void CancelAll()
{
   // Eliminar órdenes pendientes
   if(g_buyOrderTicket > 0)
   {
      DeleteOrderSafe(g_buyOrderTicket);
      g_buyOrderTicket = 0;
   }
   if(g_sellOrderTicket > 0)
   {
      DeleteOrderSafe(g_sellOrderTicket);
      g_sellOrderTicket = 0;
   }
   
   // También escanear por si quedaron órdenes huérfanas
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(g_orderInfo.SelectByIndex(i))
      {
         if(g_orderInfo.Magic() == InpMagicNumber && g_orderInfo.Symbol() == _Symbol)
         {
            DeleteOrderSafe(g_orderInfo.Ticket());
         }
      }
   }
   
   g_positionTicket = 0;
   Print("[INFO] CancelAll completado. Transición a IDLE.");
}

//+------------------------------------------------------------------+
//| SECTION 5: Trailing Stop Logic                                    |
//+------------------------------------------------------------------+

void ApplyTrailingStop()
{
   if(g_positionTicket == 0) return;
   if(!g_posInfo.SelectByTicket(g_positionTicket)) return;
   
   double currentSL = g_posInfo.StopLoss();
   double currentTP = g_posInfo.TakeProfit();
   double trailDist = PipsToPrice(InpTrailingPips);
   double newSL     = 0;
   
   if(g_posInfo.PositionType() == POSITION_TYPE_BUY)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      newSL = NormalizeDouble(bid - trailDist, _Digits);
      
      // Solo mover si el nuevo SL es mayor que el actual
      if(newSL > currentSL || currentSL == 0)
      {
         for(int i = 0; i < MAX_RETRIES; i++)
         {
            if(g_trade.PositionModify(g_positionTicket, newSL, currentTP))
            {
               if(g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
               {
                  Print("[TRAIL] BUY SL movido a ", newSL, " (Bid: ", bid, ")");
                  return;
               }
            }
            Sleep(RETRY_SLEEP_MS);
         }
      }
   }
   else if(g_posInfo.PositionType() == POSITION_TYPE_SELL)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      newSL = NormalizeDouble(ask + trailDist, _Digits);
      
      // Solo mover si el nuevo SL es menor que el actual (o SL == 0)
      if(newSL < currentSL || currentSL == 0)
      {
         for(int i = 0; i < MAX_RETRIES; i++)
         {
            if(g_trade.PositionModify(g_positionTicket, newSL, currentTP))
            {
               if(g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
               {
                  Print("[TRAIL] SELL SL movido a ", newSL, " (Ask: ", ask, ")");
                  return;
               }
            }
            Sleep(RETRY_SLEEP_MS);
         }
      }
   }
}

//--- Verificar si la posición sigue abierta
bool IsPositionOpen()
{
   if(g_positionTicket == 0) return false;
   return g_posInfo.SelectByTicket(g_positionTicket);
}

//+------------------------------------------------------------------+
//| SECTION 6: UI / Chart Objects                                     |
//+------------------------------------------------------------------+

//--- Crear un botón en el gráfico
void CreateButton(string name, string text, int x, int y, int width, int height, color bgColor, color txtColor)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtColor);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 100);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

//--- Crear una etiqueta de texto
void CreateLabel(string name, string text, int x, int y, color txtColor, int fontSize = 9)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 100);
}

//--- Inicializar todos los objetos UI
void InitUI()
{
   int btnW = 100;
   int btnH = 30;
   int baseX = 20;
   int baseY = 40;
   
   // Botones (Alineados arriba a la izquierda)
   CreateButton(BTN_ARM,    "▶ ARMAR",    baseX,       baseY, btnW, btnH, C'35,134,54',  clrWhite);
   CreateButton(BTN_CANCEL, "■ CANCELAR", baseX + 110, baseY, btnW, btnH, C'207,34,46',  clrWhite);
   CreateButton(BTN_TP,     "TP OFF",     baseX + 220, baseY, btnW, btnH, clrGray,       clrWhite);
   
   // Labels
   CreateLabel(LBL_TITLE,     "═══ NEWS STRADDLE EA ═══",            baseX, baseY + 40, clrGold, 11);
   CreateLabel(LBL_STATE,     "Estado: " + StateToString(g_state),   baseX, baseY + 60,  clrWhite);
   CreateLabel(LBL_EVENT,     "Evento: " + InpNewsTime,              baseX, baseY + 78,  clrSilver);
   CreateLabel(LBL_COUNTDOWN, "",                                    baseX, baseY + 96,  clrYellow);
   CreateLabel(LBL_PARAMS,    StringFormat("Dist: %.1f pips | Trail: %.1f pips | Lot: %.2f",
               InpEntryDistPips, InpTrailingPips, InpLotSize),       baseX, baseY + 114,  clrSilver);
   
   UpdateTPButton();
   ChartRedraw();
}

//--- Actualizar el botón TP según estado
void UpdateTPButton()
{
   if(g_useTP)
   {
      ObjectSetString(0, BTN_TP, OBJPROP_TEXT, "TP ON (" + DoubleToString(InpTPPips, 1) + "p)");
      ObjectSetInteger(0, BTN_TP, OBJPROP_BGCOLOR, C'30,100,200');
   }
   else
   {
      ObjectSetString(0, BTN_TP, OBJPROP_TEXT, "TP OFF");
      ObjectSetInteger(0, BTN_TP, OBJPROP_BGCOLOR, clrGray);
   }
}

//--- Actualizar el panel de estado
void UpdateUI()
{
   // Estado
   ObjectSetString(0, LBL_STATE, OBJPROP_TEXT, "Estado: " + StateToString(g_state));
   
   // Color del estado según fase
   color stateColor = clrWhite;
   switch(g_state)
   {
      case STATE_IDLE:          stateColor = clrWhite;      break;
      case STATE_ARMED:         stateColor = clrYellow;     break;
      case STATE_ORDERS_PLACED: stateColor = clrOrange;     break;
      case STATE_TRADE_ACTIVE:  stateColor = clrLime;       break;
      case STATE_DONE:          stateColor = clrDodgerBlue; break;
   }
   ObjectSetInteger(0, LBL_STATE, OBJPROP_COLOR, stateColor);
   
   // Countdown
   if(g_state == STATE_ARMED && g_eventTime > 0)
   {
      long secsLeft = (long)(g_eventTime - TimeCurrent());
      if(secsLeft > 0)
      {
         int mins = (int)(secsLeft / 60);
         int secs = (int)(secsLeft % 60);
         ObjectSetString(0, LBL_COUNTDOWN, OBJPROP_TEXT,
                         StringFormat("⏱ T-%02d:%02d hasta órdenes", mins, secs));
         ObjectSetInteger(0, LBL_COUNTDOWN, OBJPROP_COLOR, clrYellow);
      }
      else
      {
         ObjectSetString(0, LBL_COUNTDOWN, OBJPROP_TEXT, "⚡ COLOCANDO ÓRDENES...");
         ObjectSetInteger(0, LBL_COUNTDOWN, OBJPROP_COLOR, clrOrange);
      }
   }
   else if(g_state == STATE_TRADE_ACTIVE)
   {
      if(g_posInfo.SelectByTicket(g_positionTicket))
      {
         double profit = g_posInfo.Profit();
         string profitStr = StringFormat("P/L: %.2f | SL: %.5f", profit, g_posInfo.StopLoss());
         ObjectSetString(0, LBL_COUNTDOWN, OBJPROP_TEXT, profitStr);
         ObjectSetInteger(0, LBL_COUNTDOWN, OBJPROP_COLOR, profit >= 0 ? clrLime : clrRed);
      }
   }
   else
   {
      ObjectSetString(0, LBL_COUNTDOWN, OBJPROP_TEXT, "");
   }
   
   ChartRedraw();
}

//--- Eliminar todos los objetos UI
void DestroyUI()
{
   ObjectDelete(0, BTN_ARM);
   ObjectDelete(0, BTN_CANCEL);
   ObjectDelete(0, BTN_TP);
   ObjectDelete(0, LBL_STATE);
   ObjectDelete(0, LBL_EVENT);
   ObjectDelete(0, LBL_PARAMS);
   ObjectDelete(0, LBL_TITLE);
   ObjectDelete(0, LBL_COUNTDOWN);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| SECTION 7: Event Handlers                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("═══════════════════════════════════════════════");
   Print("[INIT] NewsStraddleEA v1.00 iniciando...");
   Print("[INIT] Símbolo: ", _Symbol, " | Digits: ", _Digits, " | Point: ", _Point);
   
   // Inicializar factor de pips
   InitPipFactor();
   Print("[INIT] PipFactor: ", g_pipFactor, " | 1 pip = ", PipsToPrice(1.0), " en precio");
   
   // Configurar CTrade primero
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(50);  // Slippage amplio para noticias
   
   // Detectar filling mode soportado por el broker
   long fillType = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillType & SYMBOL_FILLING_IOC) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else if((fillType & SYMBOL_FILLING_FOK) != 0)
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   
   Print("[INIT] Filling mode: ", fillType);
   
   // Estado inicial
   g_state = STATE_IDLE;
   g_useTP = InpUseTP;
   
   // UI PRIMERO — siempre visible sin importar validaciones
   InitUI();
   
   // Timer de 500ms para precisión
   EventSetMillisecondTimer(500);
   
   // Validaciones (no-fatales: warnings + fallback)
   if(!ValidateSymbolOrderMode())
   {
      Print("[WARNING] Símbolo no soporta Stop-Limit. Usando Buy Stop / Sell Stop como fallback.");
      g_useStopLimit = false;
   }
   else
   {
      g_useStopLimit = true;
      Print("[INFO] Símbolo soporta Stop-Limit. Modo óptimo activado.");
   }
   
   if(!ValidateLotSize())
   {
      Print("[WARNING] LotSize puede no ser válido. Revise configuración.");
   }
   
   if(!ValidateStopsLevel(InpEntryDistPips))
   {
      Print("[WARNING] Distancia de entrada puede ser menor que el mínimo del broker.");
   }
   
   // Parsear hora del evento
   g_eventTime = ParseEventTime(InpNewsTime);
   if(g_eventTime == 0)
   {
      Print("[WARNING] No se pudo parsear la hora del evento. Use formato HH:MM:SS");
   }
   else
   {
      Print("[INIT] Evento programado para: ", TimeToString(g_eventTime, TIME_SECONDS));
   }
   
   Print("[INIT] EA listo. Presione ARMAR para programar el evento.");
   Print("═══════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   // STATE_ORDERS_PLACED: Verificar si alguna orden se ejecutó
   if(g_state == STATE_ORDERS_PLACED)
   {
      if(CheckForExecution())
      {
         g_state = STATE_TRADE_ACTIVE;
         Print("[STATE] → TRADE_ACTIVE. Trailing Stop activo.");
         UpdateUI();
      }
      
      // También verificar si las órdenes siguen existiendo
      // (podrían haber sido canceladas externamente)
      bool buyExists  = false;
      bool sellExists = false;
      
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         if(g_orderInfo.SelectByIndex(i))
         {
            if(g_orderInfo.Magic() == InpMagicNumber && g_orderInfo.Symbol() == _Symbol)
            {
               if(g_orderInfo.Ticket() == g_buyOrderTicket)  buyExists = true;
               if(g_orderInfo.Ticket() == g_sellOrderTicket) sellExists = true;
            }
         }
      }
      
      // Si ambas órdenes desaparecieron sin posición, algo salió mal
      if(!buyExists && !sellExists && g_positionTicket == 0)
      {
         // Verificar una vez más si hay posición
         if(!CheckForExecution())
         {
            Print("[WARNING] Ambas órdenes desaparecieron sin posición. → IDLE");
            g_state = STATE_IDLE;
            g_buyOrderTicket = 0;
            g_sellOrderTicket = 0;
            UpdateUI();
         }
      }
   }
   
   // STATE_TRADE_ACTIVE: Trailing Stop + verificar cierre
   if(g_state == STATE_TRADE_ACTIVE)
   {
      if(IsPositionOpen())
      {
         ApplyTrailingStop();
      }
      else
      {
         Print("[INFO] Posición cerrada. → DONE");
         g_state = STATE_DONE;
         g_positionTicket = 0;
         g_buyOrderTicket = 0;
         g_sellOrderTicket = 0;
         UpdateUI();
      }
   }
}

//+------------------------------------------------------------------+
//| OnTimer (cada 500ms)                                              |
//+------------------------------------------------------------------+
void OnTimer()
{
   // STATE_ARMED: Esperar T-10s (o el lead time configurado)
   if(g_state == STATE_ARMED)
   {
      datetime triggerTime = g_eventTime - InpLeadTimeSeconds;
      datetime now = TimeCurrent();
      
      if(now >= triggerTime)
      {
         Print("[TRIGGER] ¡Momento alcanzado! Colocando órdenes straddle...");
         
         if(PlaceStraddleOrders())
         {
            g_state = STATE_ORDERS_PLACED;
            Print("[STATE] → ORDERS_PLACED");
         }
         else
         {
            Print("[ERROR] Fallo al colocar órdenes. → IDLE");
            g_state = STATE_IDLE;
         }
         UpdateUI();
      }
   }
   
   // Actualizar UI periódicamente
   UpdateUI();
}

//+------------------------------------------------------------------+
//| OnChartEvent                                                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   
   // --- Botón ARMAR ---
   if(sparam == BTN_ARM)
   {
      ObjectSetInteger(0, BTN_ARM, OBJPROP_STATE, false);
      
      if(g_state == STATE_IDLE || g_state == STATE_DONE)
      {
         // Re-parsear la hora del evento (por si cambió de día)
         g_eventTime = ParseEventTime(InpNewsTime);
         
         if(g_eventTime == 0)
         {
            Print("[ERROR] Hora del evento inválida.");
            return;
         }
         
         // Verificar que el evento no ha pasado
         if(TimeCurrent() >= g_eventTime)
         {
            Print("[WARNING] La hora del evento ya pasó. Reprograme para mañana o cambie InpNewsTime.");
            // Intentar con el día siguiente
            g_eventTime += 86400;
            Print("[INFO] Evento reprogramado para: ", TimeToString(g_eventTime, TIME_DATE | TIME_SECONDS));
         }
         
         g_state = STATE_ARMED;
         Print("[STATE] → ARMED. Evento: ", TimeToString(g_eventTime, TIME_SECONDS));
         Print("[INFO] Órdenes se colocarán a T-", InpLeadTimeSeconds, "s (",
               TimeToString(g_eventTime - InpLeadTimeSeconds, TIME_SECONDS), ")");
      }
      else
      {
         Print("[INFO] No se puede ARMAR en estado ", StateToString(g_state));
      }
      UpdateUI();
   }
   
   // --- Botón CANCELAR ---
   if(sparam == BTN_CANCEL)
   {
      ObjectSetInteger(0, BTN_CANCEL, OBJPROP_STATE, false);
      
      Print("[ACTION] CANCELAR presionado. Limpiando todo...");
      CancelAll();
      g_state = STATE_IDLE;
      UpdateUI();
   }
   
   // --- Botón TP ON/OFF ---
   if(sparam == BTN_TP)
   {
      ObjectSetInteger(0, BTN_TP, OBJPROP_STATE, false);
      
      g_useTP = !g_useTP;
      Print("[ACTION] TP Toggle: ", (g_useTP ? "ON" : "OFF"));
      
      // Si hay posición activa y se acaba de activar TP, aplicarlo
      if(g_useTP && g_state == STATE_TRADE_ACTIVE && g_positionTicket > 0)
      {
         SetTakeProfit();
      }
      // Si se desactivó TP y hay posición, quitar el TP
      else if(!g_useTP && g_state == STATE_TRADE_ACTIVE && g_positionTicket > 0)
      {
         if(g_posInfo.SelectByTicket(g_positionTicket))
         {
            double currentSL = g_posInfo.StopLoss();
            g_trade.PositionModify(g_positionTicket, currentSL, 0);
            Print("[INFO] TP removido de la posición.");
         }
      }
      
      UpdateTPButton();
      UpdateUI();
   }
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("═══════════════════════════════════════════════");
   Print("[DEINIT] NewsStraddleEA cerrando. Razón: ", reason);
   
   // Eliminar órdenes pendientes del EA
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(g_orderInfo.SelectByIndex(i))
      {
         if(g_orderInfo.Magic() == InpMagicNumber && g_orderInfo.Symbol() == _Symbol)
         {
            Print("[DEINIT] Eliminando orden pendiente: ", g_orderInfo.Ticket());
            g_trade.OrderDelete(g_orderInfo.Ticket());
         }
      }
   }
   
   // Eliminar timer
   EventKillTimer();
   
   // Eliminar UI
   DestroyUI();
   
   Print("[DEINIT] Cleanup completo.");
   Print("═══════════════════════════════════════════════");
}
//+------------------------------------------------------------------+

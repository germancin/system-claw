//+------------------------------------------------------------------+
//| Inputs.mqh — Todos los parámetros configurables del EA            |
//+------------------------------------------------------------------+

input string InpNewsTime          = "08:30:00";   // Hora del evento (HH:MM:SS servidor)
input double InpEntryDistPips     = 1000.0;        // Distancia de entrada en pips
input double InpSLPips            = 10000.0;       // Stop Loss en pips
input double InpTPPips            = 10000.0;       // Take Profit en pips
input bool   InpEnableTP          = true;           // Activar Take Profit
input double InpTrailingStopPips  = 2000.0;         // Trailing Stop en pips (0=off)
input double InpLotSize           = 0.10;          // Tamaño de lote
input int    InpMagicNumber       = 202601;        // Magic Number único
input int    InpLeadTimeSeconds   = 10;            // Segundos antes del evento para colocar órdenes

//+------------------------------------------------------------------+
//| Inputs.mqh — Todos los parámetros configurables del EA            |
//+------------------------------------------------------------------+

input string InpNewsTime          = "08:30:00";   // Hora del evento (HH:MM:SS servidor)
input double InpEntryDistPips     = 15.0;         // Distancia de entrada en pips
input double InpTrailingPips      = 15.0;         // Distancia del Trailing Stop en pips
input bool   InpUseTP             = false;        // Usar Take Profit (ON/OFF)
input double InpTPPips            = 30.0;         // Take Profit en pips
input double InpLotSize           = 0.01;         // Tamaño de lote
input int    InpMagicNumber       = 202601;       // Magic Number único
input int    InpLeadTimeSeconds   = 10;           // Segundos antes del evento para colocar órdenes

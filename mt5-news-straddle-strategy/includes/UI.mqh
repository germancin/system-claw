//+------------------------------------------------------------------+
//| UI.mqh — Panel visual del gráfico (botones, labels, colores)      |
//+------------------------------------------------------------------+

const string BG_PANEL  = "NewsEA_BgPanel";
const string BTN_CANCEL= "NewsEA_BtnCancel";
const string LBL_STATE = "NewsEA_LblState";
const string LBL_COUNT = "NewsEA_LblCountdown";

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
   CreateButton(BTN_CANCEL, "CANCEL ALL", baseX + 110, baseY, 120, 35, C'207,34,46', clrWhite);

   // Labels
   CreateLabel("NewsEA_Title",  "═══ NEWS STRADDLE EA v1.12 ═══",     baseX, baseY + 40,  clrGold, 11);
   CreateLabel(LBL_STATE,       "Estado: IDLE",                        baseX, baseY + 62,  clrWhite, 9);
   CreateLabel("NewsEA_Event",  "Evento: " + InpNewsTime,             baseX, baseY + 80,  clrSilver, 9);
   CreateLabel(LBL_COUNT,       "",                                    baseX, baseY + 98,  clrYellow, 9);
   CreateLabel("NewsEA_Params", StringFormat("Dist: %.1f | Trail: %.1f | TP: %.1f pips",
               InpEntryDistPips, InpTrailingPips, InpTPPips),          baseX, baseY + 116, C'100,200,255', 8);
   CreateLabel("NewsEA_Rule",   "TP Virtual -> Breakeven+50 -> Trailing",  baseX, baseY + 134, C'255,200,100', 8);

   ChartRedraw();
}

void UpdateUI()
{
   ObjectSetString(0, LBL_STATE, OBJPROP_TEXT, "Estado: " + StateToString(g_state));

   if(g_state == STATE_ARMED && g_eventTime > 0)
   {
      long secs = (long)(g_eventTime - TimeCurrent());
      if(secs > 0)
         ObjectSetString(0, LBL_COUNT, OBJPROP_TEXT, StringFormat("T-%02d:%02d", (int)(secs / 60), (int)(secs % 60)));
      else
         ObjectSetString(0, LBL_COUNT, OBJPROP_TEXT, "COLOCANDO ORDENES...");
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

void DrawVirtualTP(double price)
{
   ObjectDelete(0, LINE_VIRTUAL_TP);
   ObjectCreate(0, LINE_VIRTUAL_TP, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, LINE_VIRTUAL_TP, OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, LINE_VIRTUAL_TP, OBJPROP_STYLE, STYLE_DASHDOT);
   ObjectSetInteger(0, LINE_VIRTUAL_TP, OBJPROP_WIDTH, 2);
   ObjectSetString(0, LINE_VIRTUAL_TP, OBJPROP_TEXT, "Virtual TP");
   ChartRedraw();
}

void DeleteVirtualTP()
{
   ObjectDelete(0, LINE_VIRTUAL_TP);
   ChartRedraw();
}

void CleanupUI()
{
   ObjectDelete(0, BG_PANEL);
   ObjectDelete(0, BTN_CANCEL);
   ObjectDelete(0, LBL_STATE);
   ObjectDelete(0, LBL_COUNT);
   ObjectDelete(0, "NewsEA_Title");
   ObjectDelete(0, "NewsEA_Event");
   ObjectDelete(0, "NewsEA_Params");
   ObjectDelete(0, "NewsEA_Rule");
   DeleteVirtualTP();
}

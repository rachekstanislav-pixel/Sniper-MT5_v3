// Standalone working revision of uploaded 3.6.5 VISUAL_AUDIT.
// Canonical src/ modules were not supplied; port these changes when available.
//+------------------------------------------------------------------+
//|                                               Sniper_Manager.mq5 |
//|                                Copyright 2026, Trading Expert    |
//+------------------------------------------------------------------+
#property strict
#property version "3.65"
#property description "BASE_ATR trading restored unchanged; right HUD and one-row summary only"
#include <Trade\Trade.mqh>
#include <Canvas\Canvas.mqh>

CTrade trade;

// Each attachment owns one short namespace. Never enumerate/delete another tool's objects.
string G_VisualPrefix="";


// ===== 1. НАСТРОЙКИ АВТОТОРГОВЛИ И ДИНАМИЧЕСКОГО РИСКА =====
input bool   EnableAutoTrade      = true;     // Автоторговля (вкл/выкл)
input ulong  MagicNumber          = 777;      // Magic Number
input int    EntryDelayMinutes    = 2;        // Задержка между входами (мин)

// ===== 2. НАСТРОЙКИ УПРАВЛЕНИЯ ПОЗИЦИЯМИ (ДЛЯ ВСЕЙ КОРЗИНЫ) =====
input int    Fixed_TakeProfit     = 1000;     // ВИРТУАЛЬНЫЙ Тейк-Профит всей пачки (в пунктах)
input int    Physical_BE_Trigger  = 250;      // Триггер физического БУ (в пунктах)
input int    Physical_BE_Level    = 50;       // Уровень физического БУ (в пунктах)
input int    StopLossPoints       = 500;      // Дефолтный Стоп-лосс для входов ИИ (в пунктах)

// ===== 3. SMC, ОБЪЕМЫ И ТРИГГЕРЫ ВХОДОВ =====
input int    MinSweepPoints       = 100;      // Минимальный прокол уровня для Свипа (в пунктах)
input double VolSpikeCoef         = 1.5;      // Коэффициент аномального объема (множитель SMA)
input int    Vol_SMA_Period       = 20;       // Период SMA для тиковых объемов
input int    ATR_Period           = 14;       // Период ATR
input int    ATR_MA_Period        = 50;       // Период SMA для ATR
input int    RSI_Period           = 13;       // Период RSI для старших ТФ
input int    Stoch_K              = 5;
input int    Stoch_D              = 3;
input int    Stoch_Slow           = 3;

// ===== 4. НАСТРОЙКИ СТРУКТУРЫ И ЦВЕТОВ =====
input int    Fractal_Strength     = 20;
input color  Color_BOS            = clrDodgerBlue;
input color  Color_CHOCH          = clrMagenta;
input color  Diamond_Color        = clrMediumOrchid;
input color  Color_OB_Buy         = clrDarkGreen;
input color  Color_OB_Sell        = clrMidnightBlue;
input color  Color_FVG_Buy        = clrDarkGreen;
input color  Color_FVG_Sell       = clrMidnightBlue;
input int    InvalidationPoints   = 500;      // Отмена зоны OTE

// ===== 5. TELEGRAM =====
input string Telegram_Token       = "";
input string Telegram_Chat_ID     = "";

// Explicit simulation: no CTrade mutation, AI consumption or Telegram requests.
input bool DiagnosticMode = false;
input double DailyLossLimitPercent = 0.0; // 0: no new daily strategy limit; own realized+floating PNL
input int MaxStructureAgeBars = 0; // 0: preserve legacy age policy; >0: explicit opt-in expiry
input bool DiagnosticCleanView = false; // Compact text layout only; NEVER hides modules or objects
input bool ShowMTFDashboard = true;
input bool ShowD1Fibonacci = true; // Native anchored tool; numeric reference lines retained
input bool ShowH4Fibonacci = true; // Native anchored tool; numeric reference lines retained
input bool ShowLegacyStructure = true; // Original v1 chart-TF structure, visual only
input bool ShowStructureLabels = true; // HH/HL/LH/LL labels; event BOS/CHoCH remain
input bool ShowFiboDiagnostics = false; // Central diagnostic rectangle OFF by default
input bool ShowDiagnosticSignals = true; // Candidate arrows, never simulated fills
input int VisualRefreshSeconds = 1; // Model timer; actual painting is wall-clock limited
input int TesterVisualFrameMs = 500;
input int LiveVisualFrameMs = 250;
input int HudFontSize = 11;
input int InfoFontSize = 13; // Summary font stays readable; wrap instead of shrinking
input int InfoWidthPercent = 80; // Right-aligned information block
input int HudWidthPercent = 72; // Visual only: entire information panel, right aligned
input int InfoRightMarginPx = 24;
input int HudBackgroundTransparency = 80; // Percent TRANSPARENT (80 => alpha 51 / opacity 20%)
input string HudFontName = "Arial"; // Explicit font shared by measurement and labels
input int HudTopOffsetPx = 90; // Reserve space for MT5 one-click trading; 8 suits tester
input bool ShowChartPriceCaptions = true; // Short, spaced captions; full detail in tooltips
input bool EnableSMC_EMA = true;
input bool EnableSMC_Comp = true; // Includes paired Compression limit
input bool EnableSMC_OTE = true;
input bool RequireOTEReclaim = true; // D1 .790 sweep + closed M15 return + held H4 OB; false restores legacy touch entry
input bool AllowOTEReclaimAgainstH4 = true; // Separate permission; exactly half dynamic cash risk
input int OTEReclaimMaxBars = 4; // Including the sweep candle: at most one hour on M15
input double OTEReclaimMaxDistanceATR = 0.5; // Maximum entry distance above/below D1 .790
input bool EnableSMC_Sweep = true;
input bool EnableSMC_Base = true;
input bool BaseUseStopOrders = false; // Alternative to the existing closed-breakout / ATR mode
enum BASE_TARGET_SCOPE { BASE_TARGET_H1=1, BASE_TARGET_H4=2, BASE_TARGET_H1_H4=3 };
input BASE_TARGET_SCOPE BaseTargetScope = BASE_TARGET_H1_H4; // Nearest confirmed profitable H1/H4 level
input bool BaseRequireVolumeSpike = false; // Closed breakout is sufficient; optional old volume filter
input int BaseSwingStrength = 2; // Confirmed local pivot: closed bars on each side
input int BaseSwingLookback = 64;
input int BaseSLBufferPoints = 15; // Beyond the last confirmed high/low
input int BaseMaxWaitBars = 10; // Same horizon as the existing BASE projection
input bool EnableAICommands = true;
input bool AllowD1OTEAgainstH4 = false; // EXPERIMENT: only SMC_OTE, strict D1 direction; data/risk gates remain
input double CounterTrendRiskMult = 0.5; // Only above explicit OTE exception; never increases risk
input int MaxVisualHistory = 256; // Presentation history only, not a signal/risk limit
input bool ShowTesterIndicatorWindows = false;
input bool ShowFiboLevelCaptions = false; // Full prices/roles remain in dashboard and tooltips
input bool ShowReferenceHLines = false; // Avoid duplicating native Fibonacci levels
input int DiagnosticTopOffsetPx = 166; // Offset below MT5 trading widgets on live charts
input int H4OldStructureWarningBars = 12; // Informational warning only; does not alter entries
input bool DiagnosticShowH4Zones = true; // Optional OB/FVG rectangles in clean mode
input bool RequireConfirmedH4ForEntries = true; // Block trades without confirmed H4 BOS/CHoCH
input bool EnforceH4Direction = true; // Trade only in H4 confirmed direction
// D1 is the primary intraday Fibonacci; H4 is an independent confirmation filter.
input bool D1_RequireImpulse = false; // If true, skip non-impulse previous days
input int D1_AverageDays = 14;
input double D1_MinRangeMultiplier = 1.20;
input double D1_MinBodyRatio = 0.60;
input bool D1_RequireDirectionForEntries = false; // Optional D1 directional filter
input bool BlockD1H4ConflictForEntries = true; // Future trading: block opposite D1/H4 directions (no forced D1 alignment otherwise)

// --- Глобальные переменные ---
double G_Fibo_618 = 0, G_Fibo_790 = 0, G_Fibo_EQ = 0;
bool   G_Fibo_isUp = true;
bool   G_Struct_Valid = false;
datetime G_D1_SourceDay = 0;
int G_D1_Direction = 0; // +1 bullish previous day, -1 bearish
bool G_D1_Valid = false;
double G_Struct_High = 0.0, G_Struct_Low = 0.0;
datetime G_LastBarTime = 0, G_LastBuyTime = 0, G_LastSellTime = 0;

int h_atr, h_atr_ma;
int h_ote_atr=INVALID_HANDLE;
int h_ema21, h_ema55, h_ema200;

// --- Переменные для MTF ---
int h_mtf_rsi[6], h_mtf_stoch[6], h_mtf_macd[6];
int h_mtf_ema21[6], h_mtf_ema55[6], h_mtf_ema200[6];
double G_MTF_SwingHigh[6], G_MTF_SwingLow[6];
datetime G_MTF_SwingHighTime[6], G_MTF_SwingLowTime[6];

string mtf_names[6] = {"M1", "M5", "M15", "H1", "H4", "D1"};
ENUM_TIMEFRAMES mtf_tfs[6] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};

bool   G_PredZone_Active = false;
double G_PredZone_High = 0.0, G_PredZone_Low = 0.0;
bool   G_Compression_Active = false;
bool   G_WickAlertedForCurrentZone = false;

// --- ФОРВАРД-ДЕКЛАРАЦИИ ---
double CalculateSmartLot(double entry_price, double stop_loss);
double GetDynamicRisk();
double GetDynamicGlobalRisk();
double GetVolumeSMA(int period);
string GetNearestOBDistance();
void CheckBaseBreakout();
void CheckLiquiditySweepLive();
void CheckEMATouchLive();
void CheckCompressionPhase();
void CheckAISignals();
bool CanOpenLot(int type, string block_comment);
void ManagePositions();
void CheckEquityProtection();
bool IsSwingHigh(ENUM_TIMEFRAMES tf, int index, int strength);
bool IsSwingLow(ENUM_TIMEFRAMES tf, int index, int strength);
void DrawStructureAndFibo();
void UpdatePreviousDayFibo();
input ENUM_TIMEFRAMES SF_StructureTF = PERIOD_H4;
input int    SF_LeftBars = 3;
input int    SF_RightBars = 3;
input int    SF_LookbackBars = 300;
input double SF_MinSwingPoints = 0.0;
input double SF_BreakBufferPoints = 0.0;
input bool   SF_ShowOTE = true;
input bool   SF_ShowStatus = true;
input bool   SF_ShowAnchor = true;
input bool   SF_KeepAfterTest = true;
input bool   SF_ShowHistory = true; // show previous confirmed breaks
input int    SF_HistoryCount = 8; // maximum historical break drawings

int SF_ConfirmedDirection = 0;
datetime SF_ConfirmedBreakTime = 0;
double SF_ConfirmedOrigin = 0.0;
double SF_ConfirmedBreak = 0.0;
string SF_PivotStructure = "UNDEFINED"; // most recent confirmed H4 high/low classification
string SF_Prefix = "SN24_STRUCT_";
datetime SF_LastClosed = 0;
string SF_ActivePrefix = "SN24_STRUCT_";
bool SF_DataReady=false;
bool G_D1_DataReady=false;
bool G_StopLatched=false, G_StateOK=true, G_ExecutionUncertain=false;
datetime G_EntryRetryAfter=0,G_PendingCancelRetryAfter=0;
bool G_StopNoticePending=false;
string G_StateFile="", G_StopFile="";
string G_SF_EventLabel="BOS/INITIAL";
int G_InstanceLock=INVALID_HANDLE;
MqlRates SF_Rates[];


struct SF_Pivot
{
   datetime time;
   double price;
   int type; // +1 high, -1 low
   int shift;
};

// Presentation only. No function in this block can submit or mutate a trade.
struct H4ViewZone {
   string name,label;
   datetime time;
   double top,bottom;
   color shade;
};
H4ViewZone G_H4ViewZones[];
datetime SF_OriginTime=0,SF_EndpointTime=0;

// Presentation resources and read-only signal audit; never used as trade permissions.
CCanvas G_HeaderCanvas,G_DiagCanvas;
bool G_HeaderCanvasReady=false,G_DiagCanvasReady=false;
int G_HeaderCanvasWidth=0,G_HeaderCanvasHeight=0,G_DiagCanvasWidth=0,G_DiagCanvasHeight=0;
enum SignalAuditSlot { AUDIT_EMA=0,AUDIT_COMP,AUDIT_OTE,AUDIT_SWEEP,AUDIT_BASE,AUDIT_AI,AUDIT_COUNT };
struct SignalAuditCounters {
   long calls,read_ok,candidate_hits,gate_checks,gate_rejects,submissions,confirmed_market,confirmed_pending;
};
SignalAuditCounters G_SignalAudit[AUDIT_COUNT];
long G_MTFAuditFrames[6],G_MTFAuditReady[6];

// Bounded, wall-clock presentation. Trading/data paths never wait for the renderer.
bool G_PaintFrame=false,G_VisualEnabled=true;
double G_CompHigh=0,G_CompLow=0;
bool G_CompEntryDone=false;
datetime G_CompDay=0,G_CompRetryAt=0;
int G_CompDirection=0;
datetime G_OTEReclaimCheckedBar=0,G_OTEReclaimSignalBar=0,G_OTEReclaimDay=0;
int G_OTEReclaimSide=-1;
struct OTEReclaimState {
   bool active; int bars; double obLow,obHigh,extreme;
   datetime obTime,confirmedAt,sweepTime,lastTime;
};
OTEReclaimState G_OTEReclaim;
datetime G_OTEContextDay=0;
double G_OTEContextLow=0,G_OTEContextHigh=0;
int G_OTEContextDirection=0;
bool G_BaseArmed=false,G_BaseConsumed=false;
bool G_BaseStopOCOTripped=false;
double G_BaseHigh=0,G_BaseLow=0;
datetime G_BaseStarted=0,G_BaseArmedBar=0,G_BaseCheckedBar=0;
string G_StructureStatus="";
struct RectangleView {
   string name,text; datetime first,last; double high,low; color shade; bool painted;
};
struct ArrowView {
   string name,text; datetime time; double price; color shade; int code; bool buy,painted;
};
RectangleView G_BaseViews[];
ArrowView G_ArrowViews[];
string G_DroppedViews[];


// Pixel geometry comes from the actual configured font, including terminal DPI.
int G_HudLeft=12;
int G_HudWidth=0,G_HudFont=11,G_HudRow=22,G_HudColumns=6;
int G_HudTop=0,G_SummaryY=0,G_ScopeY=0,G_DiagTop=0,G_DiagBottom=0;
bool G_HudCompact=false;
int G_DiagPage=0,G_DiagPages=1;


// Split diagnostics on measured width. Every part remains available in its tooltip.

struct PriceCaption { string key,text; double price; color shade; };
PriceCaption G_PriceCaptions[];


// v3.5 safety boundary. All entry requests and CTrade mutations are centralized here.


// Only known module IDs can request an entry. Comments are exact IDs, not arbitrary privileges.


// A narrow allow-list of explicit no-execution responses. Timeout/connection/error,
// unknown codes and contradictory result fields must remain fail-closed.


// Single source of truth for H4 retracement prices.
// origin -> break is the confirmed impulse, and retracement is measured
// BACK from the break toward the origin (never forward from the origin).


void CreateFiboLine(string n, double p, color c, ENUM_LINE_STYLE s, string t);
void CreateStructLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, string text);
void UpdateH4Zones();
void DrawR(string n, datetime t1, double p1, datetime t2, double p2, color c, string txt="");
string GetTimerToNextBar();
void UpdateCenterInfo();
void UpdateFiboDiagnostics();
void UpdateDashboardMTF();
bool CheckNewBar();
void CreateCloseButton();
void DrawCandleSize();
void CheckPredictiveZone();
void CheckWickTouchesAndAlert();
void DrawArrow(string obj_name, datetime t, double p, color clr, int arrow_code, string text, bool isBuy);
void SendTelegramPhotoAlert(string message);
double GetDailyPNL();
void CleanInvalidatedZones();
string GetActiveMacroOTE(double cur);
void UpdateMTFSwings();
void DeleteOrdersByComment(string comment_str);

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   Print("SN365 BASE ATR + D1 .790 M15 OB RECLAIM | counter-H4 half risk | BASE STOP / EXTREMUM mode available | build OTE-1+BASE-STOP-1");
   ResetSignalAudit();
   G_VisualEnabled=!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE);
   InitVisualNamespace();
   if(!MathIsValidNumber(DailyLossLimitPercent) || MagicNumber==0 || EntryDelayMinutes<0 || StopLossPoints<=0 || InvalidationPoints<=0 ||
      Fractal_Strength<1 || Vol_SMA_Period<1 || DailyLossLimitPercent<0 || MaxStructureAgeBars<0 || VisualRefreshSeconds<1 || TesterVisualFrameMs<100 || LiveVisualFrameMs<100 ||
      (!MathIsValidNumber(CounterTrendRiskMult) || CounterTrendRiskMult<=0 || CounterTrendRiskMult>1) ||
      OTEReclaimMaxBars<1 || OTEReclaimMaxBars>96 || (EnableSMC_OTE && RequireOTEReclaim && MinSweepPoints<1) ||
      !MathIsValidNumber(OTEReclaimMaxDistanceATR) || OTEReclaimMaxDistanceATR<=0 || OTEReclaimMaxDistanceATR>5 ||
      BaseSwingStrength<1 || BaseSwingStrength>20 || BaseSwingLookback<2*BaseSwingStrength+2 ||
      BaseSwingLookback>2000 || (int)BaseTargetScope<1 || (int)BaseTargetScope>3 || BaseSLBufferPoints<1 || BaseMaxWaitBars<1 ||
      InfoFontSize<8 || InfoFontSize>24 || InfoWidthPercent<30 || InfoWidthPercent>100 || InfoRightMarginPx<0 ||
      HudBackgroundTransparency<0 || HudBackgroundTransparency>100 || HudFontSize<8 || HudFontSize>18 || HudTopOffsetPx<8 || StringLen(HudFontName)==0 || MaxVisualHistory<16 || MaxVisualHistory>5000)
      return INIT_PARAMETERS_INCORRECT;
   if(!InitSafetyState()) {
      G_StateOK=false;
      if(!DiagnosticMode) return INIT_FAILED;
      // A broken trading-state file must not prevent a strictly read-only chart.
      // Keep stop/uncertainty flags and disk untouched; rebuild visual structure only.
      SF_ConfirmedDirection=0; SF_ConfirmedBreakTime=0;
      SF_ConfirmedOrigin=0; SF_ConfirmedBreak=0;
      G_SF_EventLabel="BOS/INITIAL";
      SafetyLog("diagnostic visual fallback: trading state unavailable, no requests permitted");
   }
   if(!EventSetTimer(VisualRefreshSeconds)) return INIT_FAILED;
   CreateCloseButton();
   trade.LogLevel(LOG_LEVEL_ERRORS);
   trade.SetExpertMagicNumber(MagicNumber);

   G_LastBarTime = 0;
   G_WickAlertedForCurrentZone = false;
   // Cooldowns restored from safety state; never reset on restart.
   G_Struct_Valid = false;
   SF_LastClosed=0; SF_ActivePrefix=SF_Prefix; SF_Clear();

   if(MQLInfoInteger(MQL_TESTER)) TesterHideIndicators(!ShowTesterIndicatorWindows);
   if(EnableSMC_OTE && RequireOTEReclaim) h_ote_atr=iATR(_Symbol,PERIOD_M15,ATR_Period);
   h_atr = iATR(_Symbol, _Period, ATR_Period);
   h_atr_ma = iMA(_Symbol, _Period, ATR_MA_Period, 0, MODE_SMA, h_atr);

   h_ema21 = iMA(_Symbol, _Period, 21, 0, MODE_EMA, PRICE_CLOSE);
   h_ema55 = iMA(_Symbol, _Period, 55, 0, MODE_EMA, PRICE_CLOSE);
   h_ema200= iMA(_Symbol, _Period, 200, 0, MODE_EMA, PRICE_CLOSE);

   for(int i = 0; i < 6; i++) {
      h_mtf_rsi[i] = iRSI(_Symbol, mtf_tfs[i], RSI_Period, PRICE_CLOSE);
      h_mtf_stoch[i] = iStochastic(_Symbol, mtf_tfs[i], Stoch_K, Stoch_D, Stoch_Slow, MODE_SMA, STO_LOWHIGH);
      h_mtf_macd[i] = iMACD(_Symbol, mtf_tfs[i], 12, 26, 9, PRICE_CLOSE);
      h_mtf_ema21[i] = iMA(_Symbol, mtf_tfs[i], 21, 0, MODE_EMA, PRICE_CLOSE);
      h_mtf_ema55[i] = iMA(_Symbol, mtf_tfs[i], 55, 0, MODE_EMA, PRICE_CLOSE);
      h_mtf_ema200[i]= iMA(_Symbol, mtf_tfs[i], 200, 0, MODE_EMA, PRICE_CLOSE);
   }

   if((EnableSMC_OTE && RequireOTEReclaim && h_ote_atr==INVALID_HANDLE) || h_atr==INVALID_HANDLE || h_atr_ma==INVALID_HANDLE || h_ema21==INVALID_HANDLE ||
      h_ema55==INVALID_HANDLE || h_ema200==INVALID_HANDLE) return INIT_FAILED;
   for(int i=0;i<6;i++)
      if(h_mtf_rsi[i]==INVALID_HANDLE || h_mtf_stoch[i]==INVALID_HANDLE || h_mtf_macd[i]==INVALID_HANDLE ||
         h_mtf_ema21[i]==INVALID_HANDLE || h_mtf_ema55[i]==INVALID_HANDLE || h_mtf_ema200[i]==INVALID_HANDLE)
         return INIT_FAILED;
   RefreshMarketContext();
   G_BaseCheckedBar=BaseUseStopOrders?0:iTime(_Symbol,_Period,1); // Pending mode may arm a live inside-range quote immediately.
   G_OTEReclaimCheckedBar=iTime(_Symbol,PERIOD_M15,1); // Never replay a historical entry on attachment.
   ServiceVisuals(true);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   EventKillTimer();
   if(!DiagnosticMode && G_InstanceLock!=INVALID_HANDLE) DeleteOrdersByComment(""); // Own pending must not survive removal/input changes.
   if(G_InstanceLock!=INVALID_HANDLE) { FileClose(G_InstanceLock); G_InstanceLock=INVALID_HANDLE; }
   IndicatorRelease(h_atr); IndicatorRelease(h_atr_ma);
   if(h_ote_atr!=INVALID_HANDLE) IndicatorRelease(h_ote_atr);
   IndicatorRelease(h_ema21); IndicatorRelease(h_ema55); IndicatorRelease(h_ema200);

   for(int i = 0; i < 6; i++) {
       IndicatorRelease(h_mtf_rsi[i]); IndicatorRelease(h_mtf_stoch[i]); IndicatorRelease(h_mtf_macd[i]);
       IndicatorRelease(h_mtf_ema21[i]); IndicatorRelease(h_mtf_ema55[i]); IndicatorRelease(h_mtf_ema200[i]);
   }
   ReleasePanelCanvases();
   ClearOwnVisuals(SF_KeepAfterTest && MQLInfoInteger(MQL_TESTER));
   PrintSignalAudit();
}

// Own deal ledger. Own BASE Stop entry fills persist cooldown and cancel sibling pending orders.
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result) {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
   if(!HistoryDealSelect(trans.deal)) { SafetyLog("deal ledger: HistoryDealSelect unavailable"); return; }
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol ||
      (ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=MagicNumber) return;
   Print("SN363 DEAL | time=",TimeToString((datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME),TIME_DATE|TIME_SECONDS),
      " | deal=",trans.deal," | position=",HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID),
      " | order=",HistoryDealGetInteger(trans.deal,DEAL_ORDER)," | entry=",HistoryDealGetInteger(trans.deal,DEAL_ENTRY),
      " | side=",HistoryDealGetInteger(trans.deal,DEAL_TYPE)," | volume=",DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_VOLUME),8),
      " | price=",DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_PRICE),_Digits),
      " | profit=",DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_PROFIT),2),
      " | commission=",DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_COMMISSION),2),
      " | swap=",DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_SWAP),2),
      " | fee=",DoubleToString(HistoryDealGetDouble(trans.deal,DEAL_FEE),2),
      " | reason=",HistoryDealGetInteger(trans.deal,DEAL_REASON)," | comment=",HistoryDealGetString(trans.deal,DEAL_COMMENT));
   if(DiagnosticMode || G_InstanceLock==INVALID_HANDLE) return;
   long dealEntry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(dealEntry==DEAL_ENTRY_IN || dealEntry==DEAL_ENTRY_INOUT) {
      string module=HistoryDealGetString(trans.deal,DEAL_COMMENT);
      if(HistoryOrderSelect(trans.order)) module=HistoryOrderGetString(trans.order,ORDER_COMMENT);
      if(IsBaseStopModule(module)) {
         int side=(int)HistoryDealGetInteger(trans.deal,DEAL_TYPE);
         if(side!=DEAL_TYPE_BUY && side!=DEAL_TYPE_SELL) return;
         datetime filled=(datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME);
         if(side==DEAL_TYPE_BUY && filled>G_LastBuyTime) G_LastBuyTime=filled;
         else if(side==DEAL_TYPE_SELL && filled>G_LastSellTime) G_LastSellTime=filled;
         G_BaseStopOCOTripped=true; G_BaseConsumed=true;
         if(!SaveSafetyState()) G_StateOK=false;
         CancelBaseStopOrders();
      }
   }
}

void OnTimer() {
   RefreshMarketContext();
   CheckEquityProtection();
   ReviewOwnPending();
   if(BaseUseStopOrders) CheckBaseStopSetup(); // Retry warm-up data without waiting for another chart bar.
   ServiceVisuals(); // Paint at bounded wall-clock rate, not every simulated second.
   static datetime lastAI=0;
   if(TimeCurrent()-lastAI>=5) { CheckAISignals(); lastAI=TimeCurrent(); }
}

//+------------------------------------------------------------------+
//| MAIN LOGIC (TICK)                                                |
//+------------------------------------------------------------------+
void OnTick() {
   bool isNewBar=CheckNewBar();
   RefreshMarketContext(); // Closed D1/H4 first, independent of chart timeframe.
   CheckEquityProtection();
   ReviewOwnPending();
   if(DiagnosticMode) {
      // Full intrabar visual evaluation, even with a previously latched live stop.
      // Every mutation remains blocked by the unchanged v3.5 safety boundary.
      if(isNewBar) { UpdateMTFSwings(); UpdateH4Zones(); CheckBaseBreakout(); }
      CheckCompressionPhase();
      CheckLiquiditySweepLive();
      CheckEMATouchLive();
      CheckPredictiveZone();
      CheckOTEReclaim();
      CheckWickTouchesAndAlert();
      ServiceVisuals();
      return;
   }
   if(G_StopLatched || G_ExecutionUncertain || !G_StateOK) return;
   if(TradingMutationAllowed()) ManagePositions();
   if(isNewBar) {
      UpdateMTFSwings();
      UpdateH4Zones();
      CheckBaseBreakout();
   }
   // Same evaluation schedule in both presentation modes. No orders in DiagnosticMode.
   if(EnableAutoTrade || isNewBar) {
      CheckCompressionPhase();
      CheckLiquiditySweepLive();
      CheckEMATouchLive();
      CheckPredictiveZone();
      CheckOTEReclaim();
      CheckWickTouchesAndAlert();
   }
   ServiceVisuals();
}

//+------------------------------------------------------------------+
//| AI NEWS SIGNAL READER                                            |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| RISK MANAGEMENT & POSITIONS                                      |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| SMC MODULES (LIVE & TICK)                                        |
//+------------------------------------------------------------------+


// МОДУЛЬ 3: СВИП ЛИКВИДНОСТИ (ВХОД LIVE)


// МОДУЛЬ 4: ТОРГОВЛЯ ОТ EMA (LIVE)


// МОДУЛЬ 2: ПРОБОЙ БАЗЫ/НАКОПЛЕНИЯ


// Legacy deep D1 OTE .790-1.000; no new CHoCH/compression prerequisite added.


//+------------------------------------------------------------------+
//| VISUALIZATION AND DASHBOARD                                      |
//+------------------------------------------------------------------+


// The H4 structure remains a separate confirmation/visual layer.
// It no longer replaces the previous CLOSED D1 Fibonacci.


void OnChartEvent(const int id,const long &l,const double &d,const string &s) {
   if(id==CHARTEVENT_CHART_CHANGE) { ServiceVisuals(); return; }
   if(id==CHARTEVENT_OBJECT_CLICK && s==ViewName("DiagNext")) {
      G_DiagPage=(G_DiagPage+1)%MathMax(1,G_DiagPages);
      ObjectSetInteger(0,ViewName("DiagNext"),OBJPROP_STATE,false);
      ServiceVisuals(); return;
   }
   if(id!=CHARTEVENT_OBJECT_CLICK || s!=ViewName("Btn_CloseAll")) return;
   if(DiagnosticMode) { SafetyLog("diagnostics: CLOSE OWN blocked"); return; }
   LatchGlobalStop("manual CLOSE OWN");
   CheckEquityProtection();
   ObjectSetInteger(0,ViewName("Btn_CloseAll"),OBJPROP_STATE,false);
}


// Read-only Fibonacci diagnostics. Never alters trade entry rules or validity flags.


//+------------------------------------------------------------------+

// Modules share application state; each function has one owning source file.
// BEGIN Sniper365/Structure.mqh
// Sniper 3.65: Structure; shared application declarations in the entrypoint.
#ifndef SNIPER365_STRUCTURE_MQH
#define SNIPER365_STRUCTURE_MQH

string StructureConfig() {
   return IntegerToString((int)SF_StructureTF)+":"+IntegerToString(SF_LeftBars)+":"+
      IntegerToString(SF_RightBars)+":"+IntegerToString(SF_LookbackBars)+":"+
      DoubleToString(SF_MinSwingPoints,8)+":"+DoubleToString(SF_BreakBufferPoints,8);
}

bool StructureCurrent() {
   datetime closed=iTime(_Symbol,SF_StructureTF,1);
   if(!SF_DataReady || closed==0 || SF_LastClosed!=closed || SF_ConfirmedDirection==0) return false;
   if(SF_ConfirmedBreakTime==0 || SF_ConfirmedBreakTime>closed) return false;
   if(MaxStructureAgeBars>0) {
      int age=iBarShift(_Symbol,SF_StructureTF,SF_ConfirmedBreakTime,true);
      if(age<0 || age>MaxStructureAgeBars) return false;
   }
   return true;
}

bool SF_High(int shift) {
   double v=SF_Rates[shift].high;
   for(int j=1;j<=SF_LeftBars;j++) if(SF_Rates[shift+j].high>=v) return false;
   for(int j=1;j<=SF_RightBars;j++) if(SF_Rates[shift-j].high>=v) return false;
   return true;
}

bool SF_Low(int shift) {
   double v=SF_Rates[shift].low;
   for(int j=1;j<=SF_LeftBars;j++) if(SF_Rates[shift+j].low<=v) return false;
   for(int j=1;j<=SF_RightBars;j++) if(SF_Rates[shift-j].low<=v) return false;
   return true;
}

void SF_Update()
{
   if(SF_LastClosed==iTime(_Symbol,SF_StructureTF,1) && SF_DataReady) return;
   static ulong retryAfter=0;
   ulong now=GetTickCount64();
   if(!SF_DataReady && now<retryAfter) return;
   retryAfter=now+1000;
   SF_DataReady=false;
   if(SF_LeftBars<1 || SF_RightBars<1 || SF_LookbackBars<SF_LeftBars+SF_RightBars+20 ||
      SF_MinSwingPoints<0 || SF_BreakBufferPoints<0 || SF_HistoryCount<1 || SF_HistoryCount>30)
   { SF_Clear();SF_Status("INVALID INPUTS");return; }
   int bars=Bars(_Symbol,SF_StructureTF);
   if(bars<SF_LeftBars+SF_RightBars+25) {SF_Status("WAITING FOR H4 HISTORY");return;}
   datetime closed=iTime(_Symbol,SF_StructureTF,1);
   if(closed==0) return;
   int needed=SF_LookbackBars+SF_LeftBars+1;
   ArraySetAsSeries(SF_Rates,true);
   if(!SeriesInfoInteger(_Symbol,SF_StructureTF,SERIES_SYNCHRONIZED) ||
      CopyRates(_Symbol,SF_StructureTF,0,needed,SF_Rates)!=needed) return;
   for(int z=0;z<needed;z++)
      if(SF_Rates[z].time==0 || SF_Rates[z].low<=0 || SF_Rates[z].high<SF_Rates[z].low) return;
   // Keep the previous confirmed drawing until a new valid swing is ready.
   // Clearing here used to erase all Fibonacci levels on WAIT states.

   // Build confirmed pivots in chronological order. shift >= RightBars+1:
   // no current (unclosed) bar is ever used for confirmation.
   SF_Pivot pivots[];
   int oldest=MathMin(SF_LookbackBars,bars-SF_LeftBars-1);
   for(int s=oldest;s>=SF_RightBars+1;s--)
   {
      bool hi=SF_High(s),lo=SF_Low(s);
      if(hi==lo) continue; // ambiguous outside bar or neither
      SF_Pivot p;
      p.time=SF_Rates[s].time;
      p.price=hi?SF_Rates[s].high:SF_Rates[s].low;
      p.type=hi?1:-1;
      p.shift=s;
      // Keep every confirmed pivot: replacing an older pivot with a later
      // extreme would retroactively change the historical break simulation.
      int n=ArraySize(pivots);
      ArrayResize(pivots,n+1);
      pivots[n]=p;
   }
   int count=ArraySize(pivots);
   // HH/LH and HL/LL are classified using only confirmed H4 pivots.
   double lastHi=0, prevHi=0, lastLo=0, prevLo=0;
   for(int k=0;k<count;k++) {
      if(pivots[k].type==1) { prevHi=lastHi; lastHi=pivots[k].price; }
      else { prevLo=lastLo; lastLo=pivots[k].price; }
   }
   string highClass=(prevHi>0?(lastHi>prevHi?"HH":(lastHi<prevHi?"LH":"EH")):"H?");
   string lowClass=(prevLo>0?(lastLo>prevLo?"HL":(lastLo<prevLo?"LL":"EL")):"L?");
   SF_PivotStructure=highClass+"/"+lowClass;
   if(count<4) {SF_Status("WAIT: FEWER THAN 4 CONFIRMED PIVOTS");return;}

   // At each CLOSED H4 candle, only pivots whose right-hand confirmation
   // has already closed are eligible. Process breaks once per reference pivot.
   int trend=0;
   int usedHigh=-1,usedLow=-1;
   double buffer=SF_BreakBufferPoints*_Point;
   // Keep only the last N confirmed break events. Each event is reconstructed
   // solely from pivots confirmed by its CLOSED break candle.
   int eventBreak[], eventPivot[], eventOrigin[], eventTrend[], eventType[];
   for(int s=oldest;s>=1;s--)
   {
      int highIdx=-1,lowIdx=-1;
      for(int k=0;k<count;k++)
      {
         if(pivots[k].shift-SF_RightBars<s) continue;
         if(pivots[k].shift<=s) continue;
         if(pivots[k].type==1) highIdx=k;
         else lowIdx=k;
      }
      double c=SF_Rates[s].close;
      if(c<=0) continue;
      bool up=(highIdx>=0 && highIdx!=usedHigh && c>pivots[highIdx].price+buffer);
      bool down=(lowIdx>=0 && lowIdx!=usedLow && c<pivots[lowIdx].price-buffer);
      if(up==down) continue;
      int dir=up?1:-1;
      int broken=up?highIdx:lowIdx;
      if(SF_ConfirmedBreakTime>0 && SF_Rates[s].time>SF_ConfirmedBreakTime &&
         (ArraySize(eventBreak)==0 || SF_Rates[eventBreak[ArraySize(eventBreak)-1]].time<=SF_ConfirmedBreakTime))
         trend=SF_ConfirmedDirection;
      int kind=(trend==-dir)?2:1;
      int origin=-1;
      for(int k=broken-1;k>=0;k--)
         if(pivots[k].type==-dir) {origin=k;break;}
      if(origin<0) continue;
      double p0=pivots[broken].price;
      double p1=pivots[origin].price;
      // A valid UP impulse must end ABOVE its origin; DOWN must end BELOW.
      // Reject invalid geometry before updating trend/used-pivot state.
      if(MathAbs(p0-p1)<MathMax(SF_MinSwingPoints*_Point,_Point)) continue;
      if((dir==1 && p0<=p1) || (dir==-1 && p0>=p1)) continue;
      trend=dir;
      if(up) usedHigh=highIdx;
      else usedLow=lowIdx;
      int n=ArraySize(eventBreak);
      ArrayResize(eventBreak,n+1);
      ArrayResize(eventPivot,n+1);
      ArrayResize(eventOrigin,n+1);
      ArrayResize(eventTrend,n+1);
      ArrayResize(eventType,n+1);
      eventBreak[n]=s;
      eventPivot[n]=broken;
      eventOrigin[n]=origin;
      eventTrend[n]=dir;
      eventType[n]=kind;
   }
   int total=ArraySize(eventBreak);
   if(total==0) {SF_Status("WAIT: NO VALID CONFIRMED BREAK");return;}
   int candidate=total-1;
   datetime candidateTime=SF_Rates[eventBreak[candidate]].time;
   double candidateOrigin=pivots[eventOrigin[candidate]].price;
   double candidateBreak=pivots[eventPivot[candidate]].price;
   if(candidateTime<SF_ConfirmedBreakTime) { SafetyLog("H4 event fell outside reconstruction window"); return; }
   if(candidateTime==SF_ConfirmedBreakTime && SF_ConfirmedBreakTime>0 &&
      (SF_ConfirmedDirection!=eventTrend[candidate] ||
       MathAbs(SF_ConfirmedOrigin-candidateOrigin)>_Point/2 ||
       MathAbs(SF_ConfirmedBreak-candidateBreak)>_Point/2))
   { SafetyLog("H4 same event changed anchors; review history/settings"); return; }
   // Draw deterministic history: previous confirmed breaks remain visible
   // while newer events are added. No orders, and no future bars used.
   SF_Clear();
   DrawConfirmedPivotLabels(pivots,count);
   int nShow=SF_ShowHistory?SF_HistoryCount:1;
   int first=MathMax(0,total-nShow);
   for(int e=first;e<total;e++)
   {
      int broken=eventPivot[e], origin=eventOrigin[e];
      double p0=pivots[broken].price;
      double p1=pivots[origin].price;
      datetime breakTime=iTime(_Symbol,SF_StructureTF,eventBreak[e]);
      // Historical objects have unique names and survive subsequent breaks.
      SF_ActivePrefix=SF_Prefix+IntegerToString((long)breakTime)+"_";
      bool newest=(e==total-1);
      string kind=(eventType[e]==2)?"CHoCH":"BOS/INITIAL";
      if(newest && candidateTime==SF_ConfirmedBreakTime) kind=G_SF_EventLabel;
      DrawStructureEvent(SF_ActivePrefix,pivots[broken].time,p0,breakTime,kind,eventTrend[e],newest);
      if(SF_ShowAnchor)
         SF_Trend("ANCHOR",pivots[origin].time,p1,pivots[broken].time,p0,
                  newest?clrAqua:clrSlateGray);
      // Historical full-width levels would obscure newer setups, so only
      // the most recent event has horizontal price levels and its OTE box.
      if(newest)
      {
         SF_Line("SWING_ORIGIN_1",p1,clrSilver);
         SF_Line("BREAK_LEVEL_0",p0,clrSilver);
         double r050=0.0,r618=0.0;
         if(H4Retracement(eventTrend[e],p1,p0,0.500,r050) &&
            H4Retracement(eventTrend[e],p1,p0,0.618,r618))
         {
            SF_Line("FIB_050",r050,clrSilver);
            SF_Line("FIB_0618",r618,clrGold);
            SF_OTE(breakTime,p0,p1);
         }
      }
   }
   SF_ActivePrefix=SF_Prefix;
   int latest=total-1;
   int broken=eventPivot[latest], origin=eventOrigin[latest];
   bool newEvent=(candidateTime!=SF_ConfirmedBreakTime);
   SF_ConfirmedDirection=eventTrend[latest];
   SF_ConfirmedBreakTime=iTime(_Symbol,SF_StructureTF,eventBreak[latest]);
   SF_ConfirmedOrigin=pivots[origin].price;
   SF_ConfirmedBreak=pivots[broken].price;
   SF_OriginTime=pivots[origin].time; SF_EndpointTime=pivots[broken].time;
   SF_LastClosed=closed;
   SF_DataReady=true;
   if(newEvent) G_SF_EventLabel=(eventType[latest]==2)?"CHoCH":"BOS/INITIAL";
   if(newEvent && !DiagnosticMode && EnableAutoTrade && !SaveSafetyState()) G_StateOK=false;
   string event=G_SF_EventLabel;
   string direction=(eventTrend[latest]==1)?"UP":"DOWN";
   string message=direction+" "+event+" at "+TimeToString(iTime(_Symbol,SF_StructureTF,eventBreak[latest]))+
      " | swing "+DoubleToString(pivots[origin].price,_Digits)+" -> "+
      DoubleToString(pivots[broken].price,_Digits);
   SF_Status(message);
   // One log entry per new event, rather than repeated entries every H4 bar.
   static datetime lastLogged=0;
   datetime eventTime=iTime(_Symbol,SF_StructureTF,eventBreak[latest]);
   if(lastLogged!=eventTime)
   {
      Print("SF26 ",message," | pivot confirmation ",SF_RightBars,
            " closed bars | entry filter");
      lastLogged=eventTime;
   }
   // Chart refresh is handled by MT5, not forced on every H4 reconstruction.
}

void UpdateMTFSwings() {
   static datetime checkedMinute=0; static bool snapshotReady=false;
   datetime minute=iTime(_Symbol,PERIOD_M1,0);
   if(minute>0 && minute==checkedMinute && snapshotReady) return;
   snapshotReady=true;
   static datetime computed[6];
   for(int i = 0; i < 6; i++) {
      datetime frame=iTime(_Symbol,mtf_tfs[i],0);
      if(frame>0 && frame==computed[i] && G_MTF_SwingHigh[i]>0 && G_MTF_SwingLow[i]>0) continue;
      int limit = 150;
      if(!SeriesInfoInteger(_Symbol,mtf_tfs[i],SERIES_SYNCHRONIZED) ||
         Bars(_Symbol,mtf_tfs[i])<limit+Fractal_Strength) {
         snapshotReady=false;
         G_MTF_SwingHigh[i]=0; G_MTF_SwingLow[i]=0;
         G_MTF_SwingHighTime[i]=0; G_MTF_SwingLowTime[i]=0; continue;
      }
      int last_sh = -1, last_sl = -1;

      for(int j = Fractal_Strength + 1; j < limit; j++) {
         bool isHigh = true, isLow = true;
         for(int k = 1; k <= Fractal_Strength; k++) {
            if(iHigh(_Symbol, mtf_tfs[i], j - k) >= iHigh(_Symbol, mtf_tfs[i], j) || iHigh(_Symbol, mtf_tfs[i], j + k) >= iHigh(_Symbol, mtf_tfs[i], j)) isHigh = false;
            if(iLow(_Symbol, mtf_tfs[i], j - k) <= iLow(_Symbol, mtf_tfs[i], j) || iLow(_Symbol, mtf_tfs[i], j + k) <= iLow(_Symbol, mtf_tfs[i], j)) isLow = false;
         }
         if(last_sh == -1 && isHigh) last_sh = j;
         if(last_sl == -1 && isLow) last_sl = j;
         if(last_sh != -1 && last_sl != -1) break;
      }
      computed[i]=frame;
      if(last_sh != -1) { G_MTF_SwingHigh[i] = iHigh(_Symbol, mtf_tfs[i], last_sh); G_MTF_SwingHighTime[i] = iTime(_Symbol, mtf_tfs[i], last_sh); }
      else { G_MTF_SwingHigh[i] = 0; G_MTF_SwingHighTime[i] = 0; }

      if(last_sl != -1) { G_MTF_SwingLow[i] = iLow(_Symbol, mtf_tfs[i], last_sl); G_MTF_SwingLowTime[i] = iTime(_Symbol, mtf_tfs[i], last_sl); }
      else { G_MTF_SwingLow[i] = 0; G_MTF_SwingLowTime[i] = 0; }
   }
   checkedMinute=minute;
}

bool IsSwingHigh(ENUM_TIMEFRAMES tf, int index, int strength) {
   for(int i = 1; i <= strength; i++) {
      if(iHigh(_Symbol, tf, index - i) >= iHigh(_Symbol, tf, index) || iHigh(_Symbol, tf, index + i) >= iHigh(_Symbol, tf, index)) return false;
   }
   return true;
}

bool IsSwingLow(ENUM_TIMEFRAMES tf, int index, int strength) {
   for(int i = 1; i <= strength; i++) {
      if(iLow(_Symbol, tf, index - i) <= iLow(_Symbol, tf, index) || iLow(_Symbol, tf, index + i) <= iLow(_Symbol, tf, index)) return false;
   }
   return true;
}

bool CheckNewBar() {
   datetime currentTime = iTime(_Symbol, _Period, 0);
   if(currentTime != G_LastBarTime) { G_LastBarTime = currentTime; return true; }
   return false;
}

#endif // SNIPER365_STRUCTURE_MQH

// END Sniper365/Structure.mqh
// BEGIN Sniper365/Fibonacci.mqh
// Sniper 3.65: Fibonacci; shared application declarations in the entrypoint.
#ifndef SNIPER365_FIBONACCI_MQH
#define SNIPER365_FIBONACCI_MQH

double RetracementPrice(double origin,double endpoint,double ratio) {
   return endpoint+(origin-endpoint)*ratio;
}

bool TradeOTE(double origin,double endpoint,double &low,double &high) {
   low=0; high=0;
   if(!Positive(origin) || !Positive(endpoint) || MathAbs(endpoint-origin)<=_Point) return false;
   double a=RetracementPrice(origin,endpoint,0.790),b=RetracementPrice(origin,endpoint,1.000);
   low=MathMin(a,b); high=MathMax(a,b);
   return Positive(low) && Positive(high);
}

bool H4Retracement(const int direction,const double origin,const double endpoint,
                   const double ratio,double &price)
{
   price=0.0;
   if(origin<=0.0 || endpoint<=0.0 || ratio<0.0 || ratio>1.0) return false;
   if(direction==1 && endpoint<=origin) return false;
   if(direction==-1 && endpoint>=origin) return false;
   if(direction!=1 && direction!=-1) return false;
   if(MathAbs(endpoint-origin)<=_Point) return false;
   price=RetracementPrice(origin,endpoint,ratio);
   return MathIsValidNumber(price) && price>0.0;
}

void UpdatePreviousDayFibo() {
   datetime day=iTime(_Symbol,PERIOD_D1,0);
   if(day>0 && day==G_D1_SourceDay && G_D1_DataReady) return;
   G_D1_DataReady=false; G_D1_Valid=false; G_Struct_Valid=false;
   G_Fibo_618=0; G_Fibo_790=0; G_Fibo_EQ=0; G_Struct_High=0; G_Struct_Low=0;
   G_D1_Direction=0; G_Fibo_isUp=true;
   G_PredZone_Active=false; G_WickAlertedForCurrentZone=false;
   ObjectDelete(0,ViewName("PredZone")); ObjectDelete(0,ViewName("Txt_PredZone"));
   string lines[]={"Line_000","Line_050","Line_618","Line_Dia2","Line_100","Line_786","Line_Trade100"};
   for(int n=0;n<ArraySize(lines);n++) ObjectDelete(0,ViewName(lines[n]));
   if(day==0 || !SeriesInfoInteger(_Symbol,PERIOD_D1,SERIES_SYNCHRONIZED)) return;
   if(D1_RequireImpulse && (D1_AverageDays<2 || D1_MinRangeMultiplier<=0 || D1_MinBodyRatio<0 || D1_MinBodyRatio>1)) return;
   int needed=D1_RequireImpulse?D1_AverageDays+2:2;
   MqlRates rates[]; ArraySetAsSeries(rates,true);
   if(CopyRates(_Symbol,PERIOD_D1,0,needed,rates)!=needed) return;
   double hi=rates[1].high,lo=rates[1].low,op=rates[1].open,cl=rates[1].close,span=hi-lo;
   if(!Positive(lo) || !Positive(hi) || span<=_Point || rates[1].time<=0) return;
   double avg=0;
   if(D1_RequireImpulse) {
      for(int k=2;k<needed;k++) { double r=rates[k].high-rates[k].low; if(r<=0) return; avg+=r; }
      avg/=D1_AverageDays;
   }
   G_D1_SourceDay=day; G_D1_DataReady=true;
   G_D1_Direction=cl>op?1:(cl<op?-1:0);
   bool impulse=avg>0 && span>=avg*D1_MinRangeMultiplier && MathAbs(cl-op)/span>=D1_MinBodyRatio;
   G_D1_Valid=G_D1_Direction!=0 && (!D1_RequireImpulse || impulse);
   G_Struct_Valid=G_D1_Valid;
   if(!G_D1_Valid) { SafetyLog("D1 rejected: doji or optional impulse filter"); return; }
   bool up=G_D1_Direction==1;
   G_Struct_High=hi; G_Struct_Low=lo; G_Fibo_isUp=up;
   double origin=up?lo:hi,endpoint=up?hi:lo;
   G_Fibo_EQ=RetracementPrice(origin,endpoint,0.500);
   G_Fibo_618=RetracementPrice(origin,endpoint,0.618);
   G_Fibo_790=RetracementPrice(origin,endpoint,0.790);
   CreateFiboLine("Line_000",endpoint,clrGray,STYLE_SOLID,"Previous closed D1 0");
   CreateFiboLine("Line_050",G_Fibo_EQ,clrGray,STYLE_SOLID,"Previous closed D1 0.5");
   CreateFiboLine("Line_618",G_Fibo_618,clrGold,STYLE_SOLID,"D1 REFERENCE 0.618 (not trade entry edge)");
   CreateFiboLine("Line_786",RetracementPrice(origin,endpoint,0.786),Diamond_Color,STYLE_DOT,"D1 REFERENCE 0.786");
   CreateFiboLine("Line_Dia2",G_Fibo_790,Diamond_Color,STYLE_SOLID,"D1 TRADE OTE 0.790 start");
   CreateFiboLine("Line_100",origin,Diamond_Color,STYLE_SOLID,"D1 TRADE OTE 1.000 end");
   Print("SN35 D1 FIBO source=",TimeToString(rates[1].time,TIME_DATE)," current-day=",TimeToString(day,TIME_DATE),
      " direction=",G_D1_Direction," trade OTE=.790-1.000");
}

string GetActiveMacroOTE(double cur) {
   for(int i = 5; i >= 3; i--) {
      if(G_MTF_SwingHigh[i] <= 0 || G_MTF_SwingLow[i] <= 0) continue;
      double r = G_MTF_SwingHigh[i] - G_MTF_SwingLow[i];
      if(r <= 0) continue;

      if(G_MTF_SwingLowTime[i] < G_MTF_SwingHighTime[i]) {
         double ote_top = G_MTF_SwingHigh[i] - r * 0.618;
         double ote_bot = G_MTF_SwingHigh[i] - r * 0.790;
         if(cur >= ote_bot && cur <= ote_top) return mtf_names[i] + " BUY";
      } else {
         double ote_bot = G_MTF_SwingLow[i] + r * 0.618;
         double ote_top = G_MTF_SwingLow[i] + r * 0.790;
         if(cur >= ote_bot && cur <= ote_top) return mtf_names[i] + " SELL";
      }
   }
   return "NONE";
}

#endif // SNIPER365_FIBONACCI_MQH

// END Sniper365/Fibonacci.mqh
// BEGIN Sniper365/SMC.mqh
// Sniper 3.65: SMC; shared application declarations in the entrypoint.
#ifndef SNIPER365_SMC_MQH
#define SNIPER365_SMC_MQH

void RegisterH4Zone(string name,datetime time,double top,datetime until,double bottom,color shade,string label) {
   int n=ArraySize(G_H4ViewZones);
   ArrayResize(G_H4ViewZones,n+1);
   G_H4ViewZones[n].name=name; G_H4ViewZones[n].time=time;
   G_H4ViewZones[n].top=MathMax(top,bottom); G_H4ViewZones[n].bottom=MathMin(top,bottom);
   G_H4ViewZones[n].shade=shade; G_H4ViewZones[n].label=label;
   DrawR(name,time,top,until,bottom,shade,label);
}

double GetVolumeSMA(int period) {
    long vol[];
    if(CopyTickVolume(_Symbol, _Period, 1, period, vol) < period) return 0.0;
    double sum = 0.0;
    for(int i=0; i<period; i++) sum += (double)vol[i];
    return sum / (double)period;
}

string GetNearestOBDistance() {
   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID),nearest=DBL_MAX;
   for(int i=0;i<ArraySize(G_H4ViewZones);i++) {
      if(StringFind(G_H4ViewZones[i].name,"OB_H4_")!=0) continue;
      double distance=price>G_H4ViewZones[i].top?price-G_H4ViewZones[i].top:
         (price<G_H4ViewZones[i].bottom?G_H4ViewZones[i].bottom-price:0);
      nearest=MathMin(nearest,distance);
   }
   return nearest==DBL_MAX?"NONE":DoubleToString(nearest/_Point,0)+" pts";
}

void UpdateH4Zones() {
   static datetime lastClosed=0;
   datetime closed=iTime(_Symbol,PERIOD_H4,1);
   if(closed>0 && closed==lastClosed && ArraySize(G_H4ViewZones)>0) {
      for(int i=0;i<ArraySize(G_H4ViewZones);i++)
         DrawR(G_H4ViewZones[i].name,G_H4ViewZones[i].time,G_H4ViewZones[i].top,
            TimeCurrent()+PeriodSeconds(PERIOD_H4)*10,G_H4ViewZones[i].bottom,
            G_H4ViewZones[i].shade,G_H4ViewZones[i].label);
      return;
   }
   MqlRates r[]; ArraySetAsSeries(r, true);
   int copied = CopyRates(_Symbol, PERIOD_H4, 1, 200, r);
   if(copied < 10 || closed==0) return;
   ArrayResize(G_H4ViewZones,0);
   if(copied==200) lastClosed=closed; // Retry while older H4 history is still loading.
   ObjectsDeleteAll(0,ViewName("OB_H4_")); ObjectsDeleteAll(0,ViewName("FVG_H4_"));
   ObjectsDeleteAll(0,ViewName("Txt_OB_H4_")); ObjectsDeleteAll(0,ViewName("Txt_FVG_H4_"));

   for(int i = 0; i < copied - 2; i++) {
      if(r[i+1].close > r[i+1].open && r[i].close < r[i+1].low) {
         bool mitigated = false;
         for(int j = i - 1; j >= 0; j--) { if(r[j].high > r[i+1].high) { mitigated = true; break; } }
         if(!mitigated) RegisterH4Zone("OB_H4_S_"+TimeToString(r[i+1].time), r[i+1].time, r[i+1].high, TimeCurrent()+PeriodSeconds(PERIOD_H4)*10, r[i+1].low, Color_OB_Sell, "H4 Bearish OB");
      }
      if(r[i+1].close < r[i+1].open && r[i].close > r[i+1].high) {
         bool mitigated = false;
         for(int j = i - 1; j >= 0; j--) { if(r[j].low < r[i+1].low) { mitigated = true; break; } }
         if(!mitigated) RegisterH4Zone("OB_H4_B_"+TimeToString(r[i+1].time), r[i+1].time, r[i+1].high, TimeCurrent()+PeriodSeconds(PERIOD_H4)*10, r[i+1].low, Color_OB_Buy, "H4 Bullish OB");
      }
      if(i+2 < copied) {
         if(r[i].low > r[i+2].high) {
             bool mitigated = false;
             for(int j = i - 1; j >= 0; j--) { if(r[j].low < r[i+2].high) { mitigated = true; break; } }
             if(!mitigated) RegisterH4Zone("FVG_H4_B_"+TimeToString(r[i].time), r[i+2].time, r[i].low, TimeCurrent()+PeriodSeconds(PERIOD_H4)*10, r[i+2].high, Color_FVG_Buy, "H4 Bullish FVG");
         }
         if(r[i].high < r[i+2].low) {
             bool mitigated = false;
             for(int j = i - 1; j >= 0; j--) { if(r[j].high > r[i+2].low) { mitigated = true; break; } }
             if(!mitigated) RegisterH4Zone("FVG_H4_S_"+TimeToString(r[i].time), r[i+2].time, r[i+2].low, TimeCurrent()+PeriodSeconds(PERIOD_H4)*10, r[i].high, Color_FVG_Sell, "H4 Bearish FVG");
         }
      }
   }
}

void CleanInvalidatedZones() {
   double c1 = iClose(_Symbol, _Period, 1);
   int total = OwnObjectsTotal(0, 0, OBJ_RECTANGLE);
   for(int i = total - 1; i >= 0; i--) {
      string name = OwnObjectName(0, i, 0, OBJ_RECTANGLE);
      if(StringFind(name,"OB_H4_")==0 || StringFind(name,"FVG_H4_")==0) continue;
      if(StringFind(name, "OTE_Buy") == 0 || StringFind(name, "OB_H4_B") == 0 || StringFind(name, "FVG_H4_B") == 0) {
         double bot = MathMin(ObjectGetDouble(0,ViewName(name), OBJPROP_PRICE, 0), ObjectGetDouble(0,ViewName(name), OBJPROP_PRICE, 1));
         if(c1 < bot) { ObjectDelete(0,ViewName(name)); ObjectDelete(0,ViewName("Txt_" + name)); }
      }
      else if(StringFind(name, "OTE_Sell") == 0 || StringFind(name, "OB_H4_S") == 0 || StringFind(name, "FVG_H4_S") == 0) {
         double top = MathMax(ObjectGetDouble(0,ViewName(name), OBJPROP_PRICE, 0), ObjectGetDouble(0,ViewName(name), OBJPROP_PRICE, 1));
         if(c1 > top) { ObjectDelete(0,ViewName(name)); ObjectDelete(0,ViewName("Txt_" + name)); }
      }
   }
}

#endif // SNIPER365_SMC_MQH

// END Sniper365/SMC.mqh
// BEGIN Sniper365/Signals.mqh
// Sniper 3.65: Signals; shared application declarations in the entrypoint.
#ifndef SNIPER365_SIGNALS_MQH
#define SNIPER365_SIGNALS_MQH

void ResetSignalAudit() {
   for(int i=0;i<AUDIT_COUNT;i++) {
      G_SignalAudit[i].calls=0; G_SignalAudit[i].read_ok=0; G_SignalAudit[i].candidate_hits=0;
      G_SignalAudit[i].gate_checks=0; G_SignalAudit[i].gate_rejects=0; G_SignalAudit[i].submissions=0;
      G_SignalAudit[i].confirmed_market=0; G_SignalAudit[i].confirmed_pending=0;
   }
   for(int i=0;i<6;i++) { G_MTFAuditFrames[i]=0; G_MTFAuditReady[i]=0; }
}
int AuditModuleIndex(string module) {
   if(module=="SMC_EMA" || module=="EMA") return AUDIT_EMA;
   if(module=="SMC_Comp" || module=="SMC_Comp_Limit" || module=="COMP") return AUDIT_COMP;
   if(module=="SMC_OTE" || module=="SMC_OTE_Reclaim" || module=="OTE") return AUDIT_OTE;
   if(module=="SMC_Sweep" || StringFind(module,"SW")==0) return AUDIT_SWEEP;
   if(module=="SMC_Base" || module=="SMC_Base_ATR" || IsBaseStopModule(module) || module=="BASE") return AUDIT_BASE;
   if(module=="AI NEWS BUY" || module=="AI NEWS SELL" || module=="AI") return AUDIT_AI;
   return -1;
}
void AuditModuleCall(int slot) { G_SignalAudit[slot].calls++; }
void AuditModuleRead(int slot) { G_SignalAudit[slot].read_ok++; }
void AuditCandidateHit(string module) {
   int slot=AuditModuleIndex(module); if(slot>=0) G_SignalAudit[slot].candidate_hits++;
}
void AuditGateCheck(string module,bool rejected) {
   int slot=AuditModuleIndex(module); if(slot<0) return;
   if(rejected) G_SignalAudit[slot].gate_rejects++; else G_SignalAudit[slot].gate_checks++;
}
bool AuditGateReject(string module) { AuditGateCheck(module,true); return false; }
void AuditSubmission(string module,bool confirmed,bool pending) {
   int slot=AuditModuleIndex(module); if(slot<0) return;
   if(!confirmed) G_SignalAudit[slot].submissions++;
   else if(pending) G_SignalAudit[slot].confirmed_pending++;
   else G_SignalAudit[slot].confirmed_market++;
}
void PrintSignalAudit() {
   string modules[]={"SMC_EMA","SMC_Comp","SMC_OTE","SMC_Sweep","SMC_Base","AI"};
   for(int i=0;i<AUDIT_COUNT;i++) Print("SN365 MODULE | module=",modules[i],
      " | calls=",G_SignalAudit[i].calls," | read_ok=",G_SignalAudit[i].read_ok,
      " | candidate_hits=",G_SignalAudit[i].candidate_hits," | gate_checks=",G_SignalAudit[i].gate_checks,
      " | gate_rejects=",G_SignalAudit[i].gate_rejects," | submissions=",G_SignalAudit[i].submissions,
      " | confirmed_market=",G_SignalAudit[i].confirmed_market," | confirmed_pending=",G_SignalAudit[i].confirmed_pending);
   for(int i=0;i<6;i++) Print("SN365 MTF | timeframe=",mtf_names[i]," | frames=",G_MTFAuditFrames[i]," | all_ready=",G_MTFAuditReady[i]);
}

bool SignalModuleEnabled(string module) {
   if(module=="SMC_EMA") return EnableSMC_EMA;
   if(module=="SMC_Comp" || module=="SMC_Comp_Limit") return EnableSMC_Comp;
   if(module=="SMC_OTE") return EnableSMC_OTE && !RequireOTEReclaim;
   if(module=="SMC_OTE_Reclaim") return EnableSMC_OTE && RequireOTEReclaim;
   if(module=="SMC_Sweep") return EnableSMC_Sweep;
   if(module=="SMC_Base" || module=="SMC_Base_ATR") return EnableSMC_Base;
   if(IsBaseStopModule(module)) return EnableSMC_Base && BaseUseStopOrders;
   if(module=="AI NEWS BUY" || module=="AI NEWS SELL") return EnableAICommands;
   return false;
}

bool DirectionAllowed(int side,string &why,string module="") {
   if(!G_D1_DataReady) { why="D1 data not synchronized"; return false; }
   if(D1_RequireDirectionForEntries && (!G_D1_Valid || G_D1_Direction!=(side==POSITION_TYPE_BUY?1:-1))) {
      why="D1 direction/validity"; return false;
   }
   // Market data validity is a safety prerequisite even when direction filters are disabled.
   if(!StructureCurrent()) {
      why="H4 not ready/current"; return false;
   }
   if(module=="SMC_OTE_Reclaim" && AllowOTEReclaimAgainstH4) {
      if(!G_D1_Valid || G_D1_Direction!=(side==POSITION_TYPE_BUY?1:-1) ||
         G_OTEReclaimSignalBar!=iTime(_Symbol,PERIOD_M15,1) || G_OTEReclaimDay!=G_D1_SourceDay ||
         G_OTEReclaimSide!=side) {
         why="confirmed OTE exception requires fresh D1 reclaim"; return false;
      }
      return true; // Only H4 direction/conflict is waived; StructureCurrent already passed.
   }
   // Opt-in matrix row: only the existing D1 deep-retracement module can ignore
   // H4 direction/conflict, never H4 data validity or the shared safety boundary.
   if(AllowD1OTEAgainstH4 && module=="SMC_OTE") {
      if(!G_D1_Valid || G_D1_Direction!=(side==POSITION_TYPE_BUY?1:-1)) {
         why="OTE exception requires D1 direction"; return false;
      }
      return true;
   }
   if(EnforceH4Direction && SF_ConfirmedDirection!=(side==POSITION_TYPE_BUY?1:-1)) {
      why="H4 direction"; return false;
   }
   if(BlockD1H4ConflictForEntries && G_D1_Valid && SF_ConfirmedDirection!=0 &&
      G_D1_Direction!=SF_ConfirmedDirection) { why="D1/H4 conflict"; return false; }
   return true;
}

void CheckAISignals() {
   AuditModuleCall(AUDIT_AI);
   if(!EnableAICommands || !TradingMutationAllowed() || G_StopLatched) return; // Disabled AI never consumes commands.
   string name="ai_signal.txt";
   int handle=FileOpen(name,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(handle==INVALID_HANDLE) return;
   AuditModuleRead(AUDIT_AI);
   string data=FileReadString(handle);
   FileClose(handle);
   string arr[];
   if(StringSplit(data,StringGetCharacter(";",0),arr)<3) { SafetyLog("AI malformed file"); return; }
   if(arr[0]!=_Symbol && arr[0]!="ALL") return;
   if(arr[1]!="BUY" && arr[1]!="SELL") { SafetyLog("AI unknown action"); return; }
   AuditCandidateHit("AI");
   // Consume a matching valid command once, even if rejected. No stale deferred retries.
   if(!FileDelete(name,FILE_COMMON)) { SafetyLog("AI could not claim command"); return; }
   bool buy=(arr[1]=="BUY");
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   double entry=buy?tick.ask:tick.bid;
   double sl=entry+(buy?-1:1)*StopLossPoints*_Point;
   if(SubmitEntry(buy?POSITION_TYPE_BUY:POSITION_TYPE_SELL,false,entry,sl,buy?"AI NEWS BUY":"AI NEWS SELL")) {
      DrawArrow("AI_"+IntegerToString(GetTickCount()),TimeCurrent(),entry,buy?clrAqua:clrMagenta,
                buy?233:234,"AI: "+arr[2],buy);
      SendTelegramPhotoAlert("AI "+arr[1]+": "+arr[2]);
   }
}

void CheckCompressionPhase() {
   AuditModuleCall(AUDIT_COMP);
   if(!G_D1_DataReady || !G_D1_Valid) {
      G_Compression_Active=false; G_CompEntryDone=false; G_CompRetryAt=0;
      DeleteOrdersByComment("SMC_Comp_Limit");
      return;
   }
   // Preserve the original ATR definition and chart geometry. Only the entry latch changes.
   double atr_val[], atr_ma_val[];
   if(CopyBuffer(h_atr,0,0,1,atr_val)!=1 || CopyBuffer(h_atr_ma,0,0,1,atr_ma_val)!=1) return;
   if(!Positive(atr_val[0]) || !Positive(atr_ma_val[0])) return;
   AuditModuleRead(AUDIT_COMP);
   if(atr_val[0]>=atr_ma_val[0]) {
      if(G_Compression_Active) DeleteOrdersByComment("SMC_Comp_Limit");
      G_Compression_Active=false; G_CompEntryDone=false; G_CompRetryAt=0;
      return;
   }
   if(!SeriesInfoInteger(_Symbol,_Period,SERIES_SYNCHRONIZED) || Bars(_Symbol,_Period)<3) return;
   int hi=iHighest(_Symbol,_Period,MODE_HIGH,3,0),lo=iLowest(_Symbol,_Period,MODE_LOW,3,0);
   if(hi<0 || lo<0) return;
   double max_h=iHigh(_Symbol,_Period,hi),min_l=iLow(_Symbol,_Period,lo);
   if(!Positive(min_l) || !Positive(max_h) || max_h<=min_l) return;
   int direction=G_Fibo_isUp?1:-1;
   if(G_CompDay!=G_D1_SourceDay || G_CompDirection!=direction) {
      // An old D1 phase cannot defer its entry into a new daily context.
      DeleteOrdersByComment("SMC_Comp_Limit");
      G_Compression_Active=false; G_CompEntryDone=false; G_CompRetryAt=0;
      G_CompDay=G_D1_SourceDay; G_CompDirection=direction;
   }
   if(!G_Compression_Active) {
      G_Compression_Active=true; G_CompEntryDone=false; G_CompRetryAt=0;
      G_CompHigh=max_h; G_CompLow=min_l;
      DrawDiagnosticSignal("COMP",G_Fibo_isUp?POSITION_TYPE_BUY:POSITION_TYPE_SELL,
         iTime(_Symbol,_Period,0),G_Fibo_isUp?min_l:max_h,"Compression ATR (candidate)");
   } else {
      G_CompHigh=MathMax(G_CompHigh,max_h); G_CompLow=MathMin(G_CompLow,min_l);
   }
   // A temporary gate rejection must not consume the entire compression phase.
   // Re-evaluate only while ATR compression still exists, at most once per 5 model seconds.
   if(G_CompEntryDone || !EnableAutoTrade || DiagnosticMode || !EnableSMC_Comp ||
      TimeCurrent()<G_CompRetryAt) return;
   G_CompRetryAt=TimeCurrent()+5;
   int side=G_Fibo_isUp?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
   double entry=G_Fibo_isUp?q.ask:q.bid;
   double edge=G_Fibo_isUp?min_l:max_h;
   double sl=NormalizeDouble(edge+(G_Fibo_isUp?-15:15)*_Point,_Digits);
   // SubmitEntry rechecks policy, cooldown, uncertain state, broker constraints and cash risk.
   if(!SubmitEntry(side,false,entry,sl,"SMC_Comp")) return;
   G_CompEntryDone=true;
   double limit_entry=NormalizeDouble(edge,_Digits);
   double limit_sl=NormalizeDouble(edge+(G_Fibo_isUp?-1:1)*InvalidationPoints*_Point,_Digits);
   SubmitEntry(side,true,limit_entry,limit_sl,"SMC_Comp_Limit");
}

void CheckLiquiditySweepLive() {
   AuditModuleCall(AUDIT_SWEEP);
   if(!EnableAutoTrade && !DiagnosticMode) return;
   double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   long vol_arr[];
   if(CopyTickVolume(_Symbol, _Period, 0, 1, vol_arr) <= 0) return;
   long current_vol = vol_arr[0];

   double vol_sma = GetVolumeSMA(Vol_SMA_Period);
   if(vol_sma>0) AuditModuleRead(AUDIT_SWEEP);
   bool volume_anomaly = (vol_sma > 0.0 && (double)current_vol > vol_sma * VolSpikeCoef);

   UpdateMTFSwings();

   for(int i = 5; i >= 0; i--) {
      // BUY SWEEP
      if(G_MTF_SwingLow[i] > 0 && current_bid <= G_MTF_SwingLow[i] - MinSweepPoints * _Point) {
         if(volume_anomaly) DrawDiagnosticSignal("SW"+mtf_names[i],POSITION_TYPE_BUY,
            iTime(_Symbol,_Period,0),current_bid,"Sweep+volume "+mtf_names[i]);
         if(volume_anomaly && CanOpenLot(POSITION_TYPE_BUY, "SMC_Sweep") && TimeCurrent() - G_LastBuyTime >= EntryDelayMinutes * 60) {
            double sl = NormalizeDouble(iLow(_Symbol, _Period, 0) - 15 * _Point, _Digits);

            if(SubmitEntry(POSITION_TYPE_BUY,false,current_ask,sl,"SMC_Sweep")) {

               DrawArrow("Sweep_B_" + IntegerToString(GetTickCount()), iTime(_Symbol, _Period, 0), sl, clrLime, 233, "💧 Sweep + Vol BUY", true);
               SendTelegramPhotoAlert("⚡️ СИГНАЛ: Свип ликвидности + ОБЪЕМ\nType: BUY\nТФ: " + mtf_names[i] + "\nУровень: " + DoubleToString(current_ask, _Digits));
            }
         }
      }
      // SELL SWEEP
      if(G_MTF_SwingHigh[i] > 0 && current_ask >= G_MTF_SwingHigh[i] + MinSweepPoints * _Point) {
         if(volume_anomaly) DrawDiagnosticSignal("SW"+mtf_names[i],POSITION_TYPE_SELL,
            iTime(_Symbol,_Period,0),current_ask,"Sweep+volume "+mtf_names[i]);
         if(volume_anomaly && CanOpenLot(POSITION_TYPE_SELL, "SMC_Sweep") && TimeCurrent() - G_LastSellTime >= EntryDelayMinutes * 60) {
            double sl = NormalizeDouble(iHigh(_Symbol, _Period, 0) + 15 * _Point, _Digits);

            if(SubmitEntry(POSITION_TYPE_SELL,false,current_bid,sl,"SMC_Sweep")) {

               DrawArrow("Sweep_S_" + IntegerToString(GetTickCount()), iTime(_Symbol, _Period, 0), sl, clrRed, 234, "💧 Sweep + Vol SELL", false);
               SendTelegramPhotoAlert("⚡️ СИГНАЛ: Свип ликвидности + ОБЪЕМ\nType: SELL\nТФ: " + mtf_names[i] + "\nУровень: " + DoubleToString(current_bid, _Digits));
            }
         }
      }
   }
}

void CheckEMATouchLive() {
   AuditModuleCall(AUDIT_EMA);
   if(!EnableAutoTrade && !DiagnosticMode) return;
   double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double e21[], e55[], e200[];
   if(CopyBuffer(h_ema21, 0, 0, 1, e21) <= 0 || CopyBuffer(h_ema55, 0, 0, 1, e55) <= 0 || CopyBuffer(h_ema200, 0, 0, 1, e200) <= 0) return;

   AuditModuleRead(AUDIT_EMA);
   bool allow_200 = true;
   bool allow_55 = (_Period >= PERIOD_M15);
   bool allow_21 = (_Period >= PERIOD_H1);

   bool uptrend = (e21[0] > e55[0] && e55[0] > e200[0]);
   bool downtrend = (e21[0] < e55[0] && e55[0] < e200[0]);
   double tolerance = 2 * _Point;

   if(uptrend && TimeCurrent() - G_LastBuyTime >= EntryDelayMinutes*60) {
      bool touched = false; double sl = 0;
      if(allow_21 && MathAbs(current_ask - e21[0]) <= tolerance) { touched = true; sl = NormalizeDouble(e55[0], _Digits); }
      else if(allow_55 && MathAbs(current_ask - e55[0]) <= tolerance) { touched = true; sl = NormalizeDouble(e200[0], _Digits); }
      else if(allow_200 && MathAbs(current_ask - e200[0]) <= tolerance) { touched = true; sl = NormalizeDouble(e200[0] - 150*_Point, _Digits); }

      if(touched) DrawDiagnosticSignal("EMA",POSITION_TYPE_BUY,iTime(_Symbol,_Period,0),current_ask,"EMA touch");
      if(touched && CanOpenLot(POSITION_TYPE_BUY, "SMC_EMA")) {

         SubmitEntry(POSITION_TYPE_BUY,false,current_ask,sl,"SMC_EMA");
      }
   }

   if(downtrend && TimeCurrent() - G_LastSellTime >= EntryDelayMinutes*60) {
      bool touched = false; double sl = 0;
      if(allow_21 && MathAbs(current_bid - e21[0]) <= tolerance) { touched = true; sl = NormalizeDouble(e55[0], _Digits); }
      else if(allow_55 && MathAbs(current_bid - e55[0]) <= tolerance) { touched = true; sl = NormalizeDouble(e200[0], _Digits); }
      else if(allow_200 && MathAbs(current_bid - e200[0]) <= tolerance) { touched = true; sl = NormalizeDouble(e200[0] + 150*_Point, _Digits); }

      if(touched) DrawDiagnosticSignal("EMA",POSITION_TYPE_SELL,iTime(_Symbol,_Period,0),current_bid,"EMA touch");
      if(touched && CanOpenLot(POSITION_TYPE_SELL, "SMC_EMA")) {

         SubmitEntry(POSITION_TYPE_SELL,false,current_bid,sl,"SMC_EMA");
      }
   }
}

bool IsBaseStopModule(string module) {
   return module=="SMC_Base_Stop_B" || module=="SMC_Base_Stop_S" ||
      StringFind(module,"SMC_Base_Stop_B:")==0 || StringFind(module,"SMC_Base_Stop_S:")==0;
}
string BaseStopGroup(string module) {
   int colon=StringFind(module,":");
   return colon>=0?StringSubstr(module,colon+1):"";
}
bool IsIndividualBaseModule(string module) {
   return module=="SMC_Base_ATR" || IsBaseStopModule(module);
}

// Only pivots confirmed by closed candles. A profitable target must exist before placing a pending.
double BaseExtremumTarget(const MqlRates &bars[],int side,int wings,double entry,bool latest) {
   if((side!=POSITION_TYPE_BUY && side!=POSITION_TYPE_SELL) || wings<1 || !Positive(entry)) return 0;
   double target=0;
   for(int j=wings;j+wings<ArraySize(bars);j++) {
      double value=side==POSITION_TYPE_BUY?bars[j].high:bars[j].low;
      if(!Positive(value) || (side==POSITION_TYPE_BUY?value<=entry:value>=entry)) continue;
      bool pivot=true;
      for(int k=1;k<=wings;k++) {
         double newer=side==POSITION_TYPE_BUY?bars[j-k].high:bars[j-k].low;
         double older=side==POSITION_TYPE_BUY?bars[j+k].high:bars[j+k].low;
         if(!Positive(newer) || !Positive(older) ||
            (side==POSITION_TYPE_BUY?(value<=newer || value<=older):(value>=newer || value>=older))) {
            pivot=false; break;
         }
      }
      if(!pivot) continue;
      if(latest) return value;
      if(target==0 || (side==POSITION_TYPE_BUY?value<target:value>target)) target=value;
   }
   return target;
}

bool GetBaseStopTarget(int side,double entry,double &target,bool &historyReady) {
   target=0; historyReady=true;
   for(int index=0;index<2;index++) {
      ENUM_TIMEFRAMES tf=index==0?PERIOD_H1:PERIOD_H4;
      if((BaseTargetScope==BASE_TARGET_H1 && tf!=PERIOD_H1) ||
         (BaseTargetScope==BASE_TARGET_H4 && tf!=PERIOD_H4)) continue;
      MqlRates rates[]; ArraySetAsSeries(rates,true);
      if(!SeriesInfoInteger(_Symbol,tf,SERIES_SYNCHRONIZED) ||
         CopyRates(_Symbol,tf,1,BaseSwingLookback,rates)!=BaseSwingLookback) {
         historyReady=false; SafetyLog("BASE STOP: H1/H4 target history unavailable"); return false;
      }
      double candidate=BaseExtremumTarget(rates,side,BaseSwingStrength,entry,false);
      if(Positive(candidate) && (target==0 || (side==POSITION_TYPE_BUY?candidate<target:candidate>target))) target=candidate;
   }
   return Positive(target);
}

bool BaseStopHasPosition() {
   for(int i=0;i<PositionsTotal();i++) {
      ulong t=PositionGetTicket(i);
      if(IsOwnPosition(t) && IsBaseStopModule(PositionGetString(POSITION_COMMENT))) return true;
   }
   return false;
}
bool BaseStopHasPending() {
   for(int i=0;i<OrdersTotal();i++) {
      ulong t=OrderGetTicket(i);
      if(IsOwnOrder(t) && IsBaseStopModule(OrderGetString(ORDER_COMMENT))) return true;
   }
   return false;
}
void CancelBaseStopOrders() {
   if(DiagnosticMode || G_InstanceLock==INVALID_HANDLE) return;
   for(int i=OrdersTotal()-1;i>=0;i--) {
      ulong t=OrderGetTicket(i);
      if(IsOwnOrder(t) && IsBaseStopModule(OrderGetString(ORDER_COMMENT))) SafeDelete(t);
   }
}

// Recover OCO after restart, including a fill that has already closed before reconnection.
bool BaseStopFilledSince(datetime since,string expectedComment,bool &historyReady) {
   string group=BaseStopGroup(expectedComment);
   datetime zone=(datetime)StringToInteger(group);
   if(zone>0 && zone<since) since=zone;
   historyReady=HistorySelect(since,TimeCurrent());
   if(!historyReady) return false;
   for(int i=0;i<HistoryDealsTotal();i++) {
      ulong deal=HistoryDealGetTicket(i); if(deal==0) { historyReady=false; return false; }
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=MagicNumber) continue;
      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT) continue;
      string comment=HistoryDealGetString(deal,DEAL_COMMENT);
      ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
      string original=HistoryOrderGetString(order,ORDER_COMMENT);
      if(original=="" && !IsBaseStopModule(comment)) { historyReady=false; return false; }
      if((IsBaseStopModule(comment) && (group=="" || BaseStopGroup(comment)==group)) ||
         (IsBaseStopModule(original) && (group=="" || BaseStopGroup(original)==group))) return true;
   }
   return false;
}

void CheckBaseStopSetup() {
   AuditModuleCall(AUDIT_BASE);
   if(!SeriesInfoInteger(_Symbol,_Period,SERIES_SYNCHRONIZED)) return;
   datetime closed=iTime(_Symbol,_Period,1);
   if(closed<=0 || closed==G_BaseCheckedBar) return;
   double atr[];
   if(CopyBuffer(h_atr,0,1,1,atr)!=1 || !Positive(atr[0]) || Bars(_Symbol,_Period)<10) return;
   int hi=iHighest(_Symbol,_Period,MODE_HIGH,8,2),lo=iLowest(_Symbol,_Period,MODE_LOW,8,2);
   if(hi<0 || lo<0) return;
   double high=iHigh(_Symbol,_Period,hi),low=iLow(_Symbol,_Period,lo),c1=iClose(_Symbol,_Period,1);
   if(!Positive(low) || !Positive(high) || high<=low || high-low>=atr[0]*1.5) { G_BaseCheckedBar=closed; return; }
   AuditModuleRead(AUDIT_BASE);
   datetime first=iTime(_Symbol,_Period,9);
   DrawR("BaseZone_"+TimeToString(first),first,high,TimeCurrent()+PeriodSeconds()*10,low,clrDarkGray,"BASE");
   if(BaseStopHasPosition()) { G_BaseCheckedBar=closed; G_BaseConsumed=true; CancelBaseStopOrders(); return; }
   if(BaseStopHasPending()) { G_BaseCheckedBar=closed; return; } // Freeze existing order boundaries/targets until execution or expiry.
   G_BaseStopOCOTripped=false;
   if(!Positive(c1) || c1<low || c1>high) { G_BaseCheckedBar=closed; SafetyLog("BASE STOP: closed price already outside BASE; no chase"); return; }
   if(G_BaseConsumed && BaseBreakoutSide(c1,G_BaseLow,G_BaseHigh)>=0) { G_BaseCheckedBar=closed; return; }
   if(BaseRequireVolumeSpike) {
      double sma=GetVolumeSMA(Vol_SMA_Period);
      if(!Positive(sma) || (double)iVolume(_Symbol,_Period,1)<=sma*VolSpikeCoef) {
         G_BaseCheckedBar=closed; SafetyLog("BASE STOP: optional volume filter not confirmed"); return;
      }
   }
   MqlRates stops[]; ArraySetAsSeries(stops,true);
   if(CopyRates(_Symbol,_Period,1,BaseSwingLookback,stops)!=BaseSwingLookback) {
      SafetyLog("BASE STOP: confirmed stop swing history unavailable"); return;
   }
   double targets[2]={0,0};
   for(int side=POSITION_TYPE_BUY;side<=POSITION_TYPE_SELL;side++) {
      bool ready=false;
      GetBaseStopTarget(side,side==POSITION_TYPE_BUY?high:low,targets[side],ready);
      if(!ready) return; // Keep this bar eligible while terminal downloads the target history.
   }
   G_BaseCheckedBar=closed;
   G_BaseHigh=high; G_BaseLow=low; G_BaseStarted=first; G_BaseConsumed=false;
   if(DiagnosticMode || !EnableAutoTrade || !EnableSMC_Base) return;
   for(int side=POSITION_TYPE_BUY;side<=POSITION_TYPE_SELL;side++) {
      if(G_BaseStopOCOTripped || BaseStopHasPosition()) { CancelBaseStopOrders(); return; }
      double entry=side==POSITION_TYPE_BUY?high:low,sl=0;
      if(!BaseSwingStop(stops,side,BaseSwingStrength,BaseSLBufferPoints*_Point,sl)) {
         SafetyLog("BASE STOP: confirmed SL pivot unavailable"); continue;
      }
      double tp=targets[side];
      if(!Positive(tp)) { SafetyLog("BASE STOP: no confirmed target beyond boundary"); continue; }
      string module=(side==POSITION_TYPE_BUY?"SMC_Base_Stop_B:":"SMC_Base_Stop_S:")+IntegerToString((long)first);
      Print("SN365 BASE STOP | zone=",TimeToString(first)," | module=",module,
         " | boundary=",DoubleToString(entry,_Digits)," | target=",DoubleToString(tp,_Digits));
      SubmitEntry(side,true,entry,sl,module,0,1,tp);
   }
}

// Use numerical BASE bounds, never chart-object coordinates for trade decisions.
int BaseBreakoutSide(double close,double low,double high) {
   if(!Positive(close) || !Positive(low) || !Positive(high) || high<=low) return -1;
   if(close<low) return POSITION_TYPE_SELL;
   if(close>high) return POSITION_TYPE_BUY;
   return -1; // A wick/touch is not a confirmed breakout.
}

bool BaseSwingStop(const MqlRates &bars[],int side,int wings,double buffer,double &sl) {
   sl=0;
   if((side!=POSITION_TYPE_BUY && side!=POSITION_TYPE_SELL) || wings<1 || !Positive(buffer)) return false;
   // bars[0] is the breakout candle, all samples are closed. The pivot is confirmed as of its close.
   for(int j=wings;j+wings<ArraySize(bars);j++) {
      double pivot=side==POSITION_TYPE_SELL?bars[j].high:bars[j].low;
      if(!Positive(pivot)) return false;
      bool confirmed=true;
      for(int k=1;k<=wings;k++) {
         if(side==POSITION_TYPE_SELL) {
            if(!Positive(bars[j-k].high) || !Positive(bars[j+k].high) ||
               pivot<=bars[j-k].high || pivot<=bars[j+k].high) { confirmed=false; break; }
         } else {
            if(!Positive(bars[j-k].low) || !Positive(bars[j+k].low) ||
               pivot>=bars[j-k].low || pivot>=bars[j+k].low) { confirmed=false; break; }
         }
      }
      if(confirmed) { sl=pivot+(side==POSITION_TYPE_SELL?buffer:-buffer); return Positive(sl); }
   }
   return false; // No guessed zone-boundary stop if a local pivot is missing.
}

double BaseATRTarget(bool buy,double entry,double atr,double tick,int digits) {
   if(!Positive(entry) || !Positive(atr) || !Positive(tick)) return 0;
   double raw=entry+(buy?2.0:-2.0)*atr;
   if(!Positive(raw)) return 0;
   // Round outward on the broker grid; never put a TP on the wrong side of entry.
   double tp=NormalizeDouble((buy?MathCeil(raw/tick):MathFloor(raw/tick))*tick,digits);
   if(!Positive(tp) || (buy?tp<=entry:tp>=entry)) return 0;
   return tp;
}

void CheckBaseBreakout() {
   if(BaseUseStopOrders) { CheckBaseStopSetup(); return; }
   AuditModuleCall(AUDIT_BASE);
   if(!SeriesInfoInteger(_Symbol,_Period,SERIES_SYNCHRONIZED) || Bars(_Symbol,_Period)<10) return;
   datetime closed=iTime(_Symbol,_Period,1);
   if(closed<=0 || closed==G_BaseCheckedBar) return;
   double atr[];
   if(CopyBuffer(h_atr,0,1,1,atr)!=1 || !Positive(atr[0])) return;
   int ih=iHighest(_Symbol,_Period,MODE_HIGH,8,2),il=iLowest(_Symbol,_Period,MODE_LOW,8,2);
   if(ih<0 || il<0) return;
   double h8=iHigh(_Symbol,_Period,ih),l8=iLow(_Symbol,_Period,il),c1=iClose(_Symbol,_Period,1);
   if(!Positive(h8) || !Positive(l8) || !Positive(c1) || h8<=l8) return;
   G_BaseCheckedBar=closed;
   AuditModuleRead(AUDIT_BASE);
   bool narrow=(h8-l8<atr[0]*1.5);
   // Preserve the original BASE geometry, colours, labels and detection window.
   if(narrow) {
      string b_name="BaseZone_"+TimeToString(iTime(_Symbol,_Period,9));
      DrawR(b_name,iTime(_Symbol,_Period,9),h8,TimeCurrent()+PeriodSeconds()*10,l8,clrDarkGray,"BASE");
   }
   if(G_BaseArmed) {
      int age=iBarShift(_Symbol,_Period,G_BaseArmedBar,true);
      if(age<0 || age>BaseMaxWaitBars) { G_BaseArmed=false; G_BaseConsumed=true; }
   }
   // Prefer the bounds displayed before this breakout, not a recomputed box containing the impulse.
   if(!G_BaseArmed && narrow && (!G_BaseConsumed || BaseBreakoutSide(c1,l8,h8)<0)) {
      G_BaseArmed=true; G_BaseConsumed=false;
      G_BaseHigh=h8; G_BaseLow=l8;
      G_BaseStarted=iTime(_Symbol,_Period,9); G_BaseArmedBar=closed;
   }
   if(!G_BaseArmed) return;
   int side=BaseBreakoutSide(c1,G_BaseLow,G_BaseHigh);
   if(side<0) {
      // While still inside, the most recently painted BASE becomes the next reference.
      if(narrow) {
         G_BaseHigh=h8; G_BaseLow=l8;
         G_BaseStarted=iTime(_Symbol,_Period,9); G_BaseArmedBar=closed;
      }
      return;
   }
   G_BaseArmed=false; G_BaseConsumed=true; // One attempt per confirmed breakout, never chase a rejected move.
   Print("SN365 BASE | breakout=",TimeToString(closed)," | zone=",TimeToString(G_BaseStarted),
      " | low=",DoubleToString(G_BaseLow,_Digits)," | high=",DoubleToString(G_BaseHigh,_Digits),
      " | side=",side==POSITION_TYPE_BUY?"BUY":"SELL");
   DrawDiagnosticSignal("BASE",side,closed,c1,"BASE closed breakout / swing SL / 2 ATR TP");
   if(BaseRequireVolumeSpike) {
      double sma=GetVolumeSMA(Vol_SMA_Period);
      if(!Positive(sma) || (double)iVolume(_Symbol,_Period,1)<=sma*VolSpikeCoef) {
         SafetyLog("SMC_Base_ATR: optional volume spike not confirmed"); return;
      }
   }
   MqlRates rates[]; ArraySetAsSeries(rates,true);
   int count=CopyRates(_Symbol,_Period,1,BaseSwingLookback,rates);
   double sl=0;
   if(count<2*BaseSwingStrength+1 || rates[0].time!=closed ||
      !BaseSwingStop(rates,side,BaseSwingStrength,BaseSLBufferPoints*_Point,sl)) {
      SafetyLog("SMC_Base_ATR: confirmed local swing unavailable"); return;
   }
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
   // Do not enter if the quote has already returned inside the broken boundary.
   if((side==POSITION_TYPE_BUY?q.bid<=G_BaseHigh:q.ask>=G_BaseLow)) {
      SafetyLog("SMC_Base_ATR: quote returned inside BASE"); return;
   }
   if(DiagnosticMode || !EnableAutoTrade || !EnableSMC_Base) return;
   SubmitEntry(side,false,side==POSITION_TYPE_BUY?q.ask:q.bid,sl,"SMC_Base_ATR",atr[0]);
}

void CheckPredictiveZone() {
   AuditModuleCall(AUDIT_OTE);
   if(!G_D1_DataReady || !G_Struct_Valid) return;
   double range = G_Struct_High - G_Struct_Low;
   if(range <= 0) return;
   AuditModuleRead(AUDIT_OTE);

   double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(!G_PredZone_Active) {
       // Preserve legacy activation after .700 retracement; not a CHoCH detector.
       double origin=G_Fibo_isUp?G_Struct_Low:G_Struct_High;
       double endpoint=G_Fibo_isUp?G_Struct_High:G_Struct_Low;
       double edge70=RetracementPrice(origin,endpoint,0.700),tradeLo=0,tradeHi=0;
       if(!TradeOTE(origin,endpoint,tradeLo,tradeHi)) return;
       if(G_Fibo_isUp && current_price < edge70) {
           G_PredZone_High = tradeHi;
           G_PredZone_Low = tradeLo;
           G_PredZone_Active = true;
           G_WickAlertedForCurrentZone = false;
           DrawR("PredZone", iTime(_Symbol, _Period, 1), G_PredZone_High, TimeCurrent() + PeriodSeconds()*10, G_PredZone_Low, clrDimGray, "OTE POI BUY");
       }
       else if(!G_Fibo_isUp && current_price > edge70) {
           G_PredZone_Low = tradeLo;
           G_PredZone_High = tradeHi;
           G_PredZone_Active = true;
           G_WickAlertedForCurrentZone = false;
           DrawR("PredZone", iTime(_Symbol, _Period, 1), G_PredZone_High, TimeCurrent() + PeriodSeconds()*10, G_PredZone_Low, clrDimGray, "OTE POI SELL");
       }
   } else {
       // The frame renderer extends PredZone from numerical state.

       if(G_Fibo_isUp) {
           if(ask <= G_PredZone_High && ask >= G_PredZone_Low) {
               DrawDiagnosticSignal("OTE",POSITION_TYPE_BUY,iTime(_Symbol,_Period,0),ask,"Deep OTE .790-1.000");
               if(!RequireOTEReclaim && EnableAutoTrade && CanOpenLot(POSITION_TYPE_BUY, "SMC_OTE") && TimeCurrent() - G_LastBuyTime >= EntryDelayMinutes*60) {
                   double sl = NormalizeDouble(G_PredZone_Low - InvalidationPoints * _Point, _Digits);

                   if(SubmitEntry(POSITION_TYPE_BUY,false,ask,sl,"SMC_OTE")) {

                       G_PredZone_Active = false;

                   }
               }
           } else if(current_price < G_PredZone_Low - InvalidationPoints * _Point) {
               G_PredZone_Active = false;
           }
       } else {
           if(bid >= G_PredZone_Low && bid <= G_PredZone_High) {
               DrawDiagnosticSignal("OTE",POSITION_TYPE_SELL,iTime(_Symbol,_Period,0),bid,"Deep OTE .790-1.000");
               if(!RequireOTEReclaim && EnableAutoTrade && CanOpenLot(POSITION_TYPE_SELL, "SMC_OTE") && TimeCurrent() - G_LastSellTime >= EntryDelayMinutes*60) {
                   double sl = NormalizeDouble(G_PredZone_High + InvalidationPoints * _Point, _Digits);

                   if(SubmitEntry(POSITION_TYPE_SELL,false,bid,sl,"SMC_OTE")) {

                       G_PredZone_Active = false;

                   }
               }
           } else if(current_price > G_PredZone_High + InvalidationPoints * _Point) {
               G_PredZone_Active = false;
           }
       }
   }
}

// Freeze only H4 blocks whose displacement was closed before the M15 sweep opened.
// Visual H4 zones are deliberately unchanged: trade confirmation uses close-based invalidation.
bool FindOTEOrderBlock(const MqlRates &rates[],bool buy,datetime before,
                       double zoneLow,double zoneHigh,double sweepLow,double sweepHigh,
                       double &obLow,double &obHigh,datetime &obTime,datetime &confirmedAt) {
   obLow=0; obHigh=0; obTime=0; confirmedAt=0;
   int seconds=PeriodSeconds(PERIOD_H4);
   for(int i=0;i+1<ArraySize(rates);i++) {
      if(rates[i].time<=0 || rates[i].time+seconds>before) continue;
      double low=rates[i+1].low,high=rates[i+1].high;
      if(!Positive(low) || !Positive(high) || high<=low ||
         rates[i+1].time>=rates[i].time || high<zoneLow || low>zoneHigh ||
         sweepHigh<low || sweepLow>high) continue;
      bool formed=buy?(rates[i+1].close<rates[i+1].open && rates[i].close>high):
                      (rates[i+1].close>rates[i+1].open && rates[i].close<low);
      if(!formed) continue;
      bool held=true;
      for(int j=i-1;j>=0;j--) {
         if(rates[j].time+seconds>before) continue;
         if(!Positive(rates[j].close) || (buy?rates[j].close<low:rates[j].close>high)) {
            held=false; break;
         }
      }
      if(!held) continue;
      obLow=low; obHigh=high; obTime=rates[i+1].time; confirmedAt=rates[i].time+seconds; return true;
   }
   return false;
}

// Returns 1 for a confirmed return, 0 for waiting, -1 invalidated, -2 expired.
int AdvanceOTEReclaim(OTEReclaimState &state,bool buy,const MqlRates &bar,double level,int maxBars) {
   if(!state.active) return 0;
   state.bars++;
   if(state.bars>maxBars || bar.time-state.sweepTime>=(long)maxBars*PeriodSeconds(PERIOD_M15)) { state.active=false; return -2; }
   if(state.bars>1 && bar.time-state.lastTime!=PeriodSeconds(PERIOD_M15)) { state.active=false; return -1; }
   state.lastTime=bar.time;
   if(!Positive(bar.low) || !Positive(bar.high) || !Positive(bar.open) || !Positive(bar.close) ||
      bar.high<bar.low || bar.close<bar.low || bar.close>bar.high) { state.active=false; return -1; }
   state.extreme=buy?MathMin(state.extreme,bar.low):MathMax(state.extreme,bar.high);
   if(buy?bar.close<state.obLow:bar.close>state.obHigh) { state.active=false; return -1; }
   if(buy?(bar.close>level && bar.close>bar.open):(bar.close<level && bar.close<bar.open)) {
      state.active=false; return 1;
   }
   return 0;
}

bool OTEReclaimQuoteAllowed(bool buy,double bid,double ask,double level,double atr,double multiple) {
   if(!Positive(bid) || !Positive(ask) || ask<bid || !Positive(level) || !Positive(atr) || !Positive(multiple)) return false;
   // Return ABOVE .790 for BUY is intentional: do not require price to remain in the old deep zone.
   return buy?(bid>level && ask-level<=atr*multiple):(ask<level && level-bid<=atr*multiple);
}

void CheckOTEReclaim() {
   if(!RequireOTEReclaim || !EnableSMC_OTE || !G_D1_DataReady || !G_D1_Valid) {
      G_OTEReclaim.active=false; G_OTEReclaimSignalBar=0; return;
   }
   if(G_OTEContextDay!=G_D1_SourceDay || G_OTEContextLow!=G_Struct_Low ||
      G_OTEContextHigh!=G_Struct_High || G_OTEContextDirection!=G_D1_Direction) {
      G_OTEReclaim.active=false; G_OTEReclaimSignalBar=0;
      G_OTEContextDay=G_D1_SourceDay; G_OTEContextLow=G_Struct_Low;
      G_OTEContextHigh=G_Struct_High; G_OTEContextDirection=G_D1_Direction;
   }
   if(!SeriesInfoInteger(_Symbol,PERIOD_M15,SERIES_SYNCHRONIZED)) return;
   MqlRates bars[]; ArraySetAsSeries(bars,true);
   double atr[];
   if(CopyRates(_Symbol,PERIOD_M15,1,2,bars)!=2 || CopyBuffer(h_ote_atr,0,1,1,atr)!=1 || !Positive(atr[0])) return;
   datetime closed=bars[0].time;
   if(closed<=0 || closed==G_OTEReclaimCheckedBar || bars[1].time>=closed || !Positive(bars[1].close)) return;
   G_OTEReclaimCheckedBar=closed;
   G_OTEReclaimSignalBar=0; G_OTEReclaimSide=-1;
   if(closed<G_D1_SourceDay) { G_OTEReclaim.active=false; return; }
   bool buy=G_D1_Direction==1;
   double level=G_Fibo_790;
   if(!Positive(level)) return;
   if(!G_OTEReclaim.active) {
      bool sweep=buy?(bars[1].close>=level && bars[0].low<=level-MinSweepPoints*_Point):
                     (bars[1].close<=level && bars[0].high>=level+MinSweepPoints*_Point);
      if(!sweep) return;
      double zoneLow=0,zoneHigh=0;
      if(!TradeOTE(buy?G_Struct_Low:G_Struct_High,buy?G_Struct_High:G_Struct_Low,zoneLow,zoneHigh)) return;
      if(!SeriesInfoInteger(_Symbol,PERIOD_H4,SERIES_SYNCHRONIZED)) {
         SafetyLog("SMC_OTE_Reclaim: H4 OB history not synchronized"); return;
      }
      MqlRates h4[]; ArraySetAsSeries(h4,true);
      int copied=CopyRates(_Symbol,PERIOD_H4,0,200,h4);
      if(copied<3 || !FindOTEOrderBlock(h4,buy,closed,zoneLow,zoneHigh,bars[0].low,bars[0].high,
         G_OTEReclaim.obLow,G_OTEReclaim.obHigh,G_OTEReclaim.obTime,G_OTEReclaim.confirmedAt)) {
         SafetyLog("SMC_OTE_Reclaim: no pre-existing overlapping held H4 OB"); return;
      }
      // Check intervening closed M15 candles: the block must not have been invalidated before this sweep.
      int shift=iBarShift(_Symbol,PERIOD_M15,G_OTEReclaim.confirmedAt,false);
      if(shift<1 || shift>2000) { SafetyLog("SMC_OTE_Reclaim: OB M15 validation history unavailable"); return; }
      MqlRates history[]; ArraySetAsSeries(history,true);
      if(CopyRates(_Symbol,PERIOD_M15,2,shift,history)!=shift) {
         SafetyLog("SMC_OTE_Reclaim: incomplete OB M15 validation history"); return;
      }
      for(int k=0;k<ArraySize(history);k++) {
         if(history[k].time<G_OTEReclaim.confirmedAt || history[k].time>=closed) continue;
         if(!Positive(history[k].close) || (buy?history[k].close<G_OTEReclaim.obLow:history[k].close>G_OTEReclaim.obHigh)) {
            SafetyLog("SMC_OTE_Reclaim: OB previously invalidated by M15 close"); return;
         }
      }
      G_OTEReclaim.active=true; G_OTEReclaim.bars=0; G_OTEReclaim.sweepTime=closed;
      G_OTEReclaim.extreme=buy?bars[0].low:bars[0].high;
      Print("SN365 OTE ARM | time=",TimeToString(closed)," | level790=",DoubleToString(level,_Digits),
         " | OB=",TimeToString(G_OTEReclaim.obTime)," | low=",DoubleToString(G_OTEReclaim.obLow,_Digits),
         " | high=",DoubleToString(G_OTEReclaim.obHigh,_Digits));
   }
   int result=AdvanceOTEReclaim(G_OTEReclaim,buy,bars[0],level,OTEReclaimMaxBars);
   if(result==-1) { SafetyLog("SMC_OTE_Reclaim: OB invalidated by M15 close / invalid candle"); return; }
   if(result==-2) { SafetyLog("SMC_OTE_Reclaim: confirmation expired"); return; }
   if(result!=1) return;
   int side=buy?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
   DrawDiagnosticSignal("OTE",side,closed,bars[0].close,"D1 .790 sweep + M15 return + held H4 OB");
   MqlTick q;
   if(!SymbolInfoTick(_Symbol,q) || !OTEReclaimQuoteAllowed(buy,q.bid,q.ask,level,atr[0],OTEReclaimMaxDistanceATR)) {
      SafetyLog("SMC_OTE_Reclaim: return lost or quote exceeds M15 ATR distance"); return;
   }
   G_OTEReclaimSignalBar=closed; G_OTEReclaimDay=G_D1_SourceDay; G_OTEReclaimSide=side;
   // Existing OTE exit policy is retained; BASE-specific ATR exits are not silently applied here.
   double sl=NormalizeDouble(buy?G_Struct_Low-InvalidationPoints*_Point:
      G_Struct_High+InvalidationPoints*_Point,_Digits);
   Print("SN365 OTE CONFIRM | time=",TimeToString(closed)," | side=",buy?"BUY":"SELL",
      " | M15_ATR=",DoubleToString(atr[0],_Digits)," | sweepExtreme=",DoubleToString(G_OTEReclaim.extreme,_Digits));
   SubmitEntry(side,false,buy?q.ask:q.bid,sl,"SMC_OTE_Reclaim");
}

void CheckWickTouchesAndAlert() {
   if(!G_Compression_Active || !G_PredZone_Active) return;
   if(G_WickAlertedForCurrentZone) return;
   datetime current_time = iTime(_Symbol, _Period, 0);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   bool signalBuy = false, signalSell = false;
   if(G_Fibo_isUp) { if(bid <= G_PredZone_High && bid >= G_PredZone_Low) signalBuy = true; }
   else { if(ask >= G_PredZone_Low && ask <= G_PredZone_High) signalSell = true; }

   if(signalBuy) {
      DrawArrow("Signal_Buy_" + TimeToString(current_time), current_time, iLow(_Symbol, _Period, 0) - 20*_Point, clrLime, 233, "WICK TOUCH BUY", true);
      SendTelegramPhotoAlert("⚡️ СИГНАЛ: Касание зоны OTE (ВЫХОД ИЗ КОМПРЕССИИ)\nType: BUY\nУровень: " + DoubleToString(bid, _Digits));
      G_WickAlertedForCurrentZone = true;
   }
   else if(signalSell) {
      DrawArrow("Signal_Sell_" + TimeToString(current_time), current_time, iHigh(_Symbol, _Period, 0) + 20*_Point, clrRed, 234, "WICK TOUCH SELL", false);
      SendTelegramPhotoAlert("⚡️ СИГНАЛ: Касание зоны OTE (ВЫХОД ИЗ КОМПРЕССИИ)\nType: SELL\nУровень: " + DoubleToString(ask, _Digits));
      G_WickAlertedForCurrentZone = true;
   }
}

#endif // SNIPER365_SIGNALS_MQH

// END Sniper365/Signals.mqh
// BEGIN Sniper365/RiskManager.mqh
// Sniper 3.65: RiskManager; shared application declarations in the entrypoint.
#ifndef SNIPER365_RISKMANAGER_MQH
#define SNIPER365_RISKMANAGER_MQH

void SafetyLog(string reason) {
   static string previous=""; static datetime at=0;
   if(reason!=previous || TimeCurrent()-at>=60) {
      Print("SN35 SAFETY | ",reason); previous=reason; at=TimeCurrent();
   }
}

bool Positive(double x) { return MathIsValidNumber(x) && x>0; }

bool TradingMutationAllowed() { return EnableAutoTrade && !DiagnosticMode; }

bool HedgingAccount() {
   return AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
}

bool IsOwnPosition(ulong ticket) {
   return ticket>0 && PositionSelectByTicket(ticket) &&
      PositionGetString(POSITION_SYMBOL)==_Symbol &&
      (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber && HedgingAccount();
}

bool IsOwnOrder(ulong ticket) {
   return ticket>0 && OrderSelect(ticket) && OrderGetString(ORDER_SYMBOL)==_Symbol &&
      (ulong)OrderGetInteger(ORDER_MAGIC)==MagicNumber;
}

string SafetyIdentity() {
   return IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"|"+AccountInfoString(ACCOUNT_SERVER)+
      "|"+_Symbol+"|"+IntegerToString((long)MagicNumber);
}

bool SaveSafetyState() {
   if(DiagnosticMode || !EnableAutoTrade) return true;
   string tmp=G_StateFile+".tmp";
   int h=FileOpen(tmp,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,'\t');
   if(h==INVALID_HANDLE) { SafetyLog("cannot write safety state"); return false; }
   uint bytes=FileWrite(h,"SN35-2",SafetyIdentity(),G_StopLatched?1:0,(long)G_LastBuyTime,
      (long)G_LastSellTime,G_ExecutionUncertain?1:0,StructureConfig(),(long)SF_ConfirmedBreakTime,
      SF_ConfirmedDirection,DoubleToString(SF_ConfirmedOrigin,16),DoubleToString(SF_ConfirmedBreak,16),G_SF_EventLabel,"END");
   FileFlush(h); FileClose(h);
   if(bytes==0 || !FileMove(tmp,FILE_COMMON,G_StateFile,FILE_COMMON|FILE_REWRITE)) {
      SafetyLog("cannot commit safety state; entries blocked"); return false;
   }
   return true;
}

string FreshTesterPrefix(string identityHash) {
   string seed="Sniper363_TEST_"+identityHash+"_"+IntegerToString((long)TimeLocal())+"_"+
      IntegerToString((long)GetMicrosecondCount())+"_"+IntegerToString(ChartID())+"_";
   for(int serial=0;serial<64;serial++) {
      string prefix=seed+IntegerToString(serial)+"_";
      if(FileIsExist(prefix+"state.tsv",FILE_COMMON) || FileIsExist(prefix+"stop",FILE_COMMON) ||
         FileIsExist(prefix+"state.tsv.lock",FILE_COMMON)) continue;
      if(DiagnosticMode) return prefix; // Read-only; no state is imported or written.
      // Reserve this namespace before reading any file; competing agents cannot share it.
      G_InstanceLock=FileOpen(prefix+"state.tsv.lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(G_InstanceLock!=INVALID_HANDLE) return prefix;
   }
   SafetyLog("cannot reserve fresh tester namespace; initialization blocked");
   return "";
}

bool InitSafetyState() {
   string identity=SafetyIdentity();
   uint hash=2166136261;
   for(int i=0;i<StringLen(identity);i++) hash=(hash^(uint)StringGetCharacter(identity,i))*16777619;
   if(MQLInfoInteger(MQL_TESTER)) {
      string prefix=FreshTesterPrefix(IntegerToString((long)hash));
      if(prefix=="") return false;
      G_StateFile=prefix+"state.tsv"; G_StopFile=prefix+"stop";
   } else {
      G_StateFile="Sniper35_LIVE_"+IntegerToString((long)hash)+".tsv";
      G_StopFile="Sniper35_LIVE_"+IntegerToString((long)hash)+".stop";
   }
   if(!DiagnosticMode && G_InstanceLock==INVALID_HANDLE) {
      // No share flags: only one mutating LIVE instance per account/server/symbol/Magic.
      G_InstanceLock=FileOpen(G_StateFile+".lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(G_InstanceLock==INVALID_HANDLE) { SafetyLog("another instance or inaccessible safety lock"); return false; }
   }
   G_StopLatched=FileIsExist(G_StopFile,FILE_COMMON);
   if(FileIsExist(G_StateFile,FILE_COMMON)) {
      int h=FileOpen(G_StateFile,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON,'\t');
      if(h==INVALID_HANDLE) return false;
      string version=FileReadString(h), storedIdentity=FileReadString(h);
      string stopped=FileReadString(h),buy=FileReadString(h),sell=FileReadString(h),uncertain=FileReadString(h);
      string cfg=FileReadString(h),t=FileReadString(h),dir=FileReadString(h);
      string origin=FileReadString(h),endpoint=FileReadString(h),eventLabel=FileReadString(h),footer=FileReadString(h);
      FileClose(h);
      if(version!="SN35-2" || storedIdentity!=identity || footer!="END" ||
         (stopped!="0" && stopped!="1") || (uncertain!="0" && uncertain!="1")) {
         SafetyLog("invalid safety state; manual reconciliation required"); return false;
      }
      G_StopLatched=G_StopLatched || stopped=="1";
      G_LastBuyTime=(datetime)StringToInteger(buy); G_LastSellTime=(datetime)StringToInteger(sell);
      G_ExecutionUncertain=uncertain=="1";
      if(cfg==StructureConfig()) {
         SF_ConfirmedBreakTime=(datetime)StringToInteger(t);
         SF_ConfirmedDirection=(int)StringToInteger(dir);
         G_SF_EventLabel=eventLabel;
         SF_ConfirmedOrigin=StringToDouble(origin); SF_ConfirmedBreak=StringToDouble(endpoint);
         if(SF_ConfirmedBreakTime>0 &&
            (!Positive(SF_ConfirmedOrigin) || !Positive(SF_ConfirmedBreak) ||
             (SF_ConfirmedDirection!=1 && SF_ConfirmedDirection!=-1))) return false;
      }
   }
   SafetyLog("state "+G_StateFile+(G_StopLatched?" STOP LATCHED":"")+
      (G_ExecutionUncertain?" EXECUTION UNCERTAIN":""));
   return SaveSafetyState();
}

void LatchGlobalStop(string reason) {
   if(DiagnosticMode) return;
   bool first=!G_StopLatched; G_StopLatched=true; // Set BEFORE any broker operation.
   if(!FileIsExist(G_StopFile,FILE_COMMON)) {
      int h=FileOpen(G_StopFile,FILE_WRITE|FILE_TXT|FILE_COMMON);
      if(h==INVALID_HANDLE) G_StateOK=false;
      else { if(FileWriteString(h,SafetyIdentity()+"\r\n"+reason)==0) G_StateOK=false; FileFlush(h); FileClose(h); }
   }
   if(!SaveSafetyState()) G_StateOK=false;
   if(first) {
      SafetyLog("GLOBAL STOP LATCHED: "+reason+"; no automatic reset, including restart");
      G_StopNoticePending=true;
   }
}

void RefreshMarketContext() {
   SF_Update();
   static int drawnDir=0; static double drawnOrigin=0,drawnEnd=0;
   static datetime drawnTime=0;
   if(drawnDir!=SF_ConfirmedDirection || drawnOrigin!=SF_ConfirmedOrigin ||
      drawnEnd!=SF_ConfirmedBreak || drawnTime!=SF_ConfirmedBreakTime) {
      DrawStructureAndFibo(); // Cache all anchors, not only event timestamp.
      drawnDir=SF_ConfirmedDirection; drawnOrigin=SF_ConfirmedOrigin;
      drawnEnd=SF_ConfirmedBreak; drawnTime=SF_ConfirmedBreakTime;
   }
   UpdatePreviousDayFibo();
}

bool OwnFloatingPNL(double &pnl) {
   pnl=0;
   for(int i=PositionsTotal()-1;i>=0;i--) {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) return false;
      if(IsOwnPosition(ticket)) pnl+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return MathIsValidNumber(pnl);
}

bool DailyAllowed() {
   if(DailyLossLimitPercent<=0) return true; // No arbitrary new default threshold.
   datetime day=iTime(_Symbol,PERIOD_D1,0);
   if(day==0 || !HistorySelect(day,TimeCurrent())) return false;
   double realized=0,floating=0;
   for(int i=0;i<HistoryDealsTotal();i++) {
      ulong t=HistoryDealGetTicket(i); if(t==0) return false;
      if(HistoryDealGetString(t,DEAL_SYMBOL)==_Symbol &&
         (ulong)HistoryDealGetInteger(t,DEAL_MAGIC)==MagicNumber)
         realized+=HistoryDealGetDouble(t,DEAL_PROFIT)+HistoryDealGetDouble(t,DEAL_SWAP)+
            HistoryDealGetDouble(t,DEAL_COMMISSION)+HistoryDealGetDouble(t,DEAL_FEE);
   }
   if(!OwnFloatingPNL(floating)) return false;
   double base=AccountInfoDouble(ACCOUNT_BALANCE)-realized;
   return Positive(base) && realized+floating>-(base*DailyLossLimitPercent/100.0);
}

bool EntryPolicy(int side,string comment,bool pending,bool existing) {
   AuditGateCheck(comment,false);
   string why="";
   if(side!=POSITION_TYPE_BUY && side!=POSITION_TYPE_SELL) why="invalid side";
   else if(!TradingMutationAllowed()) why="AutoTrade off or explicit diagnostic mode";
   else if(G_InstanceLock==INVALID_HANDLE) why="mutating instance lock not owned";
   else if(!HedgingAccount()) why="netting/exchange account unsupported: ownership cannot be isolated";
   else if(!G_StateOK || G_ExecutionUncertain) why="state/uncertain execution requires reconciliation";
   else if(G_StopLatched || FileIsExist(G_StopFile,FILE_COMMON)) { G_StopLatched=true; why="global stop latched"; }
   else if(!DailyAllowed()) why="daily limit or history unavailable";
   else if(!SignalModuleEnabled(comment)) why="module disabled/unknown";
   else if(!DirectionAllowed(side,why,comment)) { /* reason supplied */ }
   if(why!="") { SafetyLog(comment+": "+why); return AuditGateReject(comment); }
   if(existing) return true; // No self-duplicate/cooldown rejection of an existing pending.
   datetime last=side==POSITION_TYPE_BUY?G_LastBuyTime:G_LastSellTime;
   // A paired compression limit still passes exposure/risk/SL checks. It is not another market entry.
   if((!pending || IsBaseStopModule(comment)) && (TimeCurrent()<last || TimeCurrent()-last<EntryDelayMinutes*60)) {
      SafetyLog(comment+": cooldown"); return AuditGateReject(comment);
   }
   for(int i=0;i<PositionsTotal();i++) {
      ulong t=PositionGetTicket(i);
      if(t==0) return AuditGateReject(comment);
      if(IsOwnPosition(t) && PositionGetString(POSITION_COMMENT)==comment) {
         SafetyLog(comment+": duplicate position"); return AuditGateReject(comment);
      }
   }
   for(int i=0;i<OrdersTotal();i++) {
      ulong t=OrderGetTicket(i);
      if(t==0) return AuditGateReject(comment);
      if(IsOwnOrder(t) && OrderGetString(ORDER_COMMENT)==comment) {
         SafetyLog(comment+": duplicate pending"); return AuditGateReject(comment);
      }
   }
   return true;
}

bool LossAtSL(int side,double volume,double entry,double sl,double &loss) {
   loss=0;
   if(!Positive(volume) || !Positive(entry) || !Positive(sl)) return false;
   double profit=0;
   if(!OrderCalcProfit(side==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,entry,sl,profit) ||
      !MathIsValidNumber(profit)) return false;
   loss=MathMax(0,-profit); return true;
}

bool OwnExposure(double &risk,double &buyVolume,double &sellVolume,double &pendingMargin) {
   risk=0; buyVolume=0; sellVolume=0; pendingMargin=0;
   for(int i=0;i<PositionsTotal();i++) {
      ulong t=PositionGetTicket(i); if(t==0) return false;
      if(!IsOwnPosition(t)) continue;
      int side=(int)PositionGetInteger(POSITION_TYPE);
      double v=PositionGetDouble(POSITION_VOLUME),loss=0;
      if(!LossAtSL(side,v,PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_SL),loss)) return false;
      risk+=loss; if(side==POSITION_TYPE_BUY) buyVolume+=v; else sellVolume+=v;
   }
   for(int i=0;i<OrdersTotal();i++) {
      ulong t=OrderGetTicket(i); if(t==0) return false;
      if(!IsOwnOrder(t)) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      int side;
      if(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT) side=POSITION_TYPE_BUY;
      else if(type==ORDER_TYPE_SELL_LIMIT || type==ORDER_TYPE_SELL_STOP || type==ORDER_TYPE_SELL_STOP_LIMIT) side=POSITION_TYPE_SELL;
      else return false;
      double v=OrderGetDouble(ORDER_VOLUME_CURRENT),entry=OrderGetDouble(ORDER_PRICE_OPEN),loss=0,margin=0;
      if(!LossAtSL(side,v,entry,OrderGetDouble(ORDER_SL),loss) ||
         !OrderCalcMargin(side==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,v,entry,margin)) return false;
      risk+=loss; pendingMargin+=margin; if(side==POSITION_TYPE_BUY) buyVolume+=v; else sellVolume+=v;
   }
   return MathIsValidNumber(risk) && MathIsValidNumber(pendingMargin);
}

bool SafeVolume(int side,double entry,double sl,double &volume,double riskMultiplier=1.0) {
   volume=0;
   if(!MathIsValidNumber(riskMultiplier) || riskMultiplier<=0 || riskMultiplier>1) return false;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(!Positive(step) || !Positive(minV) || !Positive(maxV) || minV>maxV || !Positive(tick) || !Positive(tv) ||
      !Positive(_Point) || !Positive(entry) || !Positive(sl) ||
      (side==POSITION_TYPE_BUY?sl>=entry:sl<=entry)) { SafetyLog("lot: invalid symbol properties/SL"); return false; }
   double balance=AccountInfoDouble(ACCOUNT_BALANCE),lossMin=0;
   if(!Positive(balance) || !LossAtSL(side,minV,entry,sl,lossMin) || !Positive(lossMin)) {
      SafetyLog("lot: OrderCalcProfit failed/zero loss"); return false;
   }
   double raw=balance*GetDynamicRisk()/100.0*riskMultiplier*minV/lossMin;
   volume=NormalizeDouble(MathFloor(MathMin(raw,maxV)/step)*step,8);
   if(volume<minV || volume<=0) { volume=0; SafetyLog("lot: minimum exceeds risk budget"); return false; }
   double actual=0;
   if(!LossAtSL(side,volume,entry,sl,actual) || actual>balance*GetDynamicRisk()/100.0*riskMultiplier+1e-8) {
      volume=0; SafetyLog("lot: rounded cash risk exceeds budget"); return false;
   }
   return true;
}

bool TradeResult(bool ok,bool pending,string action) {
   uint code=trade.ResultRetcode();
   bool accepted=ok && (pending?((code==TRADE_RETCODE_PLACED || code==TRADE_RETCODE_DONE) && trade.ResultOrder()>0):
      ((code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL)));
   Print("SN35 EXEC | ",action," | retcode=",code," | order=",trade.ResultOrder()," deal=",trade.ResultDeal());
   return accepted;
}

bool DefiniteEntryRejection(uint code,ulong order,ulong deal,double volume) {
   if(order!=0 || deal!=0 || !MathIsValidNumber(volume) || volume!=0) return false;
   return code==TRADE_RETCODE_MARKET_CLOSED || code==TRADE_RETCODE_INVALID_VOLUME ||
      code==TRADE_RETCODE_INVALID_PRICE || code==TRADE_RETCODE_INVALID_STOPS ||
      code==TRADE_RETCODE_NO_MONEY || code==TRADE_RETCODE_TRADE_DISABLED ||
      code==TRADE_RETCODE_INVALID_FILL;
}

void ResolveEntryRejection(string comment) {
   if(!DefiniteEntryRejection(trade.ResultRetcode(),trade.ResultOrder(),trade.ResultDeal(),trade.ResultVolume())) {
      SafetyLog(comment+": submission unconfirmed; reconcile state before new entry"); return;
   }
   G_ExecutionUncertain=false;
   if(!SaveSafetyState()) {
      G_ExecutionUncertain=true; G_StateOK=false;
      SafetyLog(comment+": definite rejection, but state commit failed; entries blocked"); return;
   }
   G_EntryRetryAfter=TimeCurrent()+60;
   SafetyLog(comment+": definitively rejected, no fill; entry retry paused 60 model seconds");
}

bool SubmitEntry(int side,bool pending,double proposedEntry,double proposedSL,string comment,double baseATR=0.0,int basePendingKind=0,double baseTarget=0.0) {
   RefreshMarketContext(); CheckEquityProtection();
   if(!EntryPolicy(side,comment,pending,false)) return false;
   if(TimeCurrent()<G_EntryRetryAfter) return false;
   MqlTick quote;
   if(!SymbolInfoTick(_Symbol,quote) || !Positive(quote.ask) || !Positive(quote.bid)) return false;
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(!Positive(tick)) { SafetyLog("entry: invalid tick size"); return false; }
   bool baseStop=IsBaseStopModule(comment);
   if(baseStop && (!pending || basePendingKind!=1)) {
      SafetyLog("BASE STOP: invalid pending request"); return false;
   }
   if(!baseStop && (basePendingKind!=0 || baseTarget!=0)) { SafetyLog("BASE STOP: pending arguments on another module"); return false; }
   double entry=pending?NormalizeDouble((baseStop?(side==POSITION_TYPE_BUY?MathCeil(proposedEntry/tick):MathFloor(proposedEntry/tick)):MathRound(proposedEntry/tick))*tick,_Digits):
      (side==POSITION_TYPE_BUY?quote.ask:quote.bid);
   double sl=NormalizeDouble((side==POSITION_TYPE_BUY?MathFloor(proposedSL/tick):MathCeil(proposedSL/tick))*tick,_Digits);
   double minDistance=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   bool buy=side==POSITION_TYPE_BUY;
   if(!Positive(sl) || (buy?sl>=entry:sl<=entry) || MathAbs(entry-sl)<minDistance ||
      (!pending && (buy?quote.bid-sl:sl-quote.ask)<minDistance) ||
      (pending && (baseStop?(buy?entry-quote.ask:quote.bid-entry):(buy?quote.ask-entry:entry-quote.bid))<=minDistance)) {
      SafetyLog(comment+": invalid side/distance/grid of entry or SL"); return false;
   }
   double tp=0;
   if(baseStop) {
      long allowed=SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE);
      long required=SYMBOL_ORDER_STOP;
      if((allowed & required)==0) { SafetyLog("BASE STOP: broker does not support requested order type"); return false; }
      tp=NormalizeDouble((buy?MathFloor(baseTarget/tick):MathCeil(baseTarget/tick))*tick,_Digits);
      if(!Positive(tp) || (buy?tp-entry:entry-tp)<=minDistance || baseATR!=0) {
         SafetyLog("BASE STOP: target unavailable/too close or unsupported ATR target"); return false;
      }

   }
   if(comment=="SMC_Base_ATR") {
      if(pending) { SafetyLog("SMC_Base_ATR: pending entry unsupported"); return false; }
      tp=BaseATRTarget(buy,entry,baseATR,tick,_Digits);
      if(!Positive(tp) || (buy?tp-quote.bid:quote.ask-tp)<minDistance) {
         SafetyLog("SMC_Base_ATR: invalid ATR TP / broker distance"); return false;
      }
   } else if(baseATR!=0) { SafetyLog("ATR TP only supported for BASE entries"); return false; }
   double volume=0;
   bool counterOTE=AllowD1OTEAgainstH4 && comment=="SMC_OTE" &&
      SF_ConfirmedDirection!=(side==POSITION_TYPE_BUY?1:-1);
   bool counterReclaim=AllowOTEReclaimAgainstH4 && comment=="SMC_OTE_Reclaim" &&
      SF_ConfirmedDirection!=(side==POSITION_TYPE_BUY?1:-1);
   double riskMultiplier=counterReclaim?0.5:(counterOTE?CounterTrendRiskMult:1.0);
   if(!SafeVolume(side,entry,sl,volume,riskMultiplier)) return false;
   double risk=0,buyVol=0,sellVol=0,reservedMargin=0,loss=0,margin=0;
   if(!OwnExposure(risk,buyVol,sellVol,reservedMargin) || !LossAtSL(side,volume,entry,sl,loss)) {
      SafetyLog(comment+": exposure unavailable or unprotected own position/order"); return false;
   }
   double balance=AccountInfoDouble(ACCOUNT_BALANCE),step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double cap=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),MathFloor((balance/10000.0)/step)*step);
   if((buy?buyVol:sellVol)+volume>cap+1e-8 || risk+loss>balance*GetDynamicGlobalRisk()/100.0+1e-8) {
      SafetyLog(comment+": projected volume/global cash-risk cap"); return false;
   }
   if(!OrderCalcMargin(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,entry,margin) ||
      !MathIsValidNumber(margin) || margin+reservedMargin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) {
      SafetyLog(comment+": insufficient margin"); return false;
   }
   MqlTradeRequest request={}; MqlTradeCheckResult check={};
   request.action=pending?TRADE_ACTION_PENDING:TRADE_ACTION_DEAL;
   request.type=pending?(baseStop?(buy?ORDER_TYPE_BUY_STOP:ORDER_TYPE_SELL_STOP):
      (buy?ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_SELL_LIMIT)):(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL);
   request.symbol=_Symbol; request.magic=MagicNumber; request.volume=volume;
   request.price=entry; request.stoplimit=0; request.sl=sl; request.tp=tp; request.comment=comment;
   request.type_time=ORDER_TIME_GTC; request.expiration=0; request.deviation=10;
   if(baseStop && (SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_SPECIFIED)!=0) {
      request.type_time=ORDER_TIME_SPECIFIED;
      request.expiration=TimeCurrent()+(long)BaseMaxWaitBars*PeriodSeconds(_Period);
   }
   long modes=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if(pending) request.type_filling=ORDER_FILLING_RETURN;
   else if((modes & SYMBOL_FILLING_FOK)!=0) request.type_filling=ORDER_FILLING_FOK;
   else if((modes & SYMBOL_FILLING_IOC)!=0) request.type_filling=ORDER_FILLING_IOC;
   else if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE)!=SYMBOL_TRADE_EXECUTION_MARKET)
      request.type_filling=ORDER_FILLING_RETURN;
   else { SafetyLog(comment+": unsupported filling mode"); return false; }
   if(!OrderCheck(request,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE)) { SafetyLog(comment+": OrderCheck failed code="+IntegerToString(check.retcode)); return false; }
   Print("SN364 ENTRY | module=",comment," | policy=",counterReclaim?"CONFIRMED_OTE_HALF_RISK":(counterOTE?"D1_OTE_OVERRIDE":"STRICT"),
      " | riskMultiplier=",DoubleToString(riskMultiplier,3)," | sl=",DoubleToString(sl,_Digits),
      " | volume=",DoubleToString(volume,8)," | tp=",DoubleToString(tp,_Digits));
   // Persist uncertain state BEFORE network submission. Crash/timeout cannot silently retry on restart.
   G_ExecutionUncertain=true;
   if(!SaveSafetyState()) { G_StateOK=false; return false; }
   AuditSubmission(comment,false,pending);
   trade.SetAsyncMode(false); trade.SetDeviationInPoints(10); trade.SetTypeFilling(request.type_filling);
   bool ok=false;
   if(baseStop) {
      ok=trade.OrderOpen(_Symbol,request.type,volume,0,entry,sl,tp,request.type_time,request.expiration,comment);
   } else if(pending) {
      if(buy) ok=trade.BuyLimit(volume,entry,_Symbol,sl,0,ORDER_TIME_GTC,0,comment);
      else ok=trade.SellLimit(volume,entry,_Symbol,sl,0,ORDER_TIME_GTC,0,comment);
   } else {
      if(buy) ok=trade.Buy(volume,_Symbol,entry,sl,tp,comment);
      else ok=trade.Sell(volume,_Symbol,entry,sl,tp,comment);
   }
   bool accepted=TradeResult(ok,pending,comment);
   if(!pending && (trade.ResultDeal()==0 || !Positive(trade.ResultVolume()))) accepted=false;
   // Explicit rejection can be safely released; ambiguous/partial results remain latched.
   if(!accepted) { ResolveEntryRejection(comment); return false; }
   // Do not let an immediately following paired limit underestimate an unreflected fill.
   ulong resultOrder=trade.ResultOrder();
   bool visible=pending?(IsOwnOrder(resultOrder) || IsOwnPosition(resultOrder)):IsOwnPosition(resultOrder);
   if(!visible) { SafetyLog(comment+": confirmed result not yet visible; reconcile before further requests"); return false; }
   AuditSubmission(comment,true,pending);
   G_ExecutionUncertain=false;
   if(!pending) { if(buy) G_LastBuyTime=TimeCurrent(); else G_LastSellTime=TimeCurrent(); }
   if(!SaveSafetyState()) G_StateOK=false;
   return accepted;
}

bool SafeDelete(ulong ticket) {
   if(DiagnosticMode || G_InstanceLock==INVALID_HANDLE || !IsOwnOrder(ticket)) return false;
   if(TimeCurrent()<G_PendingCancelRetryAfter) return false;
   bool accepted=TradeResult(trade.OrderDelete(ticket),false,"delete own pending");
   if(accepted) G_PendingCancelRetryAfter=0;
   else G_PendingCancelRetryAfter=TimeCurrent()+(trade.ResultRetcode()==TRADE_RETCODE_MARKET_CLOSED?60:5);
   return accepted;
}

bool SafeClose(ulong ticket) {
   if(DiagnosticMode || G_InstanceLock==INVALID_HANDLE || !IsOwnPosition(ticket)) return false;
   bool ok=trade.PositionClose(ticket);
   return TradeResult(ok,false,"close own position");
}

bool SafeModify(ulong ticket,double sl,double tp) {
   if(!TradingMutationAllowed() || G_InstanceLock==INVALID_HANDLE || !IsOwnPosition(ticket)) return false;
   long side=PositionGetInteger(POSITION_TYPE);
   double old=PositionGetDouble(POSITION_SL),tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(!Positive(tick)) return false;
   sl=NormalizeDouble((side==POSITION_TYPE_BUY?MathFloor(sl/tick):MathCeil(sl/tick))*tick,_Digits);
   if(old>0 && (side==POSITION_TYPE_BUY?sl<=old:sl>=old)) return false;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return false;
   double distance=MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
      SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   if(!Positive(sl) || (side==POSITION_TYPE_BUY?q.bid-sl:sl-q.ask)<=distance) return false;
   return TradeResult(trade.PositionModify(ticket,sl,tp),false,"modify own SL");
}

void ReviewOwnPending() {
   if(DiagnosticMode) return; // Absolutely no broker mutations in diagnostics.
   double risk=0,bv=0,sv=0,margin=0;
   bool exposureOK=OwnExposure(risk,bv,sv,margin);
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double cap=Positive(step)?MathMax(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),MathFloor(balance/10000.0/step)*step):0;
   bool invalidExposure=!exposureOK || !Positive(balance) || risk>balance*GetDynamicGlobalRisk()/100.0+1e-8 ||
      bv>cap+1e-8 || sv>cap+1e-8 || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   for(int i=OrdersTotal()-1;i>=0;i--) {
      ulong ticket=OrderGetTicket(i); if(!IsOwnOrder(ticket)) continue;
      long type=OrderGetInteger(ORDER_TYPE);
      int side=(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT)?
         POSITION_TYPE_BUY:POSITION_TYPE_SELL;
      string comment=OrderGetString(ORDER_COMMENT);
      bool invalidBase=false;
      if(IsBaseStopModule(comment)) {
         datetime setup=(datetime)OrderGetInteger(ORDER_TIME_SETUP);
         double tp=OrderGetDouble(ORDER_TP);
         bool ready=false,filled=BaseStopFilledSince(setup,comment,ready);
         MqlTick q; bool quoted=SymbolInfoTick(_Symbol,q) && Positive(q.bid) && Positive(q.ask);
         invalidBase=G_BaseStopOCOTripped || BaseStopHasPosition() || !BaseUseStopOrders || !ready || filled ||
            setup<=0 || TimeCurrent()<setup || TimeCurrent()-setup>=(long)BaseMaxWaitBars*PeriodSeconds(_Period) ||
            !Positive(tp) || !quoted || (side==POSITION_TYPE_BUY?q.bid>=tp:q.ask<=tp);
      }
      bool invalidModule=comment=="SMC_Comp_Limit" && (!G_D1_DataReady || !G_D1_Valid ||
         side!=(G_Fibo_isUp?POSITION_TYPE_BUY:POSITION_TYPE_SELL));
      if(invalidExposure || invalidBase || invalidModule || !EntryPolicy(side,comment,true,true)) SafeDelete(ticket);
   }
}

double GetDynamicRisk() {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if (balance <= 100.0) return 5.0;
    if (balance >= 1000.0) return 1.0;
    double risk = 5.0 - (balance - 100.0) * (4.0 / 900.0);
    return NormalizeDouble(risk, 2);
}

double GetDynamicGlobalRisk() {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if (balance <= 100.0) return 20.0;
    if (balance >= 1000.0) return 5.0;
    double g_risk = 20.0 - (balance - 100.0) * (15.0 / 900.0);
    return NormalizeDouble(g_risk, 2);
}

double CalculateSmartLot(double entry_price,double stop_loss) {
   double lot=0;
   int side=(stop_loss<entry_price)?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
   if(!SafeVolume(side,entry_price,stop_loss,lot)) return 0;
   return lot;
}

bool CanOpenLot(int type,string block_comment) {
   return EntryPolicy(type,block_comment,false,false);
}

// BASE ATR positions refresh their TP; BASE Stop positions keep a fixed extremum TP. Both retain individual BE.
void ManageBaseATRPositions() {
   if(!TradingMutationAllowed() || G_InstanceLock==INVALID_HANDLE || G_StopLatched || !G_StateOK || G_ExecutionUncertain) return;
   static datetime lastATRBar=0;
   datetime closed=iTime(_Symbol,_Period,1);
   double atr[];
   bool recalc=closed>0 && closed!=lastATRBar && CopyBuffer(h_atr,0,1,1,atr)==1;
   if(recalc && !Positive(atr[0])) recalc=false;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q) || !Positive(q.bid) || !Positive(q.ask)) return;
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(!Positive(tick)) return;
   double distance=MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
      SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   if(recalc) lastATRBar=closed;
   for(int i=PositionsTotal()-1;i>=0;i--) {
      ulong ticket=PositionGetTicket(i);
      if(!IsOwnPosition(ticket) || !IsIndividualBaseModule(PositionGetString(POSITION_COMMENT))) continue;
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      if(!Positive(sl)) { SafetyLog("SMC_Base_ATR: missing SL; portfolio protection remains active"); continue; }
      if(recalc && PositionGetString(POSITION_COMMENT)=="SMC_Base_ATR") {
         double target=BaseATRTarget(buy,entry,atr[0],tick,_Digits);
         if(!Positive(target)) { SafetyLog("SMC_Base_ATR: ATR target unavailable"); continue; }
         if(buy?q.bid>=target:q.ask<=target) { SafeClose(ticket); continue; }
         // Respect freeze distances for the old and new target. Never remove/widen the SL.
         if((buy?target-q.bid:q.ask-target)>distance &&
            (!Positive(tp) || MathAbs((buy?q.bid:q.ask)-tp)>distance) &&
            MathAbs((buy?q.bid:q.ask)-sl)>distance && MathAbs(target-tp)>=tick/2.0) {
            bool ok=trade.PositionModify(ticket,sl,target);
            if(TradeResult(ok,false,"BASE ATR TP update")) tp=target;
         }
      }
      if(!IsOwnPosition(ticket)) continue; // Re-read broker state after a target modification.
      tp=PositionGetDouble(POSITION_TP);
      double profitPoints=(buy?q.bid-entry:entry-q.ask)/_Point;
      if(profitPoints>=Physical_BE_Trigger) {
         double be=NormalizeDouble(entry+(buy?1:-1)*Physical_BE_Level*_Point,_Digits);
         SafeModify(ticket,be,tp); // Existing tightening-only SL boundary, current ATR TP preserved.
      }
   }
}

void ManagePositions() {
   ManageBaseATRPositions();
   double buy_vol = 0, sell_vol = 0, buy_weighted = 0, sell_weighted = 0;
   bool has_buy = false, has_sell = false;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(!Positive(point) || !Positive(tick_size) || !Positive(tick_val) || !HedgingAccount()) {
      SafetyLog("management: invalid symbol properties or unsupported account"); return;
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol && (PositionGetInteger(POSITION_MAGIC) == MagicNumber)) {
         if(IsIndividualBaseModule(PositionGetString(POSITION_COMMENT))) continue;
         double vol = PositionGetDouble(POSITION_VOLUME);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         long type = PositionGetInteger(POSITION_TYPE);
         if(type == POSITION_TYPE_BUY) { buy_vol += vol; buy_weighted += (open_price * vol); has_buy = true; }
         else if(type == POSITION_TYPE_SELL) { sell_vol += vol; sell_weighted += (open_price * vol); has_sell = true; }
      }
   }

   if(has_buy && buy_vol > 0) {
      double avg_buy = buy_weighted / buy_vol;
      double profit_pts = (bid - avg_buy) / point;
      if(profit_pts >= Physical_BE_Trigger) {
         double new_sl = NormalizeDouble(avg_buy + Physical_BE_Level * point, _Digits);
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol && (PositionGetInteger(POSITION_MAGIC) == MagicNumber) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && !IsIndividualBaseModule(PositionGetString(POSITION_COMMENT))) {
               double current_sl = PositionGetDouble(POSITION_SL);
               double current_tp = PositionGetDouble(POSITION_TP);
               if(current_sl < new_sl || current_sl == 0) SafeModify(ticket, new_sl, current_tp);
            }
         }
      }
      double target_tp_buy = NormalizeDouble(avg_buy + Fixed_TakeProfit * point, _Digits);
      string line_buy = "Virtual_TP_BUY";
      CreateFiboLine(line_buy,target_tp_buy,clrLime,STYLE_SOLID,"Basket TP BUY");

      double val_per_point_buy = buy_vol * tick_val * (point / tick_size);
      if(val_per_point_buy > 0) {
         double pts_to_stop_buy = (balance * (GetDynamicGlobalRisk() / 100.0)) / val_per_point_buy;
         double global_stop_buy = NormalizeDouble(avg_buy - pts_to_stop_buy * point, _Digits);
         string gstop_buy = "Global_Stop_BUY";
         CreateFiboLine(gstop_buy,global_stop_buy,clrFireBrick,STYLE_DOT,"Global risk reference BUY");
      }
      if(bid >= target_tp_buy) {
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol && (PositionGetInteger(POSITION_MAGIC) == MagicNumber) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && !IsIndividualBaseModule(PositionGetString(POSITION_COMMENT))) SafeClose(ticket);
         }

      }
   } else {   }

   if(has_sell && sell_vol > 0) {
      double avg_sell = sell_weighted / sell_vol;
      double profit_pts = (avg_sell - ask) / point;
      if(profit_pts >= Physical_BE_Trigger) {
         double new_sl = NormalizeDouble(avg_sell - Physical_BE_Level * point, _Digits);
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol && (PositionGetInteger(POSITION_MAGIC) == MagicNumber) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && !IsIndividualBaseModule(PositionGetString(POSITION_COMMENT))) {
               double current_sl = PositionGetDouble(POSITION_SL);
               double current_tp = PositionGetDouble(POSITION_TP);
               if(current_sl > new_sl || current_sl == 0) SafeModify(ticket, new_sl, current_tp);
            }
         }
      }
      double target_tp_sell = NormalizeDouble(avg_sell - Fixed_TakeProfit * point, _Digits);
      string line_sell = "Virtual_TP_SELL";
      CreateFiboLine(line_sell,target_tp_sell,clrRed,STYLE_SOLID,"Basket TP SELL");

      double val_per_point_sell = sell_vol * tick_val * (point / tick_size);
      if(val_per_point_sell > 0) {
         double pts_to_stop_sell = (balance * (GetDynamicGlobalRisk() / 100.0)) / val_per_point_sell;
         double global_stop_sell = NormalizeDouble(avg_sell + pts_to_stop_sell * point, _Digits);
         string gstop_sell = "Global_Stop_SELL";
         CreateFiboLine(gstop_sell,global_stop_sell,clrFireBrick,STYLE_DOT,"Global risk reference SELL");
      }
      if(ask <= target_tp_sell) {
         for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol && (PositionGetInteger(POSITION_MAGIC) == MagicNumber) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && !IsIndividualBaseModule(PositionGetString(POSITION_COMMENT))) SafeClose(ticket);
         }

      }
   } else {   }
}

void CheckEquityProtection() {
   if(DiagnosticMode) return;
   if(FileIsExist(G_StopFile,FILE_COMMON)) G_StopLatched=true;
   double pnl=0;
   if(!OwnFloatingPNL(pnl)) { G_StateOK=false; return; }
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   // Same percentage curve; ownership scope is now exclusively this symbol/Magic.
   if(!G_StopLatched && balance>0 && pnl<0 && -pnl>=balance*GetDynamicGlobalRisk()/100.0)
      LatchGlobalStop("own floating loss reached global risk");
   if(G_StopLatched) {
      DeleteOrdersByComment("");
      for(int i=PositionsTotal()-1;i>=0;i--) {
         ulong ticket=PositionGetTicket(i);
         if(IsOwnPosition(ticket)) SafeClose(ticket);
      }
      // Notify only after protective broker requests; do not delay them with WebRequest.
      if(G_StopNoticePending) {
         G_StopNoticePending=false;
         SendTelegramPhotoAlert("SN35 GLOBAL STOP: entry locked; own close/delete requests issued, check execution log.");
      }
   }
}

void DeleteOrdersByComment(string comment_str) {
   if(DiagnosticMode) return;
   for(int i=OrdersTotal()-1;i>=0;i--) {
      ulong ticket=OrderGetTicket(i);
      if(IsOwnOrder(ticket) && (comment_str=="" || OrderGetString(ORDER_COMMENT)==comment_str)) SafeDelete(ticket);
   }
}

double GetDailyPNL() {
   double daily_profit = 0;
   HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent());
   for(int i = 0; i < HistoryDealsTotal(); i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol) {
         daily_profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         daily_profit += HistoryDealGetDouble(ticket, DEAL_SWAP);
         daily_profit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }
   return daily_profit;
}

#endif // SNIPER365_RISKMANAGER_MQH

// END Sniper365/RiskManager.mqh
// BEGIN Sniper365/Dashboard.mqh
// Sniper 3.65: Dashboard; shared application declarations in the entrypoint.
#ifndef SNIPER365_DASHBOARD_MQH
#define SNIPER365_DASHBOARD_MQH

void InitVisualNamespace() {
   uint id=(uint)ChartID()^(uint)GetTickCount();
   bool collision=true;
   while(collision) {
      G_VisualPrefix="S36_"+StringFormat("%08X",id)+"_";
      collision=false;
      int n=ObjectsTotal(0,-1,-1);
      for(int i=0;i<n;i++)
         if(StringFind(ObjectName(0,i,-1,-1),G_VisualPrefix)==0) { collision=true; id++; break; }
   }
}

string ViewName(string logical) {
   if(G_VisualPrefix=="") return "S36_UNINITIALIZED_"+logical;
   if(StringFind(logical,G_VisualPrefix)==0) return logical;
   return G_VisualPrefix+logical;
}

int OwnObjectsTotal(long chart,int window=-1,int type=-1) {
   if(G_VisualPrefix=="") return 0;
   int own=0,total=ObjectsTotal(chart,window,type);
   for(int i=0;i<total;i++)
      if(StringFind(ObjectName(chart,i,window,type),G_VisualPrefix)==0) own++;
   return own;
}

string OwnObjectName(long chart,int index,int window=-1,int type=-1) {
   if(G_VisualPrefix=="") return "";
   int own=0,total=ObjectsTotal(chart,window,type);
   for(int i=0;i<total;i++) {
      string raw=ObjectName(chart,i,window,type);
      if(StringFind(raw,G_VisualPrefix)!=0) continue;
      if(own==index) return StringSubstr(raw,StringLen(G_VisualPrefix));
      own++;
   }
   return "";
}

void ClearOwnVisuals(bool keepStructure) {
   if(G_VisualPrefix=="") return;
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--) {
      string raw=ObjectName(0,i,-1,-1);
      if(StringFind(raw,G_VisualPrefix)!=0) continue;
      string logical=StringSubstr(raw,StringLen(G_VisualPrefix));
      if(keepStructure && (StringFind(logical,"SN24_STRUCT_")==0 || logical=="H4_FIBO")) continue;
      ObjectDelete(0,raw);
   }
}

bool VisualFrameReady(ulong now,ulong interval,ulong &last,bool &started) {
   if(started && now>=last && now-last<interval) return false;
   started=true; last=now; return true;
}

void ServiceVisuals(bool force=false) {
   if(!G_VisualEnabled) return;
   static ulong last=0; static bool started=false;
   ulong interval=(ulong)(MQLInfoInteger(MQL_TESTER)?TesterVisualFrameMs:LiveVisualFrameMs);
   if(!force && !VisualFrameReady(GetTickCount64(),interval,last,started)) return;
   if(force) { last=GetTickCount64(); started=true; }
   G_PaintFrame=true;
   RefreshVisuals();
   G_PaintFrame=false;
}

void DropPaintedView(string name,bool painted) {
   if(!painted) return;
   int n=ArraySize(G_DroppedViews);
   ArrayResize(G_DroppedViews,n+1); G_DroppedViews[n]=name;
}

void QueueBaseView(string name,datetime t1,double high,datetime t2,double low,color shade,string text) {
   if(!G_VisualEnabled) return;
   int n=ArraySize(G_BaseViews),slot=-1;
   for(int i=0;i<n;i++) if(G_BaseViews[i].name==name) { slot=i; break; }
   if(slot<0) {
      if(n>=MaxVisualHistory) {
         DropPaintedView(G_BaseViews[0].name,G_BaseViews[0].painted);
         for(int i=1;i<n;i++) G_BaseViews[i-1]=G_BaseViews[i];
         slot=n-1;
      } else { slot=n; ArrayResize(G_BaseViews,n+1); }
      G_BaseViews[slot].painted=false;
   }
   G_BaseViews[slot].name=name; G_BaseViews[slot].first=t1; G_BaseViews[slot].last=t2;
   G_BaseViews[slot].high=high; G_BaseViews[slot].low=low; G_BaseViews[slot].shade=shade; G_BaseViews[slot].text=text;
}

void QueueArrowView(string name,datetime time,double price,color shade,int code,string text,bool buy) {
   if(!G_VisualEnabled) return;
   int n=ArraySize(G_ArrowViews),slot=-1;
   for(int i=n-1;i>=0;i--) if(G_ArrowViews[i].name==name) { slot=i; break; }
   if(slot<0) {
      if(n>=MaxVisualHistory) {
         DropPaintedView(G_ArrowViews[0].name,G_ArrowViews[0].painted);
         for(int i=1;i<n;i++) G_ArrowViews[i-1]=G_ArrowViews[i];
         slot=n-1;
      } else { slot=n; ArrayResize(G_ArrowViews,n+1); }
   }
   G_ArrowViews[slot].name=name; G_ArrowViews[slot].time=time; G_ArrowViews[slot].price=price;
   G_ArrowViews[slot].shade=shade; G_ArrowViews[slot].code=code; G_ArrowViews[slot].text=text;
   G_ArrowViews[slot].buy=buy; G_ArrowViews[slot].painted=false;
}

bool RememberDiagnosticView(string module,int side,datetime bar) {
   static datetime current=0; static string keys[];
   if(bar!=current) { current=bar; ArrayResize(keys,0); }
   string key=module+IntegerToString(side);
   for(int i=0;i<ArraySize(keys);i++) if(keys[i]==key) return false;
   int n=ArraySize(keys); ArrayResize(keys,n+1); keys[n]=key; return true;
}

int ViewTextWidth(string text,int size) {
   uint w=0,h=0;
   if(TextSetFont(HudFontName,-size*10) && TextGetSize(text,w,h)) return (int)w;
   return (int)MathCeil(StringLen(text)*size*0.8*MathMax(1.0,TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0));
}

int ViewTextHeight(int size) {
   uint w=0,h=0;
   if(TextSetFont(HudFontName,-size*10) && TextGetSize("Ag",w,h)) return (int)h;
   return (int)MathCeil(size*1.7*MathMax(1.0,TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0));
}

string FitViewText(string text,int size,int width) {
   if(ViewTextWidth(text,size)<=width) return text;
   int lo=0,hi=StringLen(text);
   while(lo<hi) {
      int mid=(lo+hi+1)/2;
      if(ViewTextWidth(StringSubstr(text,0,mid)+"...",size)<=width) lo=mid; else hi=mid-1;
   }
   return StringSubstr(text,0,lo)+"...";
}

void UpdateHudLayout() {
   int chartWidth=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
   int margin=MathMin(InfoRightMarginPx,MathMax(0,chartWidth/4));
   int available=MathMax(40,chartWidth-margin-12);
   G_HudFont=MathMax(8,HudFontSize-(DiagnosticCleanView?1:0));
   G_HudRow=ViewTextHeight(G_HudFont)+2;
   int cell=ViewTextWidth("H4 DIAMOND RSI 100.0 DN",G_HudFont)+8;
   int maximum=MathMax(40,available*MathMax(30,MathMin(100,HudWidthPercent))/100);
   G_HudColumns=maximum>=6*cell?6:(maximum>=3*cell?3:(maximum>=2*cell?2:1));
   G_HudWidth=MathMin(available,MathMax(maximum,G_HudColumns*cell));
   G_HudLeft=MathMax(12,chartWidth-margin-G_HudWidth);
   G_HudCompact=false;
   G_HudTop=HudTopOffsetPx;
   int rows=ShowMTFDashboard?(6+G_HudColumns-1)/G_HudColumns:0;
   G_SummaryY=G_HudTop+rows*3*G_HudRow+4;
   G_ScopeY=G_SummaryY+ViewTextHeight(InfoFontSize)+4;
   G_DiagTop=MathMax(DiagnosticTopOffsetPx,G_ScopeY+G_HudRow+6);
   G_DiagBottom=G_DiagTop;
}

string LabelPartName(string name,int part) {
   return part==0?name:name+"_p"+IntegerToString(part);
}

void ClearSegmentedLabel(string name) {
   ObjectDelete(0,ViewName(name));
   for(int part=1;part<32;part++) {
      string key=LabelPartName(name,part);
      if(ObjectFind(0,ViewName(key))<0) break;
      ObjectDelete(0,ViewName(key));
   }
}

void PaintLabelSegments(string name,string text,int x,int y,color shade,int size,string tooltip) {
   int count=MathMax(1,(StringLen(text)+47)/48);
   count=MathMin(32,count);
   for(int part=0;part<count;part++) {
      string key=LabelPartName(name,part);
      string chunk=StringSubstr(text,part*48,48);
      SetViewLabel(key,chunk,x+ViewTextWidth(StringSubstr(text,0,part*48),size),y,shade,size);
      ObjectSetString(0,ViewName(key),OBJPROP_TOOLTIP,tooltip);
   }
   for(int part=count;part<32;part++) {
      string key=LabelPartName(name,part);
      if(ObjectFind(0,ViewName(key))<0) break;
      ObjectDelete(0,ViewName(key));
   }
}

void SetFittedViewLabel(string name,string text,int x,int y,color shade,int size,int width) {
   PaintLabelSegments(name,FitViewText(text,size,width),x,y,shade,size,text);
}

int PaintWrappedView(string name,string text,int x,int y,color shade,int size,int width,int maxRows=8) {
   string original=text;
   int count=0,row=ViewTextHeight(size)+5;
   while(StringLen(text)>0 && count<maxRows) {
      int take=StringLen(text);
      if(ViewTextWidth(text,size)>width) {
         int lo=1,hi=take;
         while(lo<hi) {
            int mid=(lo+hi+1)/2;
            if(ViewTextWidth(StringSubstr(text,0,mid),size)<=width) lo=mid; else hi=mid-1;
         }
         take=lo;
         for(int j=take-1;j>take/2;j--) if(StringSubstr(text,j,1)==" ") { take=j+1; break; }
      }
      string part=count==maxRows-1?FitViewText(text,size,width):StringSubstr(text,0,take);
      SetFittedViewLabel(name+"_"+IntegerToString(count),part,x,y+count*row,shade,size,width);
      ObjectSetString(0,ViewName(name+"_"+IntegerToString(count)),OBJPROP_TOOLTIP,original);
      text=StringSubstr(text,take); count++;
   }
   for(int i=count;i<8;i++) ClearSegmentedLabel(name+"_"+IntegerToString(i));
   return MathMax(1,count)*row;
}

void RegisterPriceCaption(string key,double price,string text,color shade) {
   if(!ShowChartPriceCaptions || !G_PaintFrame) return;
   int n=ArraySize(G_PriceCaptions); ArrayResize(G_PriceCaptions,n+1);
   G_PriceCaptions[n].key=key; G_PriceCaptions[n].price=price;
   G_PriceCaptions[n].text=text; G_PriceCaptions[n].shade=shade;
}

void PaintPriceCaptions() {
   ObjectsDeleteAll(0,ViewName("PriceCaption_"));
   if(!ShowChartPriceCaptions) return;
   // Legacy native tool is cached between structure changes; rebuild its caption model each frame.
   if(ShowLegacyStructure && ObjectFind(0,ViewName("Legacy_FIBO"))>=0) {
      double a=ObjectGetDouble(0,ViewName("Legacy_FIBO"),OBJPROP_PRICE,0);
      double b=ObjectGetDouble(0,ViewName("Legacy_FIBO"),OBJPROP_PRICE,1);
      double ratios[]={0.0,0.500,0.618,0.790,1.000};
      for(int i=0;i<ArraySize(ratios);i++) RegisterPriceCaption("LegacyCached"+IntegerToString(i),
         RetracementPrice(a,b,ratios[i]),"LEGACY REF "+DoubleToString(ratios[i],3),clrSilver);
   }
   int height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   int top=MathMax(G_DiagBottom+ViewTextHeight(G_HudFont)+24,G_ScopeY+G_HudRow+8),row=ViewTextHeight(G_HudFont)+4;
   int bottom=height-70,capacity=(bottom-top)/MathMax(1,row);
   if(capacity<=0) return;
   int positions[],indices[]; int count=0;
   for(int i=0;i<ArraySize(G_PriceCaptions);i++) {
      int x=0,y=0;
      if(!ChartTimePriceToXY(0,0,iTime(_Symbol,_Period,0),G_PriceCaptions[i].price,x,y) || y<top || y>bottom) continue;
      ArrayResize(positions,count+1); ArrayResize(indices,count+1);
      positions[count]=y; indices[count]=i; count++;
   }
   for(int i=1;i<count;i++) for(int j=i;j>0 && positions[j]<positions[j-1];j--) {
      int v=positions[j]; positions[j]=positions[j-1]; positions[j-1]=v;
      v=indices[j]; indices[j]=indices[j-1]; indices[j-1]=v;
   }
   count=MathMin(count,capacity);
   for(int i=0;i<count;i++) positions[i]=MathMax(positions[i],i==0?top:positions[i-1]+row);
   for(int i=count-1;i>=0;i--) positions[i]=MathMin(positions[i],i==count-1?bottom:positions[i+1]-row);
   int width=MathMin(310,G_HudWidth/2),left=G_HudLeft+G_HudWidth-width;
   for(int i=0;i<count;i++) {
      int k=indices[i];
      string text=G_PriceCaptions[k].text+" @ "+DoubleToString(G_PriceCaptions[k].price,_Digits);
      SetFittedViewLabel("PriceCaption_"+G_PriceCaptions[k].key,text,left,positions[i],G_PriceCaptions[k].shade,G_HudFont,width);
   }
}

uchar PanelAlpha(int transparency) {
   return (uchar)MathRound(255.0*(100-MathMax(0,MathMin(100,transparency)))/100.0);
}
int CenteredLabelX(int left,int availableWidth,int textWidth) {
   return left+(int)MathMax(0,(availableWidth-textWidth)/2);
}
bool PaintTransparentPanel(CCanvas &canvas,bool &ready,int &oldWidth,int &oldHeight,
                           string name,int x,int y,int width,int height) {
   if(width<1 || height<1) return false;
   if(!ready || oldWidth!=width || oldHeight!=height || ObjectFind(0,ViewName(name))<0) {
      canvas.Destroy(); ready=false;
      if(!canvas.CreateBitmapLabel(0,0,ViewName(name),x,y,width,height,COLOR_FORMAT_ARGB_NORMALIZE)) {
         SafetyLog("transparent panel unavailable: "+name+"; opaque fallback disabled"); return false;
      }
      ready=true; oldWidth=width; oldHeight=height;
   }
   ObjectSetInteger(0,ViewName(name),OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,ViewName(name),OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,ViewName(name),OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,ViewName(name),OBJPROP_BACK,false);
   ObjectSetInteger(0,ViewName(name),OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,ViewName(name),OBJPROP_HIDDEN,true);
   canvas.Erase(ColorToARGB(clrBlack,PanelAlpha(HudBackgroundTransparency)));
   canvas.Update(false);
   return true;
}
void ReleasePanelCanvases() {
   G_HeaderCanvas.Destroy(); G_DiagCanvas.Destroy();
   G_HeaderCanvasReady=false; G_DiagCanvasReady=false;
}
void PaintHeaderBackground() {
   PaintTransparentPanel(G_HeaderCanvas,G_HeaderCanvasReady,G_HeaderCanvasWidth,G_HeaderCanvasHeight,
      "HUD_BG",G_HudLeft-4,G_HudTop-4,G_HudWidth+8,
      G_ScopeY+G_HudRow-G_HudTop+4);
}

void PaintSignalViews() {
   for(int i=0;i<ArraySize(G_DroppedViews);i++) {
      ObjectDelete(0,ViewName(G_DroppedViews[i])); ObjectDelete(0,ViewName("Txt_"+G_DroppedViews[i]));
   }
   ArrayResize(G_DroppedViews,0);
   for(int i=0;i<ArraySize(G_BaseViews);i++) {
      DrawR(G_BaseViews[i].name,G_BaseViews[i].first,G_BaseViews[i].high,
         G_BaseViews[i].last,G_BaseViews[i].low,G_BaseViews[i].shade,G_BaseViews[i].text);
      G_BaseViews[i].painted=true;
   }
   for(int i=0;i<ArraySize(G_ArrowViews);i++) {
      if(G_ArrowViews[i].painted) continue;
      PaintArrow(G_ArrowViews[i].name,G_ArrowViews[i].time,G_ArrowViews[i].price,G_ArrowViews[i].shade,
         G_ArrowViews[i].code,G_ArrowViews[i].text,G_ArrowViews[i].buy);
      G_ArrowViews[i].painted=true;
   }
   datetime now=iTime(_Symbol,_Period,0);
   if(G_Compression_Active && G_D1_Valid && G_CompHigh>G_CompLow) {
      DrawR("CompZone_Current",now-2*PeriodSeconds(_Period),G_CompHigh,now+5*PeriodSeconds(_Period),G_CompLow,clrDimGray,
         "Compression "+StringSubstr(EnumToString(_Period),7)+(G_Fibo_isUp?" BUY":" SELL"));
      ObjectMove(0,ViewName("Txt_CompZone_Current"),0,now-2*PeriodSeconds(_Period),G_Fibo_isUp?G_CompLow:G_CompHigh);
      ObjectSetInteger(0,ViewName("Txt_CompZone_Current"),OBJPROP_ANCHOR,G_Fibo_isUp?ANCHOR_UPPER:ANCHOR_LOWER);
   } else { ObjectDelete(0,ViewName("CompZone_Current")); ObjectDelete(0,ViewName("Txt_CompZone_Current")); }
   if(G_PredZone_Active && G_D1_Valid)
      DrawR("PredZone",iTime(_Symbol,_Period,1),G_PredZone_High,now+10*PeriodSeconds(_Period),G_PredZone_Low,
         clrDimGray,G_Fibo_isUp?"D1 TRADE OTE BUY .790-1.000":"D1 TRADE OTE SELL .790-1.000");
   else { ObjectDelete(0,ViewName("PredZone")); ObjectDelete(0,ViewName("Txt_PredZone")); }
   if(SF_ShowStatus) SetFittedViewLabel("StructureStatus",G_StructureStatus,G_HudLeft,G_DiagBottom+8,clrSilver,9,G_HudWidth);
}

void PaintReferenceViews() {
   if(!ShowReferenceHLines) {
      ObjectsDeleteAll(0,ViewName("Line_")); ObjectsDeleteAll(0,ViewName("H4_Confirm_")); return;
   }
   DrawStructureAndFibo();
   if(!G_D1_Valid) return;
   CreateFiboLine("Line_050",G_Fibo_EQ,clrGray,STYLE_SOLID,"D1 0.5");
   CreateFiboLine("Line_618",G_Fibo_618,clrGold,STYLE_SOLID,"D1 REF 0.618");
   CreateFiboLine("Line_Dia2",G_Fibo_790,Diamond_Color,STYLE_SOLID,"D1 TRADE 0.790");
   CreateFiboLine("Line_100",G_Fibo_isUp?G_Struct_Low:G_Struct_High,Diamond_Color,STYLE_SOLID,"D1 TRADE 1.000");
}

void SetViewLabel(string name,string text,int x,int y,color shade,int size=9) {
   if(ObjectFind(0,ViewName(name))<0 && !ObjectCreate(0,ViewName(name),OBJ_LABEL,0,0,0)) return;
   ObjectSetInteger(0,ViewName(name),OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,ViewName(name),OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0,ViewName(name),OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,ViewName(name),OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,ViewName(name),OBJPROP_COLOR,shade);
   ObjectSetInteger(0,ViewName(name),OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,ViewName(name),OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,ViewName(name),OBJPROP_HIDDEN,false);
   ObjectSetInteger(0,ViewName(name),OBJPROP_BACK,false);
   ObjectSetString(0,ViewName(name),OBJPROP_FONT,HudFontName);
   ObjectSetString(0,ViewName(name),OBJPROP_TEXT,text);
}

bool DrawFibonacciTool(string name,datetime originTime,double origin,
                       datetime endpointTime,double endpoint,color shade,string caption) {
   if(originTime<=0 || endpointTime<=0 || !Positive(origin) || !Positive(endpoint) ||
      MathAbs(endpoint-origin)<=_Point) return false;
   if(ObjectFind(0,ViewName(name))<0) {
      if(!ObjectCreate(0,ViewName(name),OBJ_FIBO,0,originTime,origin,endpointTime,endpoint)) {
         SafetyLog("Fibonacci object creation failed: "+name); return false;
      }
   }
   if(!ObjectMove(0,ViewName(name),0,originTime,origin) || !ObjectMove(0,ViewName(name),1,endpointTime,endpoint)) return false;
   // Native retracement convention: level 0 at endpoint, level 1 at origin.
   double ratios[]={0.0,0.500,0.618,0.700,0.786,0.790,1.000};
   ObjectSetInteger(0,ViewName(name),OBJPROP_LEVELS,ArraySize(ratios));
   for(int i=0;i<ArraySize(ratios);i++) {
      // Prices use RetracementPrice; complete values are displayed in the HUD.
      ObjectSetDouble(0,ViewName(name),OBJPROP_LEVELVALUE,i,ratios[i]);
      string levelText=ShowFiboLevelCaptions?caption+" "+DoubleToString(ratios[i],3)+" "+
         DoubleToString(RetracementPrice(origin,endpoint,ratios[i]),_Digits):" ";
      ObjectSetString(0,ViewName(name),OBJPROP_LEVELTEXT,i,levelText);
      ObjectSetInteger(0,ViewName(name),OBJPROP_LEVELCOLOR,i,ratios[i]>=0.790?Diamond_Color:shade);
      ObjectSetInteger(0,ViewName(name),OBJPROP_LEVELSTYLE,i,STYLE_DOT);
      ObjectSetInteger(0,ViewName(name),OBJPROP_LEVELWIDTH,i,1);
   }
   for(int i=0;i<ArraySize(ratios) && name!="Legacy_FIBO";i++) {
      if(i==3 || i==4) continue; // .700/.786 remain native levels and in tooltips
      RegisterPriceCaption(name+IntegerToString(i),RetracementPrice(origin,endpoint,ratios[i]),
         caption+" "+DoubleToString(ratios[i],3),shade);
   }
   ObjectSetInteger(0,ViewName(name),OBJPROP_COLOR,shade);
   ObjectSetInteger(0,ViewName(name),OBJPROP_RAY_RIGHT,true);
   ObjectSetInteger(0,ViewName(name),OBJPROP_BACK,true);
   ObjectSetInteger(0,ViewName(name),OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,ViewName(name),OBJPROP_HIDDEN,false);
   string detail=caption+" | source anchors; REF .618-.790; D1 TRADE .790-1.000 only";
   for(int i=0;i<ArraySize(ratios);i++) detail+=" | "+DoubleToString(ratios[i],3)+": "+
      DoubleToString(RetracementPrice(origin,endpoint,ratios[i]),_Digits);
   ObjectSetString(0,ViewName(name),OBJPROP_TOOLTIP,detail);
   return true;
}

void DrawStructureEvent(string prefix,datetime pivotTime,double price,datetime breakTime,
                        string label,int direction,bool newest) {
   color shade=label=="CHoCH"?Color_CHOCH:Color_BOS;
   if(!newest) shade=clrSlateGray;
   CreateStructLine(prefix+"BREAK",pivotTime,price,breakTime,price,shade,label);
   string text=prefix+"BREAK_TEXT";
   datetime midpoint=pivotTime+(breakTime-pivotTime)/2;
   if(ObjectFind(0,ViewName(text))<0) ObjectCreate(0,ViewName(text),OBJ_TEXT,0,midpoint,price);
   ObjectMove(0,ViewName(text),0,midpoint,price);
   ObjectSetString(0,ViewName(text),OBJPROP_TEXT,label+(direction==1?" UP":" DOWN"));
   ObjectSetInteger(0,ViewName(text),OBJPROP_COLOR,shade);
   ObjectSetInteger(0,ViewName(text),OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,ViewName(text),OBJPROP_ANCHOR,direction==1?ANCHOR_LOWER:ANCHOR_UPPER);
   ObjectSetInteger(0,ViewName(text),OBJPROP_BACK,false);
}

void DrawConfirmedPivotLabels(SF_Pivot &pivots[],int count) {
   if(!ShowStructureLabels) return;
   double hi=0,lo=0;
   int first=MathMax(0,count-24);
   for(int i=0;i<count;i++) {
      string label;
      if(pivots[i].type==1) {
         label=hi>0?(pivots[i].price>hi?"HH":(pivots[i].price<hi?"LH":"EH")):"H";
         hi=pivots[i].price;
      } else {
         label=lo>0?(pivots[i].price>lo?"HL":(pivots[i].price<lo?"LL":"EL")):"L";
         lo=pivots[i].price;
      }
      if(i<first) continue;
      string name=SF_Prefix+"P_"+IntegerToString((long)pivots[i].time)+(pivots[i].type==1?"H":"L");
      ObjectCreate(0,ViewName(name),OBJ_TEXT,0,pivots[i].time,pivots[i].price);
      ObjectSetString(0,ViewName(name),OBJPROP_TEXT,label);
      ObjectSetString(0,ViewName(name),OBJPROP_TOOLTIP,label+" | confirmed after "+IntegerToString(SF_RightBars)+" CLOSED right bars");
      ObjectSetInteger(0,ViewName(name),OBJPROP_ANCHOR,pivots[i].type==1?ANCHOR_LOWER:ANCHOR_UPPER);
      ObjectSetInteger(0,ViewName(name),OBJPROP_COLOR,pivots[i].type==1?Color_BOS:Color_CHOCH);
      ObjectSetInteger(0,ViewName(name),OBJPROP_FONTSIZE,8);
   }
}

void UpdateD1FibonacciTool() {
   if(!ShowD1Fibonacci || !G_D1_DataReady || !G_D1_Valid) {
      ObjectDelete(0,ViewName("D1_FIBO")); ObjectDelete(0,ViewName("D1_ANCHOR_WAIT")); return;
   }
   static datetime cachedDay=0,highTime=0,lowTime=0;
   if(cachedDay!=G_D1_SourceDay || highTime==0 || lowTime==0) {
      // Anchor to the M15 candles containing the actual previous-day extrema.
      // No guessed future time or current-day price is used; high/low values remain D1.
      datetime from=iTime(_Symbol,PERIOD_D1,1);
      MqlRates rates[];
      datetime until=(datetime)(G_D1_SourceDay-1);
      int n=CopyRates(_Symbol,PERIOD_M15,from,until,rates);
      highTime=0; lowTime=0;
      for(int i=0;i<n;i++) {
         if(rates[i].time<from || rates[i].time>=G_D1_SourceDay) continue;
         if(highTime==0 && MathAbs(rates[i].high-G_Struct_High)<=_Point/2) highTime=rates[i].time;
         if(lowTime==0 && MathAbs(rates[i].low-G_Struct_Low)<=_Point/2) lowTime=rates[i].time;
      }
      if(highTime==0 || lowTime==0) {
         ObjectDelete(0,ViewName("D1_FIBO"));
         SetViewLabel("D1_ANCHOR_WAIT","D1 native Fibo: waiting for closed M15 extreme candles",G_HudLeft,G_DiagBottom+ViewTextHeight(G_HudFont)+16,clrSilver,8);
         return;
      }
      cachedDay=G_D1_SourceDay;
   }
   ObjectDelete(0,ViewName("D1_ANCHOR_WAIT"));
   bool up=G_D1_Direction==1;
   DrawFibonacciTool("D1_FIBO",up?lowTime:highTime,up?G_Struct_Low:G_Struct_High,
      up?highTime:lowTime,up?G_Struct_High:G_Struct_Low,clrGold,"D1 RANGE");
}

void UpdateNativeFibonacciTools() {
   UpdateD1FibonacciTool();
   if(ShowH4Fibonacci && SF_DataReady && SF_OriginTime>0 && SF_EndpointTime>0)
      DrawFibonacciTool("H4_FIBO",SF_OriginTime,SF_ConfirmedOrigin,SF_EndpointTime,
         SF_ConfirmedBreak,clrDeepSkyBlue,"H4 STRUCT REF");
   else ObjectDelete(0,ViewName("H4_FIBO"));
}

void UpdateLegacyStructureVisuals() {
   if(!ShowLegacyStructure) { ObjectsDeleteAll(0,ViewName("Legacy_")); return; }
   // Original v1 calculation, isolated from D1/H4 and all trading state.
   ENUM_TIMEFRAMES tf=_Period;
   if(tf==PERIOD_M1 || tf==PERIOD_M5) tf=PERIOD_M15;
   static datetime lastClosed=0;
   datetime closed=iTime(_Symbol,tf,1);
   if(closed==0 || closed==lastClosed) return;
   int limit=(tf==PERIOD_H1 || tf==PERIOD_H4 || tf==PERIOD_D1)?100:200;
   if(!SeriesInfoInteger(_Symbol,tf,SERIES_SYNCHRONIZED) || Bars(_Symbol,tf)<limit+MathMax(Fractal_Strength,10)) return;
   static bool valid=false;
   static double retainedHigh=0,retainedLow=0;
   double c1=iClose(_Symbol,tf,1);
   if(valid && c1<retainedHigh && c1>retainedLow) { lastClosed=closed; return; }
   int sh=-1,sl=-1;
   for(int i=Fractal_Strength+1;i<limit;i++) {
      if(sh<0 && IsSwingHigh(tf,i,Fractal_Strength)) sh=i;
      if(sl<0 && IsSwingLow(tf,i,Fractal_Strength)) sl=i;
      if(sh>=0 && sl>=0) break;
   }
   if(sh<0 || sl<0) return;
   double high=iHigh(_Symbol,tf,sh),low=iLow(_Symbol,tf,sl);
   if(!Positive(low) || high-low<=_Point) return;
   bool up=sl>sh;
   datetime highTime=iTime(_Symbol,tf,sh),lowTime=iTime(_Symbol,tf,sl);
   if(up && c1>high) {
      string kind=iLow(_Symbol,tf,sh+10)>low?"BOS":"CHoCH";
      DrawStructureEvent("Legacy_",highTime,high,closed,kind,1,true);
   } else if(!up && c1<low) {
      string kind=iHigh(_Symbol,tf,sl+10)<high?"BOS":"CHoCH";
      DrawStructureEvent("Legacy_",lowTime,low,closed,kind,-1,true);
   }
   DrawFibonacciTool("Legacy_FIBO",up?lowTime:highTime,up?low:high,
      up?highTime:lowTime,up?high:low,clrSilver,"V1 "+EnumToString(tf)+" REF");
   retainedHigh=high; retainedLow=low; valid=true; lastClosed=closed;
}

void PaintOwnManagementViews() {
   double volume[2]={0,0},weighted[2]={0,0};
   for(int i=0;i<PositionsTotal();i++) {
      ulong ticket=PositionGetTicket(i); if(!IsOwnPosition(ticket)) continue;
      if(IsIndividualBaseModule(PositionGetString(POSITION_COMMENT))) continue;
      int side=(int)PositionGetInteger(POSITION_TYPE); if(side<0 || side>1) continue;
      double v=PositionGetDouble(POSITION_VOLUME);
      volume[side]+=v; weighted[side]+=v*PositionGetDouble(POSITION_PRICE_OPEN);
   }
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   for(int side=0;side<2;side++) {
      string suffix=side==0?"BUY":"SELL";
      if(volume[side]<=0) {
         ObjectDelete(0,ViewName("Virtual_TP_"+suffix)); ObjectDelete(0,ViewName("Global_Stop_"+suffix)); continue;
      }
      double avg=weighted[side]/volume[side];
      CreateFiboLine("Virtual_TP_"+suffix,avg+(side==0?1:-1)*Fixed_TakeProfit*_Point,
         side==0?clrLime:clrRed,STYLE_SOLID,"OWN Basket TP "+suffix);
      if(Positive(tick) && Positive(tv)) {
         double distance=AccountInfoDouble(ACCOUNT_BALANCE)*GetDynamicGlobalRisk()/100.0*tick/(volume[side]*tv);
         CreateFiboLine("Global_Stop_"+suffix,avg+(side==0?-1:1)*distance,clrFireBrick,STYLE_DOT,"OWN risk reference "+suffix);
      }
   }
}

void UpdatePositionVisuals() {
   // Display legacy manual+own basket arithmetic; absolutely no close/modify requests.
   double volume[2]={0,0},weighted[2]={0,0};
   bool manual[2]={false,false};
   for(int i=0;i<PositionsTotal();i++) {
      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      ulong magic=(ulong)PositionGetInteger(POSITION_MAGIC);
      if(magic!=0 && magic!=MagicNumber) continue;
      int side=(int)PositionGetInteger(POSITION_TYPE); if(side<0 || side>1) continue;
      double v=PositionGetDouble(POSITION_VOLUME);
      if(magic==0) manual[side]=true;
      volume[side]+=v; weighted[side]+=v*PositionGetDouble(POSITION_PRICE_OPEN);
   }
   for(int side=0;side<2;side++) {
      string suffix=side==0?"BUY":"SELL";
      if(volume[side]<=0 || !manual[side]) { ObjectDelete(0,ViewName("View_TP_"+suffix)); ObjectDelete(0,ViewName("View_Stop_"+suffix)); continue; }
      double avg=weighted[side]/volume[side];
      double tp=avg+(side==0?1:-1)*Fixed_TakeProfit*_Point;
      CreateFiboLine("View_TP_"+suffix,tp,side==0?clrLime:clrRed,STYLE_DASH,"DISPLAY ONLY manual+own Basket TP "+suffix);
      double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      if(Positive(tick) && Positive(tv)) {
         double priceDistance=AccountInfoDouble(ACCOUNT_BALANCE)*GetDynamicGlobalRisk()/100.0*tick/(volume[side]*tv);
         CreateFiboLine("View_Stop_"+suffix,avg+(side==0?-1:1)*priceDistance,clrFireBrick,STYLE_DOT,
            "DISPLAY ONLY manual+own risk reference "+suffix+"; not broker SL or own-only stop trigger");
      }
   }
}

void DrawDiagnosticSignal(string module,int side,datetime bar,double price,string detail) {
   AuditCandidateHit(module);
   if(!DiagnosticMode || !ShowDiagnosticSignals) return;
   if(!RememberDiagnosticView(module,side,bar)) return;
   string name="DiagSig_"+module+IntegerToString(side)+"_"+IntegerToString((long)bar);
   DrawArrow(name,bar,price,side==POSITION_TYPE_BUY?clrLime:clrOrange,
      side==POSITION_TYPE_BUY?233:234,"DIAG CANDIDATE "+detail,side==POSITION_TYPE_BUY);
}

string ReadOnlyAIStatus() {
   if(!DiagnosticMode) return "AI: common-file commands | execution requires central gate";
   int h=FileOpen("ai_signal.txt",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(h==INVALID_HANDLE) return "AI: diagnostic read only | no command";
   string data=FileReadString(h); FileClose(h);
   string parts[];
   if(StringSplit(data,StringGetCharacter(";",0),parts)<3) return "AI: malformed command (not consumed)";
   if(parts[0]!=_Symbol && parts[0]!="ALL") return "AI: command for another symbol (not consumed)";
   if(parts[1]!="BUY" && parts[1]!="SELL") return "AI: unknown action (not consumed)";
   return "AI: "+parts[1]+" candidate, not consumed | Telegram disabled in diagnostics";
}

bool ReadViewIndicator(int handle,int buffer,double &value) {
   value=0;
   if(handle==INVALID_HANDLE || BarsCalculated(handle)<1) return false;
   double data[];
   if(CopyBuffer(handle,buffer,0,1,data)!=1 || !MathIsValidNumber(data[0])) return false;
   value=data[0]; return true;
}

bool CoveredByHud(int x,int y) {
   if(x<G_HudLeft-4 || x>G_HudLeft+G_HudWidth+4) return false;
   return (y>=G_HudTop-4 && y<=G_ScopeY+G_HudRow+4) ||
      (ShowFiboDiagnostics && y>=G_DiagTop-5 && y<=G_DiagBottom+5);
}

void MaskChartAnnotationsUnderHud() {
   int total=OwnObjectsTotal(0,0,-1);
   for(int i=0;i<total;i++) {
      string name=OwnObjectName(0,i,0,-1);
      int type=(int)ObjectGetInteger(0,ViewName(name),OBJPROP_TYPE);
      if(type==OBJ_TREND) { ObjectSetInteger(0,ViewName(name),OBJPROP_BACK,true); continue; }
      if(type!=OBJ_TEXT && type!=OBJ_ARROW) continue;
      int x=0,y=0;
      datetime time=(datetime)ObjectGetInteger(0,ViewName(name),OBJPROP_TIME,0);
      double price=ObjectGetDouble(0,ViewName(name),OBJPROP_PRICE,0);
      bool covered=ChartTimePriceToXY(0,0,time,price,x,y) && CoveredByHud(x,y);
      long periods=covered?OBJ_NO_PERIODS:OBJ_ALL_PERIODS;
      if(ObjectGetInteger(0,ViewName(name),OBJPROP_TIMEFRAMES)!=periods)
         ObjectSetInteger(0,ViewName(name),OBJPROP_TIMEFRAMES,periods);
   }
}

void RefreshVisuals() {
   UpdateHudLayout();
   ArrayResize(G_PriceCaptions,0);
   PaintHeaderBackground();
   CleanInvalidatedZones();
   UpdateH4Zones();
   UpdateMTFSwings();
   UpdateFiboDiagnostics();
   UpdateNativeFibonacciTools();
   UpdateLegacyStructureVisuals();
   PaintOwnManagementViews();
   UpdatePositionVisuals();
   UpdateCenterInfo();
   UpdateDashboardMTF();
   DrawCandleSize();
   CreateCloseButton();
   PaintSignalViews();
   PaintReferenceViews();
   PaintPriceCaptions();
   MaskChartAnnotationsUnderHud();
   ChartRedraw(0);
}

void SF_Clear() { ObjectsDeleteAll(0,ViewName(SF_Prefix)); }

void SF_Status(string message) {
   G_StructureStatus=message;
   if(!G_PaintFrame) return;
   if(SF_ShowStatus) SetViewLabel("StructureStatus",message,G_HudLeft,G_DiagBottom+8,clrSilver,8);
   else ObjectDelete(0,ViewName("StructureStatus"));
}

void SF_Line(string key,double price,color c,ENUM_LINE_STYLE style=STYLE_DASH)
{
   if(!ShowReferenceHLines) return;
   string name=SF_ActivePrefix+key;
   if(!ObjectCreate(0,ViewName(name),OBJ_HLINE,0,0,price))
   { Print("SF OBJECT ERROR ",name," code=",GetLastError());return; }
   ObjectSetInteger(0,ViewName(name),OBJPROP_COLOR,c);
   ObjectSetInteger(0,ViewName(name),OBJPROP_STYLE,style);
   ObjectSetInteger(0,ViewName(name),OBJPROP_WIDTH,1);
   ObjectSetInteger(0,ViewName(name),OBJPROP_HIDDEN,false);
   ObjectSetString(0,ViewName(name),OBJPROP_TOOLTIP,key+" "+DoubleToString(price,_Digits));
}

void SF_Trend(string key,datetime t1,double p1,datetime t2,double p2,color c)
{
   string name=SF_ActivePrefix+key;
   if(!ObjectCreate(0,ViewName(name),OBJ_TREND,0,t1,p1,t2,p2))
   { Print("SF OBJECT ERROR ",name," code=",GetLastError());return; }
   ObjectSetInteger(0,ViewName(name),OBJPROP_COLOR,c);
   ObjectSetInteger(0,ViewName(name),OBJPROP_WIDTH,2);
   ObjectSetInteger(0,ViewName(name),OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,ViewName(name),OBJPROP_HIDDEN,false);
}

void SF_OTE(datetime t,double p0,double p1)
{
   // p0 = broken extreme (impulse endpoint), p1 = origin.
   int direction=(p0>p1)?1:-1;
   double a=0.0,b=0.0,p786=0.0;
   if(!H4Retracement(direction,p1,p0,0.700,a) ||
      !H4Retracement(direction,p1,p0,0.790,b) ||
      !H4Retracement(direction,p1,p0,0.786,p786)) return;
   SF_Line("REF_070",a,clrMediumOrchid);
   SF_Line("REF_0786",p786,clrDeepPink);
   SF_Line("REF_079",b,clrMediumOrchid);
   if(!SF_ShowOTE) return;
   datetime until=iTime(_Symbol,SF_StructureTF,0)+PeriodSeconds(SF_StructureTF)*6;
   string name=SF_ActivePrefix+"REFERENCE_070_079_BOX";
   if(ObjectCreate(0,ViewName(name),OBJ_RECTANGLE,0,t,MathMax(a,b),until,MathMin(a,b)))
   {
      ObjectSetInteger(0,ViewName(name),OBJPROP_COLOR,clrMediumOrchid);
      ObjectSetInteger(0,ViewName(name),OBJPROP_FILL,false);
      ObjectSetInteger(0,ViewName(name),OBJPROP_BACK,true);
      ObjectSetInteger(0,ViewName(name),OBJPROP_STYLE,STYLE_DOT);
   }
}

void DrawCandleSize() {
   if(!Positive(_Point)) return;
   double high = iHigh(_Symbol, _Period, 0), low = iLow(_Symbol, _Period, 0);
   int pts = (int)MathRound((high - low) / _Point);
   string name = "CandleSizeText";
   datetime time0 = iTime(_Symbol, _Period, 0);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(ObjectFind(0,ViewName(name)) < 0) {
      ObjectCreate(0,ViewName(name), OBJ_TEXT, 0, time0, price);
      ObjectSetInteger(0,ViewName(name), OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0,ViewName(name), OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0,ViewName(name), OBJPROP_ANCHOR, ANCHOR_LEFT);
   }
   ObjectSetInteger(0,ViewName(name), OBJPROP_TIME, time0 + PeriodSeconds(_Period) * 2);
   ObjectSetDouble(0,ViewName(name), OBJPROP_PRICE, price);
   ObjectSetString(0,ViewName(name), OBJPROP_TEXT, " ← " + IntegerToString(pts) + " pts");
}

void DrawR(string n, datetime t1, double p1, datetime t2, double p2, color c, string txt="") {
   if(!G_PaintFrame) {
      if(StringFind(n,"BaseZone_")==0) QueueBaseView(n,t1,p1,t2,p2,c,txt);
      return;
   }
   bool h4zone=(StringFind(n,"OB_H4_")==0 || StringFind(n,"FVG_H4_")==0);
   if(h4zone && !DiagnosticShowH4Zones) { ObjectDelete(0,ViewName(n)); ObjectDelete(0,ViewName("Txt_"+n)); return; }
   if(ObjectFind(0,ViewName(n)) < 0) ObjectCreate(0,ViewName(n), OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectMove(0,ViewName(n),0,t1,p1); ObjectMove(0,ViewName(n),1,t2,p2);
   ObjectSetInteger(0,ViewName(n),OBJPROP_HIDDEN,false);
   ObjectSetInteger(0,ViewName(n), OBJPROP_COLOR, c);
   ObjectSetInteger(0,ViewName(n), OBJPROP_FILL, true);
   ObjectSetInteger(0,ViewName(n), OBJPROP_BACK, true);

   if(txt != "") {
      string tn = "Txt_" + n;
      if(ObjectFind(0,ViewName(tn)) < 0) ObjectCreate(0,ViewName(tn), OBJ_TEXT, 0, t1, p1);
      ObjectSetString(0,ViewName(tn), OBJPROP_TEXT, " " + txt);
      ObjectSetInteger(0,ViewName(tn), OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0,ViewName(tn), OBJPROP_FONTSIZE, 9);

      ObjectSetInteger(0,ViewName(tn), OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0,ViewName(tn), OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0,ViewName(tn), OBJPROP_BACK, false);
   }
}

void DrawStructureAndFibo() {
   double r050=0.0,r618=0.0,r790=0.0;
   if(!H4Retracement(SF_ConfirmedDirection,SF_ConfirmedOrigin,SF_ConfirmedBreak,0.500,r050) ||
      !H4Retracement(SF_ConfirmedDirection,SF_ConfirmedOrigin,SF_ConfirmedBreak,0.618,r618) ||
      !H4Retracement(SF_ConfirmedDirection,SF_ConfirmedOrigin,SF_ConfirmedBreak,0.790,r790))
   {
      ObjectsDeleteAll(0,ViewName("H4_Confirm_"));
      return;
   }
   CreateFiboLine("H4_Confirm_050",r050,clrDeepSkyBlue,STYLE_DASH,"H4 STRUCT 0.5");
   CreateFiboLine("H4_Confirm_618",r618,clrDeepSkyBlue,STYLE_DASH,"H4 STRUCT 0.618");
   CreateFiboLine("H4_Confirm_079",r790,clrDeepSkyBlue,STYLE_DASH,"H4 STRUCT 0.79");
}

void CreateFiboLine(string name, double price, color clr, ENUM_LINE_STYLE style, string text) {
   if(!G_PaintFrame) return;
   if(!ShowReferenceHLines && (StringFind(name,"Line_")==0 || StringFind(name,"H4_Confirm_")==0)) return;
   if(ObjectFind(0,ViewName(name)) < 0) ObjectCreate(0,ViewName(name), OBJ_HLINE, 0, 0, price);
   ObjectSetDouble(0,ViewName(name), OBJPROP_PRICE, 0, price);
   ObjectSetInteger(0,ViewName(name), OBJPROP_COLOR, clr);
   ObjectSetInteger(0,ViewName(name), OBJPROP_STYLE, style);
   RegisterPriceCaption(name,price,text,clr);
   ObjectSetString(0,ViewName(name), OBJPROP_TOOLTIP, text);
   ObjectSetString(0,ViewName(name),OBJPROP_TEXT,text);
   ObjectSetInteger(0,ViewName(name),OBJPROP_HIDDEN,false);
}

void CreateStructLine(string name, datetime t1, double p1, datetime t2, double p2, color clr, string text) {
   if(ObjectFind(0,ViewName(name)) < 0) ObjectCreate(0,ViewName(name), OBJ_TREND, 0, t1, p1, t2, p2);
   else {
      ObjectSetInteger(0,ViewName(name), OBJPROP_TIME, 0, t1); ObjectSetDouble(0,ViewName(name), OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0,ViewName(name), OBJPROP_TIME, 1, t2); ObjectSetDouble(0,ViewName(name), OBJPROP_PRICE, 1, p2);
   }
   ObjectSetInteger(0,ViewName(name), OBJPROP_COLOR, clr); ObjectSetInteger(0,ViewName(name), OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0,ViewName(name), OBJPROP_RAY_RIGHT, false); ObjectSetString(0,ViewName(name), OBJPROP_TOOLTIP, text);
   ObjectSetInteger(0,ViewName(name),OBJPROP_HIDDEN,false);
   ObjectSetInteger(0,ViewName(name),OBJPROP_BACK,false);
}

string GetTimerToNextBar() {
   int seconds = (int)(iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period) - TimeCurrent());
   return StringFormat("%02d:%02d", MathMax(0,seconds) / 60, MathMax(0,seconds) % 60);
}

void CreateCloseButton() {
   if(ObjectFind(0,ViewName("Btn_CloseAll")) < 0) {
      ObjectCreate(0,ViewName("Btn_CloseAll"), OBJ_BUTTON, 0, 0, 0);
   }
   {
      ObjectSetInteger(0,ViewName("Btn_CloseAll"), OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0,ViewName("Btn_CloseAll"), OBJPROP_XDISTANCE, MathMin(200,G_HudWidth));
      ObjectSetInteger(0,ViewName("Btn_CloseAll"), OBJPROP_YDISTANCE, 65);
      ObjectSetInteger(0,ViewName("Btn_CloseAll"), OBJPROP_XSIZE, 180);
      ObjectSetInteger(0,ViewName("Btn_CloseAll"), OBJPROP_YSIZE, 45);
      ObjectSetInteger(0,ViewName("Btn_CloseAll"), OBJPROP_FONTSIZE, 11);
      ObjectSetString(0,ViewName("Btn_CloseAll"), OBJPROP_TEXT, DiagnosticMode?"CLOSE OWN [DIAG]":"CLOSE ALL (OWN)");
      ObjectSetInteger(0,ViewName("Btn_CloseAll"), OBJPROP_BGCOLOR, clrFireBrick);
   }
}

void UpdateCenterInfo() {
   double volume=0,profit=0;
   for(int i=0;i<PositionsTotal();i++) {
      ulong t=PositionGetTicket(i);
      if(t>0 && PositionGetString(POSITION_SYMBOL)==_Symbol) {
         volume+=PositionGetDouble(POSITION_VOLUME);
         profit+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      }
   }
   string line="TIME "+GetTimerToNextBar()+" | BAL "+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+
      " | DAY "+DoubleToString(GetDailyPNL(),2)+" | RISK "+DoubleToString(GetDynamicRisk(),1)+"%"+
      " | LOTS "+DoubleToString(volume,2)+" | FLOAT "+DoubleToString(profit,2)+
      " | OTE "+GetActiveMacroOTE(SymbolInfoDouble(_Symbol,SYMBOL_BID))+" | OB "+GetNearestOBDistance();
   ClearSegmentedLabel("CenterInfo1"); ClearSegmentedLabel("CenterInfo2");
   for(int i=0;i<8;i++) { ClearSegmentedLabel("InfoMain_"+IntegerToString(i)); ClearSegmentedLabel("InfoDetails_"+IntegerToString(i)); }
   int size=InfoFontSize;
   while(size>8 && ViewTextWidth(line,size)>G_HudWidth) size--;
   // One row only; full values always remain in the tooltip on small charts.
   SetFittedViewLabel("InfoOneRow",line,G_HudLeft,G_SummaryY,profit>=0?clrLime:clrRed,size,G_HudWidth);
   SetFittedViewLabel("ScopeInfo","P/L: all magic on symbol; management: own magic only | "+
      (DiagnosticMode?"DIAGNOSTIC / NO REQUESTS":(G_StopLatched?"STOP LATCHED / ENTRIES BLOCKED":
      (EnableAutoTrade?"AUTO ENTRY ENABLED (gates apply)":"AUTO ENTRY OFF"))),
      G_HudLeft,G_ScopeY,clrSilver,MathMax(8,G_HudFont-1),G_HudWidth);
}

void UpdateFiboDiagnostics() {
   if(!ShowFiboDiagnostics) { G_DiagCanvas.Destroy(); G_DiagCanvasReady=false; ObjectsDeleteAll(0,ViewName("SN_DIAG_")); ObjectDelete(0,ViewName("DiagNext")); G_DiagBottom=G_ScopeY+G_HudRow; return; }
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   string d1="D1: WAITING";
   string h4="H4: WAITING";
   if(G_D1_Valid && G_Struct_High>G_Struct_Low) {
      double d1lo=MathMin(G_Fibo_618,G_Fibo_790);
      double d1hi=MathMax(G_Fibo_618,G_Fibo_790);
      string status=(bid>=d1lo && bid<=d1hi)?"IN REF .618-.790":"OUT REF .618-.790";
      d1="D1 "+(G_D1_Direction==1?"BUY":"SELL")+
         " | 0.618 "+DoubleToString(G_Fibo_618,_Digits)+
         " | 0.790 "+DoubleToString(G_Fibo_790,_Digits)+" | "+status;
   } else if(G_D1_DataReady && G_D1_SourceDay!=0) d1="D1: REJECTED (doji / optional impulse filter)";
   double p618=0.0,p790=0.0;
   bool h4valid=H4Retracement(SF_ConfirmedDirection,SF_ConfirmedOrigin,SF_ConfirmedBreak,0.618,p618) &&
                H4Retracement(SF_ConfirmedDirection,SF_ConfirmedOrigin,SF_ConfirmedBreak,0.790,p790);
   if(h4valid) {
      bool up=(SF_ConfirmedDirection==1);
      string status=(bid>=MathMin(p618,p790) && bid<=MathMax(p618,p790))?"IN REF .618-.790":"OUT REF .618-.790";
      // Invariant: UP deeper retracement is LOWER; DOWN deeper retracement is HIGHER.
      bool orderOK=up?(p790<p618):(p790>p618);
      h4="H4 "+(up?"UP":"DOWN")+" ["+SF_PivotStructure+"] | 0.618 "+DoubleToString(p618,_Digits)+
         " | 0.790 "+DoubleToString(p790,_Digits)+" | "+(orderOK?status:"FIB ORDER ERROR");
      // Check that actual confirmation lines and diagnostic prices agree.
      if(ObjectFind(0,ViewName("H4_Confirm_618"))>=0 && ObjectFind(0,ViewName("H4_Confirm_079"))>=0) {
         double line618=ObjectGetDouble(0,ViewName("H4_Confirm_618"),OBJPROP_PRICE);
         double line790=ObjectGetDouble(0,ViewName("H4_Confirm_079"),OBJPROP_PRICE);
         if(MathAbs(line618-p618)>_Point || MathAbs(line790-p790)>_Point)
            h4+=" | DRAW MISMATCH";
      }
   }
   string agreement="D1/H4: WAITING";
   if(G_D1_Valid && SF_ConfirmedDirection!=0)
      agreement=(G_D1_Direction==SF_ConfirmedDirection)?"D1/H4: ALIGNED":(BlockD1H4ConflictForEntries?"D1/H4: CONFLICT (FILTER ON)":"D1/H4: CONFLICT (FILTER OFF)");
   datetime lastClosedH4=iTime(_Symbol,SF_StructureTF,1);
   int ageBars=-1;
   if(SF_ConfirmedBreakTime>0) ageBars=iBarShift(_Symbol,SF_StructureTF,SF_ConfirmedBreakTime,false);
   string structure="H4 EVENT: WAITING";
   if(SF_ConfirmedBreakTime>0) {
      structure="H4 EVENT: "+TimeToString(SF_ConfirmedBreakTime,TIME_DATE|TIME_MINUTES)+
         " | age "+IntegerToString(ageBars)+" H4 bars"+
         " | pivots "+SF_PivotStructure;
      if(ageBars>H4OldStructureWarningBars) structure+=" | OLD STRUCTURE (review)";
   }
   string refresh="H4 CLOSED: "+(lastClosedH4>0?TimeToString(lastClosedH4,TIME_DATE|TIME_MINUTES):"WAITING")+
      " | D1 DAY: "+(G_D1_SourceDay>0?TimeToString(G_D1_SourceDay,TIME_DATE):"WAITING");
   string distance="PRICE: "+DoubleToString(bid,_Digits)+" | ";
   if(h4valid) {
      double nearEdge=(bid<MathMin(p618,p790)?MathMin(p618,p790):(bid>MathMax(p618,p790)?MathMax(p618,p790):bid));
      distance+="H4 REF distance "+DoubleToString(MathAbs(bid-nearEdge)/_Point,0)+" points";
   } else distance+="H4 OTE unavailable";
   double tradeLo=0,tradeHi=0;
   string tradeZone="D1 TRADE .790-1.000: WAIT";
   if(G_D1_DataReady && G_D1_Valid && TradeOTE(G_Fibo_isUp?G_Struct_Low:G_Struct_High,
      G_Fibo_isUp?G_Struct_High:G_Struct_Low,tradeLo,tradeHi))
      tradeZone="D1 TRADE .790-1.000: "+DoubleToString(tradeLo,_Digits)+".."+DoubleToString(tradeHi,_Digits)+
         ((bid>=tradeLo && bid<=tradeHi)?" IN (quote-side checked at entry)":" OUT");
   string safety="SAFETY: "+(DiagnosticMode?"DIAGNOSTIC / NO REQUESTS":(G_StopLatched?"ENTRIES BLOCKED":(EnableAutoTrade?"ENTRY ENABLED (gates apply)":"ENTRY OFF")))+
      (G_StopLatched?" | STOP LATCHED":"")+(!G_StateOK?" | STATE ERROR":"")+
      (G_ExecutionUncertain?" | EXECUTION UNCERTAIN":"")+(!SF_DataReady?" | H4 NOT READY":"");
   string lines[9];
   lines[0]=d1; lines[1]=h4; lines[2]=agreement;
   lines[3]=structure; lines[4]=refresh; lines[5]=distance; lines[6]=tradeZone; lines[7]=safety; lines[8]=ReadOnlyAIStatus();
   int x=G_HudLeft, y=G_DiagTop,row=ViewTextHeight(G_HudFont)+5;
   int room=MathMax(row,(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0)-y-36);
   int starts[10]; starts[0]=0; int pages=1,used=0;
   for(int i=0;i<9;i++) {
      int cost=(ViewTextWidth(lines[i],G_HudFont)>G_HudWidth?2:1)*row;
      cost=MathMin(room,cost);
      if(used>0 && used+cost>room) { starts[pages++]=i; used=0; }
      used+=cost;
   }
   starts[pages]=9; G_DiagPages=pages;
   G_DiagPage=MathMax(0,MathMin(G_DiagPage,pages-1));
   int expectedRows=0;
   for(int i=starts[G_DiagPage];i<starts[G_DiagPage+1];i++) {
      int rows=ViewTextWidth(lines[i],G_HudFont)>G_HudWidth?2:1;
      expectedRows+=MathMax(1,MathMin(rows,(room-expectedRows*row)/row));
   }
   PaintTransparentPanel(G_DiagCanvas,G_DiagCanvasReady,G_DiagCanvasWidth,G_DiagCanvasHeight,
      "SN_DIAG_READABLE_BG",x-5,y-5,G_HudWidth+10,expectedRows*row+(pages>1?32:0)+10);
   for(int i=0;i<9;i++) {
      string name="SN_DIAG_"+IntegerToString(i);
      ObjectDelete(0,ViewName(name)); // Older layout used one unbounded label per item
      if(i<starts[G_DiagPage] || i>=starts[G_DiagPage+1]) {
         for(int j=0;j<8;j++) ClearSegmentedLabel(name+"_"+IntegerToString(j));
         continue;
      }
      y+=PaintWrappedView(name,lines[i],x,y,i==0?clrGold:(i==1?clrDeepSkyBlue:(i==2?clrWhite:clrSilver)),
         G_HudFont,G_HudWidth,MathMax(1,MathMin(2,(G_DiagTop+room-y)/row)));
   }
   if(pages>1) {
      string nav="DiagNext";
      if(ObjectFind(0,ViewName(nav))<0) ObjectCreate(0,ViewName(nav),OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,ViewName(nav),OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,ViewName(nav),OBJPROP_XDISTANCE,G_HudLeft);
      ObjectSetInteger(0,ViewName(nav),OBJPROP_YDISTANCE,y+2);
      ObjectSetInteger(0,ViewName(nav),OBJPROP_XSIZE,MathMin(240,G_HudWidth));
      ObjectSetInteger(0,ViewName(nav),OBJPROP_YSIZE,28);
      ObjectSetInteger(0,ViewName(nav),OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,ViewName(nav),OBJPROP_BGCOLOR,clrDimGray);
      ObjectSetString(0,ViewName(nav),OBJPROP_TEXT,"DETAILS "+IntegerToString(G_DiagPage+1)+"/"+IntegerToString(pages)+" >");
      y+=32;
   } else ObjectDelete(0,ViewName("DiagNext"));
   G_DiagBottom=y;

}

void UpdateDashboardMTF() {
   if(!ShowMTFDashboard) { ObjectsDeleteAll(0,ViewName("DB_")); return; }
   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   int column=MathMin(G_HudWidth/G_HudColumns,ViewTextWidth("H4 DIAMOND RSI 100.0 DN",G_HudFont)+8),font=G_HudFont;
   for(int i=0;i<6;i++) {
      bool history=SeriesInfoInteger(_Symbol,mtf_tfs[i],SERIES_SYNCHRONIZED) && Bars(_Symbol,mtf_tfs[i])>=101;
      int ih=history?iHighest(_Symbol,mtf_tfs[i],MODE_HIGH,100,1):-1;
      int il=history?iLowest(_Symbol,mtf_tfs[i],MODE_LOW,100,1):-1;
      bool ready=ih>=1 && il>=1;
      double high=ready?iHigh(_Symbol,mtf_tfs[i],ih):0;
      double low=ready?iLow(_Symbol,mtf_tfs[i],il):0,range=high-low;
      ready=ready && Positive(low) && range>_Point;
      bool up=il>ih;
      string zone="WAIT";
      if(ready) {
         zone=price>low+range*0.5?"PREM":"DISC";
         if(price>=low+range*0.45 && price<=low+range*0.55) zone="EQ";
         double a=up?high-range*0.618:low+range*0.618;
         double b=up?high-range*0.790:low+range*0.790;
         if(price>=MathMin(a,b) && price<=MathMax(a,b)) zone="DIAMOND";

      }
      double rsi=0,e21=0,e55=0,e200=0,sc=0,ss=0,mm=0,ms=0;
      bool rsiOK=ReadViewIndicator(h_mtf_rsi[i],0,rsi);
      bool emaOK=ReadViewIndicator(h_mtf_ema21[i],0,e21) && ReadViewIndicator(h_mtf_ema55[i],0,e55) &&
         ReadViewIndicator(h_mtf_ema200[i],0,e200);
      bool stochOK=ReadViewIndicator(h_mtf_stoch[i],MAIN_LINE,sc) && ReadViewIndicator(h_mtf_stoch[i],SIGNAL_LINE,ss);
      bool macdOK=ReadViewIndicator(h_mtf_macd[i],0,mm) && ReadViewIndicator(h_mtf_macd[i],1,ms);
      G_MTFAuditFrames[i]++;
      if(ready && rsiOK && emaOK && stochOK && macdOK) G_MTFAuditReady[i]++;
      color rsiColor=!rsiOK?clrSilver:(rsi>=80?clrRed:(rsi<=20?clrLime:clrWhite));
      if(ready && zone=="DIAMOND" && rsiOK) rsiColor=Diamond_Color;
      string id=IntegerToString(i),tf=mtf_names[i]; int x=G_HudLeft+G_HudWidth-G_HudColumns*column+(i%G_HudColumns)*column;
      int y=G_HudTop+(i/G_HudColumns)*(G_HudCompact?1:3)*G_HudRow;
      ObjectDelete(0,ViewName("DB_Arr_"+id));
      SetFittedViewLabel("DB_Txt_"+id,tf+" "+zone+" RSI "+(rsiOK?DoubleToString(rsi,1):"WAIT")+" "+(emaOK?(e21>e55 && e55>e200?"UP":(e21<e55 && e55<e200?"DN":"EQ")):"?"),x,y,rsiColor,font,column-4);
      color stochColor=clrSilver;
      if(stochOK) {
         stochColor=clrWhite;
         if(sc<15) { stochColor=clrLime; }
         else if(sc>85) { stochColor=clrRed; }
      }
      ObjectDelete(0,ViewName("DB_StochArr_"+id));
      SetFittedViewLabel("DB_Stoch_"+id,tf+" STO "+(stochOK?DoubleToString(sc,0):"WAIT")+" "+(stochOK?(sc>ss?"UP":"DN"):"?"),x,y+G_HudRow,stochColor,font,column-4);
      color macdColor=!macdOK?clrSilver:(mm>ms?clrLime:(mm<ms?clrRed:clrGray));
      ObjectDelete(0,ViewName("DB_MacdArr_"+id));
      SetFittedViewLabel("DB_Macd_"+id,tf+" MACD "+(macdOK?DoubleToString(mm,2):"WAIT")+" "+(macdOK?(mm>ms?"UP":"DN"):"?"),x,y+2*G_HudRow,macdColor,font,column-4);
      if(G_HudCompact) {
         string combined=tf+" "+zone+" RSI "+(rsiOK?DoubleToString(rsi,1):"WAIT")+
            " "+(emaOK?(e21>e55 && e55>e200?"UP":(e21<e55 && e55<e200?"DN":"EQ")):"?")+
            " | STO "+(stochOK?DoubleToString(sc,0):"WAIT")+" "+(stochOK?(sc>ss?"UP":"DN"):"?")+
            " | MACD "+(macdOK?DoubleToString(mm,2):"WAIT")+" "+(macdOK?(mm>ms?"UP":"DN"):"?");
         SetFittedViewLabel("DB_Txt_"+id,combined,x,y,rsiColor,font,column-4);
         ClearSegmentedLabel("DB_Stoch_"+id); ClearSegmentedLabel("DB_Macd_"+id);
      }
   }
}

void DrawArrow(string obj_name, datetime t, double p, color clr, int arrow_code, string text, bool isBuy) {
   QueueArrowView(obj_name,t,p,clr,arrow_code,text,isBuy);
}

void PaintArrow(string obj_name, datetime t, double p, color clr, int arrow_code, string text, bool isBuy) {
   if(ObjectFind(0,ViewName(obj_name)) < 0) ObjectCreate(0,ViewName(obj_name), OBJ_ARROW, 0, t, p);
   ObjectSetInteger(0,ViewName(obj_name), OBJPROP_ARROWCODE, arrow_code);
   ObjectSetInteger(0,ViewName(obj_name), OBJPROP_COLOR, clr);
   ObjectSetInteger(0,ViewName(obj_name), OBJPROP_WIDTH, 2);

   string nt = "Txt_" + obj_name;
   if(ObjectFind(0,ViewName(nt)) < 0) ObjectCreate(0,ViewName(nt), OBJ_TEXT, 0, t, p);
   double offset = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 30;
   double p_txt = isBuy ? p - offset : p + offset;
   ObjectSetInteger(0,ViewName(nt), OBJPROP_TIME, 0, t); ObjectSetDouble(0,ViewName(nt), OBJPROP_PRICE, 0, p_txt);
   ObjectSetString(0,ViewName(nt), OBJPROP_TEXT, " " + text); ObjectSetInteger(0,ViewName(nt), OBJPROP_COLOR, clr);
   ObjectSetInteger(0,ViewName(nt), OBJPROP_FONTSIZE, 8); ObjectSetInteger(0,ViewName(nt), OBJPROP_ANCHOR, isBuy ? ANCHOR_UPPER : ANCHOR_LOWER);
}

void SendTelegramPhotoAlert(string message) {
   if(DiagnosticMode || MQLInfoInteger(MQL_TESTER)) return;
   if(Telegram_Token == "" || Telegram_Token == "ВСТАВЬ_ТОКЕН_СЮДА") return;
   string text = "🎯 <b>СИГНАЛ (Менеджер):</b> " + message + "\n<b>Пара:</b> " + _Symbol + " (" + EnumToString((ENUM_TIMEFRAMES)_Period) + ")";
   string url = "https://api.telegram.org/bot" + Telegram_Token + "/sendMessage?chat_id=" + Telegram_Chat_ID + "&parse_mode=HTML&text=" + text;
   char post[], result[]; string headers;
   WebRequest("GET", url, "", 5000, post, result, headers);

   string picName = "SniperManager.png";
   if(ChartScreenShot(0, picName, (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS), (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS))) {
      string photoUrl = "https://api.telegram.org/bot" + Telegram_Token + "/sendPhoto";
      int fileHandle = FileOpen(picName, FILE_READ|FILE_BIN);
      if(fileHandle != INVALID_HANDLE) {
         uint fileSize = (uint)FileSize(fileHandle);
         uchar fileData[];
         ArrayResize(fileData, fileSize);
         FileReadArray(fileHandle, fileData, 0, fileSize);
         FileClose(fileHandle);

         string boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW";

         string body_start = "--" + boundary + "\r\n" +
                             "Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n" +
                             Telegram_Chat_ID + "\r\n" +
                             "--" + boundary + "\r\n" +
                             "Content-Disposition: form-data; name=\"photo\"; filename=\"" + picName + "\"\r\n" +
                             "Content-Type: image/png\r\n\r\n";

         string body_end = "\r\n--" + boundary + "--\r\n";

         uchar dataStart[], dataEnd[], postData[];
         StringToCharArray(body_start, dataStart, 0, WHOLE_ARRAY, CP_UTF8);
         StringToCharArray(body_end, dataEnd, 0, WHOLE_ARRAY, CP_UTF8);

         int sizeStart = ArraySize(dataStart) - 1;
         int sizeEnd = ArraySize(dataEnd) - 1;
         ArrayResize(postData, sizeStart + fileSize + sizeEnd);
         ArrayCopy(postData, dataStart, 0, 0, sizeStart);
         ArrayCopy(postData, fileData, sizeStart, 0, fileSize);
         ArrayCopy(postData, dataEnd, sizeStart + fileSize, 0, sizeEnd);

         string head = "Content-Type: multipart/form-data; boundary=" + boundary + "\r\n";
         char res[];
         string resHeaders;
         WebRequest("POST", photoUrl, head, 10000, postData, res, resHeaders);
      }
   }
}

#endif // SNIPER365_DASHBOARD_MQH

// END Sniper365/Dashboard.mqh

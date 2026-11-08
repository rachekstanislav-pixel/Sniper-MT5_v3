# SYNTHETIC replay smoke test, not official publications

`SYNTHETIC_20261106.tsv` contains invented BUY at 2026-11-06 12:00 UTC and SELL
at 13:00 UTC, each expires 15 minutes later. These are deliberately synthetic directions,
not actual Fed decisions or a historical news dataset. The TSV protocol has no synthetic
field: provenance is carried by this filename/document. Never use it as live news input.
Real historical quotes come from the broker's Strategy Tester data; not supplied here.

Use Sniper_Manager_v3_6_6_NEWS_VIRTUAL.mq5 in local Strategy Tester, GOLD M5, real ticks, 2026-11-06 to 2026-11-07,
no optimization or remote/cloud agents. Python and WebRequest are not involved.
Put the TSV in Terminal Common Data Folder/Files, accessed via MT5 File/Open Common
Data Folder (if available), or from File/Open Data Folder navigate two levels up from
Terminal/<instance> to Terminal, then Common/Files.

Inputs for this smoke test only:
- DiagnosticMode=true (original BASE remains read-only)
- EnableAutoTrade=false
- News_Enabled=true
- News_Replay=true
- News_ReplayFile=SYNTHETIC_20261106.tsv
- News_JournalFile=SYNTHETIC_smoke_001.tsv (new name for each independent run)
- News_ConfirmationSeconds=1
- News_ConfirmationPoints=1
- News_StopPoints=500
- News_TargetPoints=1000
- News_HoldSeconds=60
- News_MaxSpreadPoints=1000 (relaxed smoke-test threshold, not live recommendation)
- News_ServerUTCOffsetSeconds=7200 ONLY if broker historical server time is UTC+2.
  Otherwise set actual historical offset in seconds. Do not confuse Windows timezone
  with broker tick time. For smoke testing the whole date, these events remain within
  the interval for usual broker offsets, but exact timing claims require verified offset.

Look in Common/Files/SYNTHETIC_smoke_001.tsv after the run. Each signal should produce
OBSERVE on its first available tick. OPEN requires actual directional price confirmation;
it is not guaranteed. If OPEN occurs, CLOSE should follow a level hit or 60-second timeout
at a subsequent tick. A single ID must not have multiple OPEN records. WAIT/expired is
valid if the price did not confirm; it does not test the OPEN/CLOSE branches.

Tester trade report may show zero trades: virtual entries are journal rows, not orders.
An empty or missing virtual journal does not establish success. Check tester Journal for
missing replay file, initialization errors or missing tick history. If either direction
never opens, further price-controlled testing is required; do not change the historical
news timestamps or call the OPEN/CLOSE workflow verified.

This fixture has not been run in actual MT5 by the author. No MetaEditor/MT5 execution
is available in the cloud. Existing real-input tests are separate from this synthetic test.

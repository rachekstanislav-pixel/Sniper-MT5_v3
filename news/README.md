# Полный советник с виртуальными новостями

**Основной файл для установки:** `Sniper_Manager_v3_6_5_NEWS_VIRTUAL.mq5` в корне репозитория.
Это полный BASE 3.65 с встроенным новостным кодом; дополнительные MQH для него не нужны.
Старый `Sniper_Manager_v3_6_5_BASE_ATR_RESTORED_VISUAL.mq5` сохранён без изменений.
Запускайте один из этих советников на счёте/символе, не оба одновременно с одинаковым Magic.

### Установка на Windows

1. Скачайте репозиторий целиком (GitHub → Code → Download ZIP) и распакуйте.
2. При установленном Python 3.10+ запустите `news/start_news_windows.cmd`. Окно оставьте открытым.
3. Откройте `http://127.0.0.1:8765/events` в браузере. Для подтверждения сбора нужны
   `errors: []` и фактические публикации. При ошибках сохраните их текст — это ещё не рабочий сбор.
4. Скопируйте **полный** `Sniper_Manager_v3_6_5_NEWS_VIRTUAL.mq5` в `MQL5/Experts`.
   Скомпилируйте MetaEditor и установите на GOLD/XAUUSD M5 вместо прежнего экземпляра.
5. Разрешите WebRequest для `http://127.0.0.1:8765` в MT5.
   На графике появится строка `NEWS [VIRTUAL ONLY]` с состоянием.

**Внимание:** это полноценный советник с сохранённой реальной торговлей BASE.
`News_Enabled=false` отключает только новости, не BASE. Не запускайте на реальном счёте
для первой проверки. `DiagnosticMode=true` сохраняет запрет сетевых запросов исходного
диагностического режима; для проверки live-новостей нужен обычный режим на демо.
Новостные сигналы не меняют фильтры BASE, риск, SL/TP и управление реальными позициями.

Параметры новостного блока теперь имеют префикс `News_`: `News_Replay`,
`News_ServerUTCOffsetSeconds`, `News_JournalFile` и т.д. Ошибка инициализации новостей
не останавливает основной советник; статус становится WAIT. Открытые виртуальные позиции
продолжают сопровождаться по котировкам при потере связи с сервисом.
Один вызов WebRequest может задержать обработку событий основного EA до заданного
таймаута 200 мс раз в минимум 5 секунд; строгая эквивалентность времени исполнения BASE
не заявляется. При необходимости отключите новости через `News_Enabled=false`.
Сервис опрашивает источники в отдельном потоке, HTTP выдаёт уже сохранённые данные.
Отдельный MQ5 оставлен как вспомогательный стенд; для него рядом нужен `SniperNews.mqh`.

### Проверки интеграции

`python3 news/build_integrated.py` воспроизводит полный файл из неизменённого BASE,
`news/mt5/SniperNews.mqh` и `news/render_status.mqpart`.
`python3 -m unittest discover -s news/tests -v` проверяет также точное восстановление
исходного BASE после удаления только добавленных hooks и новостного кода.
Это статическая проверка сохранности торгового кода, не доказательство поведения MT5.

Ниже описание протокола и исходного отдельного стенда; при работе с полным советником
используйте имена настроек с префиксом `News_`.

---

# GOLD/M5: отдельный виртуальный новостной эксперимент

Исходный `Sniper_Manager_v3_6_5_BASE_ATR_RESTORED_VISUAL.mq5` (3.65) не изменён.
`MetaTrader5_v1.txt` — старый исходник MQL5, не SET и не документация; не используется модулем.
В TXT обнаружен встроенный Telegram-токен: отзовите его у BotFather; новый храните вне Git.

## Статус проверки источников — 2026-11-02

Кандидаты официальных RSS (не сторонние агрегаторы):

| Источник | URL | Назначение |
|---|---|---|
| FED | https://www.federalreserve.gov/feeds/press_monetary.xml | Monetary policy, решения и заявления |
| BLS | https://www.bls.gov/feed/cpi.rss | CPI |
| BLS | https://www.bls.gov/feed/empsit.rss | Employment Situation: NFP и безработица |
| BEA | https://apps.bea.gov/rss/rss.xml | PCE / Personal Income and Outlays, GDP и другие релизы |

Проверка из облака остановлена HTTP CONNECT 403 от прокси. Это **не** ответ этих сайтов.
Актуальность URL, XML-формат, полный охват релизов и возможность автоматического получения пока не подтверждены.
Нельзя считать текущие адаптеры проверенными на реальных публикациях.
Сервис поддерживает RSS 2.0 и Atom 1.0, не HTML. Изменение формата ведёт к WAIT, а не к догадкам.

Страницы для проверки условий (доступ также заблокирован):
- https://www.federalreserve.gov/disclaimer.htm
- https://www.bls.gov/bls/linksite.htm
- https://www.bea.gov/about/policies-and-information

Официальные публичные публикации выбраны для бесплатного эксперимента; актуальные условия,
ограничения автоматического доступа и права на сторонние материалы ещё нужно проверить.
Подписки, API-ключи и платный ИИ отсутствуют. Сохраняйте ссылки и атрибуцию источников;
не считайте эту реализацию подтверждением разрешения на перепубликацию.

## Сервис (Python 3.10+, только стандартная библиотека)

```sh
cd /workspace/Sniper-MT5_v3
python3 -m unittest discover -s news/tests -v
mkdir -p /tmp/sniper-news
python3 news/service.py --db /tmp/sniper-news/news.sqlite3 --port 8765
```

Сервис слушает только 127.0.0.1. Запустите его на том же компьютере, где MT5.
Облачный localhost недоступен локальному терминалу. Не открывайте сервис в Интернет.
GET `/events` возвращает JSON с ID, source, url, published_at, received_at, available_at,
event_type, title, numbers, signal, reason, expires_at; даты — UTC Unix seconds.
GET `/signal.tsv` — компактный машинный транспорт для советника, не замена JSON-журнала.
Опрос источников выполняется фоновым потоком раз в минуту; таймаут каждого запроса 20 секунд.
До первого успешного опроса и во время обновления выдаётся WAIT. Устаревшее состояние сборщика также даёт WAIT.
При ошибке любого источника live-выдача всех направлений блокируется (WAIT).
`--once` делает один опрос и возвращает ненулевой exit code при ошибках.
Проверяйте ошибки: работающий HTTP-сервер ещё не доказывает получение новостей.

SQLite сохраняет первую версию публикации по source+URL. Повторный опрос не обновляет
время доступности. Исправления по тому же URL не считаются новой торговой возможностью.
Ограничение: иной URL для той же новости может дать иной ID; не добавляйте зеркальные feeds.
Архив содержит нормализованные записи, не полную историческую базу/сырые страницы.

## Гипотеза

Только FED RATE: явное `decided to raise/lower ... target range ... X to Y percent`
в официальной странице допускает SELL/BUY соответственно. Удержание ставки, дроби вместо
десятичных значений и неоднозначный текст => WAIT. Это узкий проверяемый парсер, не NLP.
Он сохраняет новый диапазон ставки; изменение в базисных пунктах и старое значение не выдумываются.
CPI, NFP/безработица, PCE, GDP и прочие события пока только собираются: `numbers={}`, WAIT.
Разбор их чисел не реализован; отсутствие чисел явно отражено пустым объектом.
Рыночный консенсус отсутствует и не заменяется предыдущим значением.
Направление в JSON — только гипотеза: виртуальный вход возможен после подтверждения цены советником.

## MT5 live

1. Скопируйте `mt5/Sniper_News_Virtual.mq5` в `MQL5/Experts`, скомпилируйте MetaEditor.
2. В настройках Expert Advisors разрешите WebRequest для `http://127.0.0.1:8765`.
3. Откройте брокерский GOLD/XAUUSD M5. Присоедините **отдельный** советник.
   Автоторговля ему не нужна. В коде отсутствуют торговые API.
4. Настройки встроены: Replay=false, подтверждение 60 секунд и 100 points,
   SL=500 points, цель=1000 points, max spread=100 points, выход через 1800 секунд.
   Points — `_Point` брокера, не доллары и не универсальные gold pips.
5. После новости первая наблюдаемая котировка становится базой. Лишь последующие
   котировки через минимум 60 секунд могут подтвердить движение. Данные до получения не используются.

Журнал `sniper_news_virtual.tsv` в Terminal Common Files содержит OBSERVE/WAIT/OPEN/CLOSE,
UTC, цену, SL, цель, результат в points, объяснение. BUY входит по Ask и выходит по Bid;
SELL входит по Bid и выходит по Ask. Спред учтён. Стоп/цель исполняются по первой
наблюдаемой котировке за уровнем (возможен разрыв), без комиссии, задержки и дополнительного
проскальзывания. Денежный P&L и размер позиции не моделируются.
По ID возможна максимум одна попытка. Занятый модуль потребляет новость как WAIT.
Потреблённые ID восстанавливаются из журнала; не удаляйте журнал для продолжения live-сессии.
После перезапуска открытая виртуальная позиция не восстанавливается: результат UNRESOLVED,
не считать её закрытой или прибыльной. Для отдельного теста используйте отдельное имя журнала.

## Strategy Tester: без WebRequest

```sh
python3 news/service.py --db /tmp/sniper-news/news.sqlite3 --export /tmp/sniper-news/recorded
```

Экспорт создаёт JSONL для аудита и TSV (без заголовка):
`id<TAB>available_at<TAB>expires_at<TAB>direction`, direction -1/0/1.
Скопируйте `recorded.tsv` в Common Files как `sniper_news.tsv`.
Tester автоматически использует файл, даже если Replay=false; WebRequest не вызывается.
Рекомендуется «Every tick based on real ticks», GOLD M5, период с доступными реальными записями.
Укажите `ServerUTCOffsetSeconds`: UTC = broker tick time минус offset. Для DST разделяйте
тест на интервалы с постоянным смещением. Неверный offset делает временной тест недостоверным.

Записи отсортированы по max(published_at, received_at): событие нельзя использовать раньше
его первого фактического получения. Экспорт сегодняшнего RSS не является исторической
базой новостей: старые публикации будут WAIT и не должны получать искусственное раннее время.
TTL=900 секунд от публикации. Файл replay считается доверенным экспортом; его ручное
редактирование может нарушить причинность. Для независимых прогонов задайте новый JournalFile,
иначе ранее потреблённые ID будут пропущены. Не запускайте несколько экземпляров с одним журналом.

Все входные строки в unit tests — **синтетические** фикстуры, не реальные новости/результаты.
В живом сервисе synthetic=true блокирует направленный сигнал. Исторические синтетические
цены/публикации не поставляются и не выдаются за бэктест.

## Что проверено

Unit tests: RSS-разбор/недоверенный host, строгий парсер ставки, дубликаты,
неизменность available_at, устаревание, преждевременные данные, WAIT, сериализация replay,
статическая проверка отсутствия торговых API в отдельном MQ5.
Это не компиляция MQL5 и не фактическая проверка отсутствия приказов в терминале.
MetaEditor и MT5 в Linux-среде не запускались; компиляция и live/Tester-прогон обязательны
до выводов о поведении. Оригинальная стратегия не тестировалась и не менялась.
Прибыльность и качество торгового преимущества не установлены.

Проверка HTTP в облаке: `/events` вернул 200 и 4 ошибки источников; `/signal.tsv` вернул WAIT.
Это проверка безопасного отказа, не успешного сбора официальных новостей. 8 unit tests прошли.

После интеграции: 11 тестов прошли; HTTP JSON/TSV проверены, при недоступных источниках WAIT.
Повторный реальный опрос источников завершился четырьмя сетевыми ошибками, записей получено 0.

## Обновление сервиса 0.3.0

Для установленного сервиса: остановите окно через Ctrl+C, замените только `news/service.py`
и снова запустите `start_news_windows.cmd`. Советник перекомпилировать не требуется.
SQLite `%LOCALAPPDATA%/sniper-news.sqlite3` сохраняйте: удаление сбросит историю получения.
На `/events` проверьте `version: "0.3.0"` и раздел `sources`; JSON теперь отформатирован.
Ошибки выводятся также в консоль после каждого опроса.

BEA URL заменён на кандидат `https://apps.bea.gov/rss/rss.xml`; это не подтверждение
его доступности. BLS URL не менялись без доказательства их ошибочности.
`http_status: 403` = отказ HTTP-сервера/шлюза; 404 = URL не найден; 429 = ограничение частоты.
`proxy_http_status` с `category: proxy_connect_error` означает отказ CONNECT-прокси,
а не ответ официального сайта. Не отключайте TLS и не обходите ограничения доступа.
Пустой или неподдерживаемый RSS теперь явно считается ошибкой, а не успешным сбором.
Ошибки любого источника по-прежнему блокируют все направления (WAIT).
Проверка новых адресов из облака снова упёрлась в CONNECT 403. Нужна повторная проверка
на машине пользователя, где ФРС уже успешно получена; статусы BLS/BEA пока неизвестны.

## Обновление 0.3.1: Atom BLS

На скриншоте пользователя BLS CPI успешно открыт браузером и имеет Atom namespace
`http://www.w3.org/2005/Atom`, а не RSS 2.0. Добавлен отдельный Atom-парсер: entry/link href,
published с часовым поясом и дробными секундами. `updated` не заменяет published.
Тип CPI/Employment определяется также по официальному feed ID. Числа пока не извлекаются,
BLS остаётся collection-only / WAIT. Проверено на явно синтетических структурных примерах.
Всего 20 тестов прошли. Это не успешный Python HTTP-запрос BLS на VPS.

Открытие в браузере не объясняет 403 сервиса: различаются HTTP-клиент, cookies и путь доступа.
Версия 0.3.1 исправляет разбор Atom, но не заявляет устранение отказа доступа.
Для обновления достаточно заменить service.py и перезапустить сервис, сохранив SQLite.
Если остаётся http_status 403, повторная установка Python и MQ5 не поможет.

## Текущая политика 0.4.0 (заменяет общий запрет версий 0.1–0.3)

Ошибка BLS больше не блокирует независимую гипотезу FED. Любая публикация требует
успешной свежей проверки **своего** источника. Ошибка FED блокирует FED; неизвестное
состояние сборщика, обновление и устаревший статус блокируют все направления.
BLS и BEA по-прежнему только журналируются. Статус BLS 403 остаётся нерешённым;
изменение политики не означает восстановление BLS. Доступ не обходится.
Последняя публикация BEA/OTHER теперь не перекрывает пригодную FED RATE.
Добавлены дробные диапазоны ставки вида `3-3/4 to 4 percent`.

В MT5 `CONNECTED: WAIT no fresh rate signal` означает успешный HTTP-ответ без направления,
`WAIT: service unavailable (код)` — ошибку связи, `VIRTUAL BUY/SELL` — виртуальную позицию.
Обновлять нужно service.py и полный MQ5; базу SQLite сохранять. MQ5 требуется перекомпилировать.
В полном файле сохранено явное datetime-преобразование, ранее проверенное пользователем.

25 автоматических проверок логики/структуры прошли. Тестовые публикации синтетические.
MetaEditor для этой ревизии и фактический виртуальный вход/replay в MT5 не запускались.
Ранее пользователь подтвердил компиляцию предыдущей ревизии, не этой.
Проверка всего цикла в MT5 всё ещё необходима; прибыльность не установлена.

## Repair 0.5.0 — why no news signal

The uploaded live JSON contained only expired publications, including four FED RATE
records with empty `numbers`. Expired events must remain WAIT: historical RSS items do
not become fresh by restarting the service or extending a tester date range.

Two defects corrected:
1. Existing empty FED interpretations were permanently skipped. The service now reparses
   legacy empty records once per parser revision, and retries transient document errors
   after at least 60 seconds. Successful interpretations remain immutable. First feed
   receipt/publication timestamps stay intact; a later interpretation has a later
   `available_at`, so it is never replayed before the supporting page was obtained.
2. HTTP WAIT/outages cleared a pending EA event but left its ID consumed forever.
   The pending event now pauses until recovery or expiry. No entry while paused.
   After recovery the same ID resumes without another OBSERVE or duplicate entry;
   price confirmation starts over. Already open virtual trades continue quote-based exits.

Parser handles Unicode fractions and HTML entities/tags; contradictory decisions return
WAIT. Original feed and release response bytes are archived in the same SQLite database,
keyed by URL and SHA256 for future analysis. No BLS access-control bypass was added.
A stored unrecognized response is retried after a parser version upgrade; transient
HTTP errors are retried. A successful already interpreted decision is not overwritten
by a revised page.

Open `http://127.0.0.1:8765/status` for a compact diagnostic report. It shows readiness,
source errors, latest rate publication and age, parsed range/action, parse failure,
current decision and wait reason counts. `/events` retains the full archive view.
Live response header `X-Sniper-State` explains WAIT on the updated EA label:
- STALE_RATE: latest rate release expired (15-minute TTL remains unchanged).
- FED_UNAVAILABLE: own source unavailable/stale.
- RATE_RELEASE_ERROR / RATE_TEXT_UNRECOGNIZED: release fetch/parser problem.
- RATE_UNCHANGED: no directional change in rate.
- COLLECTOR_PAUSED: initial collection, refresh or stale/failed collector.

Update **service.py and full integrated MQ5**; rebuild the latter in MetaEditor.
Keep SQLite and live news journals. Original BASE source is unchanged.
This does not add directions for CPI/NFP/PCE/GDP: the original scope remains FED rate
changes only; a quiet period is valid. A long tester run without a genuine publication
archive is still not a long historical news test. No artificial current timestamp or
synthetic direction is injected into live feeds.

Validation: 31 automated tests passed, including a C++ compatibility harness running
selected actual MQL news function bodies with synthetic quotes (pause/recovery, timeout,
BUY/SELL, SL/target, expiry, deduplication). This harness is **not** MetaEditor or MT5.
Separate synthetic local HTTP smoke exercised Unicode rate parsing, isolation of BLS
403, JSON /status, TSV signal and reason header. Live BLS remains unresolved. No current
FED release was fetched in this repair; actual official wording beyond tested forms,
new MetaEditor compilation and real future-news execution remain unverified.

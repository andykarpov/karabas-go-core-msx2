# Ядро MSX2 для Karabas Go / Mini / Mini G

[English version](README.md)

**В работе.** Компьютер MSX2 / MSX2+ для плат семейства Karabas Go: машина MSX1-ядра
[karabas-go-core-msx](https://github.com/andykarpov/karabas-go-core-msx) (порт
[MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer), автор molekula) с ESE-VDP (V9958 / V9938)
и RTC из [OCM-PLD](https://github.com/gnogni/ocm-pld-dev) (KdL), изображение идёт через буфер кадра в
SDRAM. ПЛИС плат — Xilinx Spartan-6 XC6SLX25. Вся работа с файлами (картриджи, образы дисков,
кассеты, BIOS) идёт через OSD и файловый браузер прошивки платы: своего загрузчика в ядре нет. План и
решения — `docs/PLAN.md`.

| Плата | Файл ядра | Видео | Звук | Состояние |
|---|---|---|---|---|
| Karabas Mini G | `msx2.kg` | HDMI, 640x480 60 Гц | HDMI, I2S ЦАП (PCM5102) | проверено на железе |
| Karabas Mini | `msx2.kg` | HDMI, 640x480 60 Гц | HDMI, аналоговый выход (sigma-delta) | собрано, на железе не проверено |
| Karabas Go | `msx2.kg` | VGA, 640x480 60 Гц | I2S ЦАП (PCM5102) | собрано, на железе не проверено |

Файл ядра — `src/msx2.kg`, один для всех трёх плат. Нужна прошивка v26103113 или новее.

## Что умеет

- **MSX2 / MSX2+:** Z80 (T80) на 3,58 МГц (турбо: 5,37 или 7,16 МГц, пункт OSD CPU), ESE-VDP из OCM-PLD как V9958 (MSX2+: YJK-режимы
  SCREEN 10–12, горизонтальный скролл) или V9938 (пункт OSD VDP), 128 КБ VRAM, звук AY-3-8910 (jt49),
  PPI, 512 КБ ОЗУ с memory mapper (порты FC–FF; пункт OSD RAM, 64K: просто 64 КБ), часы RP5C01
  (порты B4–B5) со временем платы, kanji ROM (порты D8–DB, JIS уровней 1 и 2) со шрифтом из файла
  BIOS.
- **MSX-MUSIC:** OPLL (YM2413, [jt2413](https://github.com/jotego/jtopl)) на портах 7C–7D, ROM
  MSX-MUSIC в своём слоте (C-BIOS: 3-1, BIOS OCM: 0-2). Пункт OSD FM (MSX-MUSIC) его выключает.
- **Два слота картриджей** (A в слоте 1, B в слоте 2), до 1 МБ каждый, маппер определяется по ROM:
  без маппера (16 / 32 / 48 КБ), Konami, Konami SCC (со звуком SCC), ASCII 8, ASCII 16, Game
  Master 2, линейный 64 КБ. Пункты OSD Mapper A / Mapper B задают его вручную.
- **Дисковод:** интерфейс Philips VY-0010 (контроллер WD1793 и его disk ROM, Disk BASIC 1.0) в
  слоте 1 вместо картриджа A, образы `.dsk` на 360 или 720 КБ; образ в фоне читается в SRAM платы,
  запись идёт в SRAM и сразу в файл образа. Файл только для чтения — диск с защитой от записи.
- **Физические дисководы (Karabas Go):** Disk A и Disk B могут быть дисководами разъёма (`[ Physical A ]` /
  `[ Physical B ]` в файловом браузере, DS0 / DS1), ими управляет модель WD1793 (VG93) на выводах,
  как в MSX1-ядре.
- **Nextor на образе жёсткого диска:** SD-интерфейс MSX1FPGA в слоте 1 (вместо картриджа A или
  дисковода) со своим драйвером Nextor, на файле образа (`.img`, `.hdd`, `.vhd`, `.dsk`) с SD-карты
  платы. ROM Nextor — отдельный файл (см. «BIOS и Nextor»). Монтирование первого образа сбрасывает
  машину, поэтому Nextor видит свой диск сразу при старте ядра.
- **Кассета:** файлы `.cas` (до 128 КБ) проигрываются на вход магнитофона, пока мотор PPI включён,
  как с настоящего магнитофона (`RUN"CAS:"`, `BLOAD"CAS:",R`, `CLOAD`). Вместо этого входом может
  быть пин TAPE_IN платы, на TAPE_OUT идёт выход магнитофона (`CSAVE`).
- **Настройки MSX (CMOS часов)** хранятся на SD-карте: `SET SCREEN`, `SET PROMPT`, `SET BEEP`,
  `SET TITLE`, пароль. Прошивка платы держит их в `/config/msx2.eep` и отдаёт ядру при каждом старте.
  Время и дата — часов платы; установка их из MSX (`TIME`, `DATE`, `SET TIME`) часы платы не меняет.
- **Видео:** изображение VDP (256 или 512 точек, 192 / 212 строк, с бордюром) в 640x480 60 Гц из буфера
  кадра в SDRAM; VDP работает в развёртке PAL (50 Гц) или NTSC (60 Гц): Auto — по регистру 9 (BIOS,
  программы), либо пункт OSD Video задаёт её явно. Чересстрочные режимы (424 строки, две страницы по очереди)
  сплетаются из двух полей в один кадр на 480 строк.
- **Ввод:** USB-клавиатура как клавиатура MSX, два джойстика MSX: джойстики платы или USB-геймпады.

Проверено на Mini G: C-BIOS и BIOS OCM (MSX BASIC 3.0), картриджи со звуком (PSG, MSX-MUSIC), экраны
V9958 (в том числе YJK), Disk BASIC на `.dsk`, Nextor 2.1 на образе диска, игра с `.cas`, время платы и
сохранение CMOS после перезапуска, kanji BASIC (`CALL KANJI`), турбо (Nextor на 7,16 МГц), чересстрочный экран. На железе ещё не проверены: TAPE_IN / TAPE_OUT, джойстики,
развёртка 50 Гц, режим V9938.

Ещё нет: SCC MegaRAM, FM-PAC, картриджей с батарейкой.

## BIOS и Nextor

Ядро стартует с **C-BIOS** 0.29a (MSX2+, EU, со своим логотипом), он встроен в файл ядра. C-BIOS
запускает картриджи, но в нём нет BASIC и процедур кассеты и дисковода (disk ROM и Nextor с ним
зависают). Для BASIC, дисков, кассет и Nextor загрузите настоящий BIOS пунктом **BIOS** (страница
Machine): он загружается заново при каждом старте ядра.

Пункт BIOS принимает **образ системных ROM OCM-PLD** (1chipMSX / MSX++) — файл `OCM-BIOS.DAT` (512 КБ:
SDBIOS OCM-PLD, есть и в наборе SD-карты uMSX). Другие образы, например main ROM настоящей машины на
32 КБ, пока не поддерживаются: ядро раскладывает системные ROM так, как этот образ.

| В `OCM-BIOS.DAT` | Содержимое | Слот |
|---|---|---|
| 000000 | ESE-RAM / Nextor OCM | выключен (читается FF) |
| 020000 | main ROM MSX2+ (MSX BASIC 3.0) | 0-0 |
| 028000 | XBASIC | 3-3 |
| 02C000 | MSX-MUSIC | 0-2 |
| 030000 | sub-ROM, kanji BASIC | 3-1 |
| 040000 | шрифт kanji, JIS уровней 1 и 2 (256 КБ) | порты kanji D8–DB |

ОЗУ — в слоте 3-0. С C-BIOS раскладка другая, как в его конфигурации openMSX: слот 0 не расширен
(main ROM, логотип), 3-0 sub-ROM, 3-1 MSX-MUSIC, 3-2 ОЗУ. Раскладка выбирается по файлу: раскладка
C-BIOS — пока не загружен файл BIOS.

Что надо знать о BIOS OCM:

- **Клавиатура у него японская.** Клавиши PC-клавиатуры дают символы японского MSX: Shift+2 — `"`,
  Shift+минус — `=`, Shift+8 / Shift+9 — `(` / `)`, клавиша справа от `;` — `:`.
- **Он сам ставит CMOS часов при каждом старте из своего образа** (у 1chipMSX нет батарейки: утилита
  RTCSAVE OCM записывает настройки в файл BIOS на его SD-карте). Ядро вместо этого подставляет ему
  настройки из `/config/msx2.eep`, поэтому `SET SCREEN` и остальные сохраняются; RTCSAVE не нужна и не
  используется.
- Его собственный Nextor (000000 образа) не используется: Nextor работает в слоте 1 (Machine > Slot 1 =
  Nextor) с ROM из пункта Nextor ROM.
- MSX-MUSIC стоит в слоте 0-2: программа, которая ищет его только в другом слоте, его не найдёт.

**ROM Nextor:** `NEXTOR.ROM` из MSX1FPGA (`Support/SD/MSX1FPGA`, Nextor 2.1 с драйвером его
SD-интерфейса, SHA-1 `ffb666c031edac8642c637a42af770ad2c10c764`) в `/msx2` (имя по умолчанию у пункта).
ROM Nextor с драйверами другого железа останавливаются с «Bad drive name».

## Начало работы

1. Скопируйте `msx2.kg` в корень SD-карты.
2. Положите файлы в папку `/msx2` на SD-карте: картриджи (`.rom`, `.mx1`, `.mx2`, `.bin`), образы
   дисков (`.dsk`), кассеты (`.cas`), `OCM-BIOS.DAT`, `NEXTOR.ROM` и образы жёстких дисков.
3. Выберите MSX2 в меню ядер, откройте OSD (Menu+Esc) и загрузите картридж пунктом Cart A (Menu+F1).
   Машина запускает картридж после загрузки.
4. Для BASIC: Machine > BIOS = `OCM-BIOS.DAT` (стартует MSX BASIC 3.0).

Диск: Machine > Slot 1 = Disk drive, затем `.dsk` в Disk A. Nextor: Machine > Slot 1 = Nextor, затем
образ в HDD (Nextor стартует с `A:\>`; `BASIC` — в BASIC, `CALL SYSTEM` — обратно). Кассета: `.cas` в
Tape (Menu+F4), затем `RUN"CAS:"` (программы на BASIC), `BLOAD"CAS:",R` (машинный код) или
`CLOAD` + `RUN`; Tape rewind начинает файл сначала. Дискам, кассетам и Nextor нужен файл BIOS.

## Меню OSD

На главной странице — носители, видео и сброс; настройки машины — на странице Machine (Enter / Right
открывает её, Esc — назад).

| Пункт | Значения | Горячая клавиша |
|---|---|---|
| Cart A | картридж в слот 1 (виден при Slot 1 = Cartridge A) | Menu+F1 |
| Disk A | образ `.dsk` дисковода, на Go также физический дисковод (виден при Slot 1 = Disk drive) | Menu+F3 |
| Disk B | только Go: физический дисковод B (виден при Slot 1 = Disk drive) | Menu+F6 |
| HDD | образ жёсткого диска Nextor (виден при Slot 1 = Nextor) | Menu+F5 |
| Cart B | картридж в слот 2 | Menu+F2 |
| Tape | файл `.cas` (серый при Tape input = Tape in) | Menu+F4 |
| Tape rewind | кассета с начала (как Tape) | Menu+R |
| Video | Auto / PAL 50Hz / NTSC 60Hz | Menu+V |
| Joysticks | Normal / Swap | Menu+J |
| **Machine** ► | | |
| Reset | сброс MSX | F12 |
| Eject carts | вынимает оба картриджа (и сбрасывает) | Menu+E |
| *Machine:* Slot 1 | Cartridge A / Disk drive / Nextor | Menu+D |
| Slot 1 ROM | On / Off (серый при Cartridge A) | |
| Mapper A | Auto / None / Game Master 2 / Konami / Konami SCC / ASCII 8 / ASCII 16 / Linear 64K (серый, если Slot 1 не Cartridge A) | |
| Mapper B | как Mapper A | |
| VDP | V9958 (MSX2+) / V9938 (MSX2) | |
| CPU | 3.58 MHz / 5.37 MHz / 7.16 MHz | Menu+T |
| RAM | 512K mapper / 64K | |
| FM (MSX-MUSIC) | On / Off | |
| Tape input | CAS file / Tape in (TAPE_IN) | |
| BIOS | образ системных ROM (`OCM-BIOS.DAT`), загружается при каждом старте | |
| Nextor ROM | ROM Nextor (128 КБ), загружается при каждом старте (по умолчанию `NEXTOR.ROM`) | |

«Menu» — клавиша Windows. Загрузка картриджа, BIOS или ROM Nextor, смена маппера, Slot 1, RAM или FM
сбрасывают машину; загрузка кассеты — нет. Slot 1 ROM = Off оставляет дисковод или SD-интерфейс без
ROM (только регистры) — для тестовых программ, которые работают с ними сами под C-BIOS.

Турбо (CPU = 5,37 или 7,16 МГц) ускоряет ОЗУ и системные ROM; ввод-вывод и слоты 1 и 2 (картриджи,
дисковод, Nextor) остаются на 3,58 МГц, поэтому дисководы и мапперы работают как раньше. Игры, которые
рассчитаны на скорость Z80 на 3,58 МГц, идут быстрее, а кассете нужны 3,58 МГц (процедуры кассеты в
BIOS отмеряют сигнал процессором).

## Клавиатура

Клавиши PC-клавиатуры — клавиши MSX на своих местах (японские символы BIOS OCM — см. выше). Особые
клавиши MSX:

| MSX | PC |
|---|---|
| GRAPH | правый Alt |
| CODE | F10 |
| SELECT | F11 |
| STOP | Print Screen |
| мёртвая клавиша | F9 |
| HOME, INS, DEL, стрелки | те же клавиши |
| F1..F5 | F1..F5 |

## Сборка

Ядро собирается Xilinx ISE 14.7 под Linux: `cd src && make` (все три платы по очереди) или
`make go`, `make mini`, `make minig`; `make minig-report` показывает занятость ПЛИС и тайминг
последней сборки. Модули плат — подмодуль `modules/`
([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)): клонируйте с
`git clone --recursive` или выполните `git submodule update --init`. Для упаковки `.kg` нужен соседний
репозиторий [karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) (`make_core.py`).

Симуляции (verilator, для VHDL — ghdl) лежат в `src/sim`: система с C-BIOS (`sim/sys`, также с файлом
BIOS и с RTC / CMOS платы), регрессии мапперов картриджей, дисковода, кассеты, SD-интерфейса Nextor и
экранов VDP, а также буфер кадра. В `CLAUDE.md` — устройство и правила проекта, в `docs/PLAN.md` — план
и решения, в `docs/UPSTREAM.md` — что взято из исходных проектов и что изменено.

Прошивка платы — [karabas-go-firmware](https://github.com/andykarpov/karabas-go-firmware).

## Авторы и лицензия

- [MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer): molekula и участники MiSTer (машина,
  слоты и мапперы, дисковый интерфейс VY-0010 / WD1793, проигрыватель CAS).
- [OCM-PLD](https://github.com/gnogni/ocm-pld-dev): KdL и участники OCM; ESE-VDP — Kunihiko Ohnaka,
  модуль RTC — HRA!.
- T80: Daniel Wallner, MikeJ, Sorgelig и другие. jt49, jt8255 и jt2413 (jtopl): Jose Tejada.
- [MSX1FPGA](https://github.com/fbelavenuto/msx1fpga): Fabio Belavenuto (memory mapper, SD-интерфейс
  Nextor).
- [C-BIOS](http://cbios.sourceforge.net/): команда C-BIOS.
- Платы Karabas Go и порт: Andy Karpov.

Собственный код ядра — под GNU GPL v3 (`LICENSE`). Его части сохраняют свои лицензии: MSX1_MiSTer —
GPL v2 или новее, jt49 и jtopl — GPL v3, T80 — BSD-подобная, jt8255 — MIT, C-BIOS — BSD из двух пунктов
(`src/roms/LICENSE.cbios`; ROM C-BIOS встроены в файл ядра). Disk ROM VY-0010 (`src/rtl/msx/rom`) взят
из MSX1_MiSTer.

ESE-VDP (`src/rtl/msx/vdp`) и RTC (`src/rtl/msx/rtc.v`) из OCM-PLD — под BSD-подобной лицензией, которая
также запрещает продавать их или использовать в коммерческом продукте или деятельности без
письменного разрешения. Это условие несовместимо с GPL и распространяется на файл ядра, в котором они
есть: **ядро — только для некоммерческого использования.**

BIOS настоящих машин нет ни в этом репозитории, ни в файле ядра.

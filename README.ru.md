# Ядро MSX2 для Karabas Go / Mini / Mini G

[English version](README.md)

**В работе.** Ядро MSX2 / MSX2+: MSX1-ядро
[karabas-go-core-msx](https://github.com/andykarpov/karabas-go-core-msx) с ESE-VDP (V9938 / V9958)
из [OCM-PLD](https://github.com/gnogni/ocm-pld-dev) и буфером кадра в SDRAM. Файла ядра пока нет;
план — `docs/PLAN.md`. Текст ниже пока описывает MSX1-ядро, с которого начато это.

Компьютер MSX1 для плат семейства Karabas Go. Это порт
[MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer) (автор molekula) на Xilinx Spartan-6
XC6SLX25 плат Karabas. Вся работа с файлами (картриджи, образы дисков, кассеты, BIOS) идёт через OSD
и файловый браузер прошивки платы: своего загрузчика в ядре нет.

| Плата | Файл ядра | Видео | Звук |
|---|---|---|---|
| Karabas Go | `msx.kg` | VGA, 640x480 60 Гц | I2S ЦАП (PCM5102) |
| Karabas Mini | `msx.kg` | HDMI, 640x480 60 Гц | HDMI, аналоговый выход (sigma-delta) |
| Karabas Mini G | `msx.kg` | HDMI, 640x480 60 Гц | HDMI, I2S ЦАП (PCM5102) |

Файл ядра лежит в `src/` и в релизном репозитории
[karabas-go](https://github.com/andykarpov/karabas-go) (`cores/`, один файл для всех плат).

**Состояние:** сборка для Mini G проверена на железе (картриджи и игры; дисковод и кассета — тестовыми
картриджами, с настоящим BIOS MSX пока нет). Сборки для Mini и Go сделаны из тех же исходников и на
железе ещё не проверены.

## Что умеет

- **MSX1 из MSX1_MiSTer:** Z80 (T80), видеопроцессор TMS9918 (vdp18), звук AY-3-8910 (jt49), PPI,
  512 КБ RAM в слоте 3 с memory mapper MSX2 (порты FC–FF; пункт OSD RAM, 64K — обычные 64 КБ MSX1).
- **MSX-MUSIC:** OPLL (YM2413, [jt2413](https://github.com/jotego/jtopl)) в портах 7C–7D, как
  встроенный MSX-MUSIC поздних машин: без картриджа B в слоте 2 видна сигнатура его ROM (`APRLOPLL`),
  по ней игры его находят. Пункт OSD FM (MSX-MUSIC) его выключает.
- **BIOS:** в ядро встроен [C-BIOS](http://cbios.sourceforge.net/) 0.29a (европейская версия с
  логотипом). Он запускает картриджи, но в нём нет BASIC и процедур кассеты и дисковода. Для BASIC,
  дисков и кассет загрузите BIOS настоящего MSX1 пунктом OSD BIOS (32 КБ или 48 КБ с ROM страницы 2
  слота 0); он загружается заново при каждом старте ядра.
- **Два слота картриджей** (A в слоте 1, B в слоте 2), до 1 МБ каждый, маппер определяется по ROM:
  без маппера (16 / 32 / 48 КБ), Konami, Konami SCC (со звуком SCC), ASCII 8, ASCII 16, Game Master 2,
  линейный 64 КБ. Пункты Mapper A / Mapper B задают маппер вручную.
- **Дисковод:** интерфейс Philips VY-0010 (контроллер WD1793 и его Disk ROM) в слоте 1 вместо
  картриджа A, образы `.dsk` на 360 или 720 КБ. После монтирования образ в фоне копируется в SRAM
  платы, поэтому дисковод работает со скоростью настоящего; запись идёт в SRAM и сразу в файл образа.
- **Nextor на образе жёсткого диска:** интерфейс SD MSX1FPGA в слоте 1 (вместо картриджа A или
  дисковода) с его драйвером Nextor, на файле образа (`.img`, `.hdd`, `.vhd`, `.dsk`) на SD-карте
  платы: ядро отвечает как SD-карта, секторы идут из образа через прошивку. ROM Nextor — файл
  (`NEXTOR.ROM` из MSX1FPGA, `Support/SD/MSX1FPGA`), в ядро не встроен. Файлы `.dsk` со своего
  FAT-раздела Nextor монтирует сам.
- **Кассета:** файлы `.cas` (до 256 КБ) проигрываются на вход магнитофона MSX со скоростью 2400 бод,
  пока PPI включает мотор, как с настоящим магнитофоном (`RUN"CAS:"`, `BLOAD"CAS:",R`, `CLOAD`).
  Вместо файла входом может быть вывод TAPE_IN платы (настоящий магнитофон), на TAPE_OUT — выход
  записи (`CSAVE`).
- **Видео:** картинка 256x192 с бордюром в середине 640x480 60 Гц (через буфер кадра), развёртка
  VDP PAL (50 Гц) или NTSC (60 Гц) выбирается в OSD. HDMI со звуком на Mini и Mini G.
- **Управление:** USB-клавиатура как клавиатура MSX, два джойстика MSX: джойстики платы или
  USB-геймпады.

Пока нет (см. `docs/BACKLOG.md`): SCC MegaRAM, FM-PAC, сохранение памяти Game Master 2 и других
картриджей с батарейкой.

## Как начать

1. Скопируйте `msx.kg` (один файл для Go, Mini и Mini G) в корень SD-карты.
2. Положите файлы в папку `/msx` на SD-карте: картриджи (`.rom`, `.mx1`, `.mx2`, `.bin`), образы
   дисков (`.dsk`), кассеты (`.cas`), BIOS (`.rom`), `NEXTOR.ROM` и образы жёстких дисков.
3. Выберите MSX1 в меню ядер, откройте OSD (Menu+Esc) и загрузите картридж пунктом Cart A (Menu+F1).
   Машина запускает картридж сразу после загрузки.

Для дисков и кассет нужен настоящий BIOS MSX (пункт BIOS): C-BIOS зависает в INIT Disk ROM.
Диск: Machine > Slot 1 = Disk drive, затем `.dsk` в Disk A. Nextor: Machine > Slot 1 = Nextor, затем
образ в HDD (Nextor тоже нужен настоящий BIOS). Кассета: `.cas` в Tape, затем `RUN"CAS:"`
(программы на BASIC), `BLOAD"CAS:",R` (машинный код) или `CLOAD` + `RUN`; Tape rewind ставит файл
на начало.

## Меню OSD

На главной странице — носители, видео и сброс; настройки машины — на странице Machine (Enter / Right
открывают её, Esc возвращает). Страницы показывает прошивка v26103113 и новее; старая показывает
все пункты одним списком.

| Пункт | Значения | Клавиши |
|---|---|---|
| Cart A | картридж в слот 1 (виден при Slot 1 = Cartridge A) | Menu+F1 |
| Disk A | образ `.dsk` дисковода (виден при Slot 1 = Disk drive) | Menu+F3 |
| HDD | образ жёсткого диска для Nextor (виден при Slot 1 = Nextor) | Menu+F5 |
| Cart B | картридж в слот 2 | Menu+F2 |
| Tape | файл `.cas` (серый при Tape input = Tape in) | Menu+F4 |
| Tape rewind | кассета на начало (как Tape) | Menu+R |
| Video | PAL 50Hz / NTSC 60Hz | Menu+V |
| Joysticks | Normal / Swap | Menu+J |
| **Machine** ► | | |
| Reset | сброс MSX | F12 |
| Eject carts | вынуть оба картриджа (и сброс) | Menu+E |
| *Machine:* Slot 1 | Cartridge A / Disk drive / Nextor | Menu+D |
| Slot 1 ROM | On / Off (серый при Cartridge A) | |
| Mapper A | Auto / None / Game Master 2 / Konami / Konami SCC / ASCII 8 / ASCII 16 / Linear 64K (серый, когда в Slot 1 не Cartridge A) | |
| Mapper B | как Mapper A | |
| RAM | 512K mapper / 64K | |
| FM (MSX-MUSIC) | On / Off | |
| Tape input | CAS file / Tape in (TAPE_IN) | |
| BIOS | файл BIOS, загружается при каждом старте | |
| Nextor ROM | ROM Nextor (128 КБ), загружается при каждом старте (по умолчанию `NEXTOR.ROM`) | |

«Menu» — клавиша Windows на клавиатуре. Загрузка картриджа, BIOS или ROM Nextor, смена маппера,
Slot 1, RAM или FM сбрасывают машину; загрузка кассеты — нет. Slot 1 ROM = Off оставляет дисковод или
интерфейс SD без ROM (только регистры), для тестовых программ, которые сами управляют ими под C-BIOS.

## Клавиатура

Клавиши PC-клавиатуры — клавиши MSX на своих местах. Особые клавиши MSX:

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
`make go`, `make mini`, `make minig`; `make minig-report` показывает занятость и тайминг последней
сборки. Модули плат — подмодуль `modules/`
([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)): клонируйте с
`git clone --recursive` или выполните `git submodule update --init`. Для упаковки `.kg` нужен
соседний репозиторий [karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) рядом с этим
(`make_core.py`).

Симуляция (verilator, VHDL через ghdl; регрессии мапперов картриджей, дисковода и кассеты) — в
`src/sim`. В `CLAUDE.md` устройство и правила проекта, в `docs/PLAN.md` план и решения, в
`docs/UPSTREAM.md` — что взято из исходного проекта и что изменено.

Прошивка платы — [karabas-go-firmware](https://github.com/andykarpov/karabas-go-firmware).

## Авторы и лицензия

- [MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer): molekula и участники MiSTer (машина,
  слоты и мапперы, дисковый интерфейс VY-0010 / WD1793, проигрыватель CAS).
- T80: Daniel Wallner, MikeJ, Sorgelig и другие. vdp18: Arnim Laeuger. jt49, jt8255 и jt2413 (jtopl): Jose Tejada.
- [C-BIOS](http://cbios.sourceforge.net/): команда C-BIOS.
- Платы Karabas Go и порт: Andy Karpov.

Ядро распространяется под GNU GPL v3 (`LICENSE`). Его части сохраняют свои лицензии, совместимые с
ней: MSX1_MiSTer — GPL v2 или новее, jt49 и jtopl — GPL v3, T80 и vdp18 — лицензии в стиле BSD, jt8255 — MIT,
C-BIOS — BSD из двух пунктов (`src/roms/LICENSE.cbios`; ROM C-BIOS встроены в файлы ядра). Disk ROM
VY-0010 (`src/rtl/msx/rom`) взят из MSX1_MiSTer.

У ESE-VDP (`src/rtl/msx/vdp`, Kunihiko Ohnaka, из OCM-PLD от KdL) лицензия в стиле BSD с ещё одним
условием: без письменного разрешения его нельзя продавать и использовать в коммерческих продуктах и
деятельности. С GPL это условие несовместимо, и оно действует для файлов ядра, в которых есть VDP:
они только для некоммерческого использования.

# Tempest for Analogue Pocket

An openFPGA core for Atari's **Tempest** (1980), the colour vector arcade game,
for the Analogue Pocket (handheld and Dock).

> **Status: 0.1.0, playable.** Tested on an Analogue Pocket with the real
> game ROMs. Expect some rough edges; see [Known gaps](#known-gaps).

ROMs are **not** included.

## Install

1. Download `tempest-pocket.zip` from the latest GitHub Actions run (artifact
   `tempest-pocket`) or from Releases, and unzip it onto the root of the SD card.
2. Build `tempest.rom` from your own MAME romset:

   ```
   python3 make_tempest_rom.py tempest.zip tempest.rom
   ```

   The script is also in `Assets/tempest/common/` inside the package. It
   matches every part by CRC and accepts `tempest`, `tempest1r`, `tempest1`,
   `tempest2`, `tempest3` and `temptube` sets (zip or folder).
3. Copy `tempest.rom` to `/Assets/tempest/common/`.
4. Start it from openFPGA → Arcade → Tempest.

## Controls

| Pocket | Tempest |
|---|---|
| D-pad left / right | Spinner |
| A or X | Fire |
| B or Y | Superzapper |
| Select | Coin |
| Start | Start 1 player |
| L | Start 2 players |

On a Dock with an analog controller, turn on **Spin with Analog Stick** to
use the left stick as the spinner (speed follows stick deflection).

## Settings (Core Settings menu)

Spinner speed and direction, lives, bonus life, difficulty, rating, coinage
(including free play), minimum credits, language, horizontal / vertical flip,
service mode, and a reset action. Settings persist.

High scores are kept in the game's EAROM and saved to
`/Saves/tempest/...tempest.sav` a couple of seconds after the game writes them,
and when you open the Pocket menu.

## How it works

The game logic comes from the MiSTer "Tempest from Battlezone" core by Alan
Steremberg, itself built on a Battlezone FPGA student project and Arlet
Ottens' 6502. That core was a work in progress for Tempest, so the port adds
what Tempest needs, following MAME's `tempest.cpp`:

- **No embedded ROM.** The MiSTer source carries the program ROM inside a VHDL
  file; here the program and vector ROMs are block RAM loaded from
  `tempest.rom` at boot.
- **Interrupts.** Tempest uses a 250 Hz IRQ acknowledged by a write to `$5000`
  (the Battlezone core generated an NMI).
- **Colour.** Colour RAM at `$0800` and the Tempest AVG's colour/intensity
  `STAT` instruction.
- **Inputs.** The spinner, fire, superzapper, start buttons and some DIP
  switches are read through the two POKEYs' pot inputs, as on the board.
- **Frame buffer.** The Tempest AVG never halts; it jumps back to address 0
  forever. The core treats that jump as the end of a frame, swaps a
  double-buffered 512 × 512 frame buffer at the next vertical blank (no
  tearing) and clears the new back buffer.
- **EAROM** (ER2055) emulated for high scores, with save-file support.
- **POKEY** clocks retuned for Tempest's 1.512 MHz bus at the 49.5 MHz core
  clock.

Clocks: 49.5 MHz core, 18.5625 MHz pixel clock, 512 × 512 at 60.01 Hz,
displayed at 3:4 like MAME. Audio: both POKEYs mixed, 48 kHz I2S.

## Building

Every push to `main` builds the core in GitHub Actions (`.github/workflows/build.yml`):

1. `test`: Verilator lint and simulations (`sim/run_tests.sh`).
2. `compile`: Quartus 18.1 in the `raetro/quartus:pocket` container, a
   resource and timing report, then `tools/package.py` produces the SD-card
   folder and zip as the `tempest-pocket` artifact.

Pushing a tag like `v0.1.0` also publishes a release with the zip.

Local build with Docker:

```
docker run --rm -v "$PWD":/build -w /build/src/fpga raetro/quartus:pocket \
  quartus_sh --flow compile ap_core.qpf
python3 tools/package.py
```

To change the author name shown on the Pocket, rename
`dist/Cores/mcbeefy34.Tempest`, and update `author` in its `core.json` and
`CORE_ID` in `tools/package.py`.

## Tests

`sim/run_tests.sh` (Verilator 5.x) runs:

- a lint of the full Pocket top level;
- a cross-clock test of the bridge ROM loader (6,160 words, byte order, save slot);
- a machine simulation with a synthetic test ROM (no Atari code) that boots
  through the mirrored reset vector, takes IRQs, writes a coloured display
  list ending in `JMP 0`, reads the spinner, fire button and IN0 through the
  POKEYs, writes and reads the EAROM and plays a tone, then checks the
  pixels that come out of the video port.

## Known gaps

- Not yet verified with the real game; the mathbox and AVG are the MiSTer
  versions and have only been exercised there.
- Vector intensity is on/off (colour is kept); there is no glow or
  persistence effect.
- Cocktail mode / player 2 controls are not mapped (single Pocket player).
- If the picture is mirrored or upside down on hardware, use the Flip
  settings and please report which one was needed.

## Credits and licence

- Tempest from Battlezone (MiSTer): Alan Steremberg, jstavats
- Battlezone FPGA core: the student project the MiSTer core grew from (authors not named in its sources)
- 6502 core: Arlet Ottens
- openFPGA core template and APF: Analogue
- Hardware reference: the MAME project (`tempest.cpp`, `avgdvg.cpp`, `er2055.cpp`)
- Pocket port: mcbeefy34

GPL-2.0-or-later, as the MiSTer core. Tempest is a trademark of Atari.

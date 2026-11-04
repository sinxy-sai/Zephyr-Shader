# Minecraft Iris real-machine validation report

- generated: 2026-11-05 00:52:48
- verdict: **PASS** (phase `quit`)

## Configuration

| item | value |
|---|---|
| shaderpack | `Zephyr` |
| world (quickPlaySingleplayer) | `Weston City V0.3` |
| resolution | 1280x720 |
| game dir | `C:\Users\liubingliang\Downloads\PCL-2.12.2\.minecraft\versions\1.21.1-Fabric 0.18.4` |
| java pid | 49608 |
| window title | C:\Program Files\Java\jdk-22\bin\java.exe |

## Timeline

| milestone | seconds since launch |
|---|---|
| windowSeconds | 0.6 |
| shaderpackSeconds | 0.6 |
| pipelineSeconds | 0.6 |
| quitSeconds | 0 |
| totalSeconds | 91.2 |

## Shader verification

- `Using shaderpack: Zephyr` found: True
- Iris pipeline created: True
- joined world: True
- compile/load failure: False

## Chat commands sent

| command | confirmed in latest.log (`issued server command`) |
|---|---|
| `/time set 12500` | False |
| `/gamerule doDaylightCycle false` | False |
| `/weather rain` | False |

## Screenshots

- `C:\Users\liubingliang\Downloads\PCL-2.12.2\.minecraft\versions\1.21.1-Fabric 0.18.4\shaderpacks\Zephyr\shots\20261105-005117-Zephyr-Weston_City_V0.3-window-fallback1.png`

## Notes / issues

- chat commands not confirmed in latest.log: /time set 12500, /gamerule doDaylightCycle false, /weather rain
- F2 produced no file; used window capture fallback
- game quit: already-exited

## Evidence files

- `reports/iris-errors.txt` (extracted Iris lines)
- `reports/last-run.json` (machine readable metrics)
- `C:\Users\liubingliang\Downloads\PCL-2.12.2\.minecraft\versions\1.21.1-Fabric 0.18.4\shaderpacks\Zephyr\reports\run-20261105-005117\latest.log` (full game log of this run)


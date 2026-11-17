# Promo video: shot list (about 20 seconds)

Goal: show, in real Excel, a finance person doing three things with Windows Alt sequences, with the
AltForMac HUD visible. One take, no cuts needed. Silent (captions are added on the site).

## Before recording

1. Open `docs/promo/demo-sales.csv` in Excel and save it as a workbook. It is fake data, so nothing
   private appears on screen. Close every other workbook.
2. Excel > Preferences > Accessibility: Option-key KeyTips **off**. AltForMac running (menu bar shows `⌥`).
3. Turn on **Do Not Disturb**, hide the Dock, close other apps and menu-bar clutter.
4. Make the Excel window about 1280 x 720, with the **ribbon visible** (the HUD appears under it).
   Use the Home tab, zoom 100%, and click cell A1 so nothing is selected oddly.
5. Record with **Cmd+Shift+5 > Record Selected Portion**. Drag the box around the Excel window, and
   choose "Show Mouse Clicks" off. Press Record, wait 1 second, then start.

## Take (tap Option, release, then type the letters; do not hold Option)

| # | Do | Pause after | What the viewer sees |
|---|----|-------------|----------------------|
| 1 | Select columns A:G (click A, shift-click G) | 1 s | Narrow columns, long titles cut off, `####` in the number columns |
| 2 | Tap Option, then `H` `O` `I` | 2 s | HUD shows the keys, then every column snaps to the right width |
| 3 | Click any cell, tap Option, then `W` `V` `G` | 2 s | Gridlines vanish |
| 4 | Tap Option, then `W` `V` `G` again | 1 s | Gridlines come back |
| 5 | Click a cell inside the data, tap Option, then `N` `V` | 3 s | The Insert PivotTable dialog opens |
| 6 | Press Escape to close the dialog | 1 s | End |

Tips: type at a calm, steady pace (about one key per half second) so the HUD is readable. If a take goes
wrong, stop and redo it; short re-takes are cheaper than editing.

## After recording

For the current video, GIF and dropdown picture (zoomed clips, holds on each badge screen, intro and outro
cards), use `venv/bin/python scripts/make-promo-clips.py recording.mov` and edit the times at the top of it.
Cards: `swift scripts/make-cards.swift`. The older one-take script below still works for a plain recording.


```sh
scripts/setup-video-env.sh        # once: creates ./venv with ffmpeg (git-ignored)
scripts/make-promo.sh ~/Desktop/"Screen Recording ....mov"
```

It trims nothing by default and writes `site/promo.mp4`, `site/promo.webm` and `site/promo-poster.jpg`.
Add `--start 1.5 --end 22` to trim. For a still of the HUD (used as a picture on the site), note the
moment in step 2 when the HUD shows `⌥ H O` and its list, and add `--hud-at 4.2`, optionally with
`--hud-crop W:H:X:Y` to cut out just the HUD and a bit of ribbon around it. Then the site can embed the video (ask Claude to do that).

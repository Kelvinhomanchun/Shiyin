# KelNote colour palette (IBM Design Language)

Source: https://www.ibm.com/design/language/color/ — "Blue at the core", grays dominant, other families used sparingly and with purpose. Light theme uses grade 60, dark theme uses grade 40, so every text colour is ≥ 4.5:1 against its background (WCAG AA, checked).

| Role | Light | Dark | Used for |
|---|---|---|---|
| Primary (`Color.celadon`) | Blue 60 `#0F62FE` (5.0:1) | Blue 40 `#78A9FF` (7.1:1) | Links, buttons, selected tab, timestamps, accent colour, app icon, "me" ring, VU meter |
| Signal / caution | Orange 60 `#BA4E00` (5.0:1) | Orange 40 `#FF832B` (6.8:1) | Low confidence, to confirm, skeptic. IBM Yellow is only 3.3:1 on white, so it is not used for text |
| Positive | Green 60 `#198038` | Green 40 `#42BE65` | Champion / supporter, done |
| Negative | Red 60 `#DA1E28` | Red 40 `#FF8389` | Blocker, errors, destructive |
| Secondary accent | Purple 60 `#8A3FFC` | Purple 40 `#BE95FF` | "Keep satisfied" quadrant, medium level, "them" commitments |
| Highlight (background only) | Yellow 20 `#FDDC69` | Yellow 60 `#8E6A00` | Search matches |
| Text | Gray 100 `#161616` / Gray 60 `#6F6F6F` | system | Exports, mind map |

**Stakeholder semantics**
- Levels (High / Medium / Low) are *amount*, not good/bad: Blue 60 / Purple 60 / gray. They are never red or orange, which would read as warnings.
- Quadrants use one IBM 4-colour family: Blue (manage closely), Purple (keep satisfied), Teal 60 `#007D79` (keep informed), Gray (monitor).
- Attitude is the only good/bad scale: green / gray / orange / red. It is always paired with a text label (not colour alone, per IBM accessibility guidance).

**Speakers** (avatars, 8-step cycle): Cyan 60, Purple 60, Teal 60, Magenta 60, Green 60, Blue 80, Red 70, Gray 70 (dark: the 40/30 grades). Blue 60 is excluded because it is the link colour; red is late in the cycle so small meetings don't show it.

**Mind map branches** (IBM categorical order): Purple, Cyan, Teal, Magenta, Red, Blue 80; root is Blue 60.

**Settings icons**: IBM 60-grade family per page (Blue, Purple, Teal, Green, Red, Cyan 70, Blue 70, Yellow 60, Orange 40, Gray 60).

Avoided combinations (IBM): greens next to reds/magentas/purples only occur in the attitude scale, where meaning requires it and labels carry the meaning.

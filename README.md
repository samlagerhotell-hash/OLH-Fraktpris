# OLH Fraktpris

Internal Oslo Lagerhotell tool: parcel prices from our Profrakt agreements (Bring, PostNord), Norway only.
Shows full price (list + surcharges), our cost (agreement incl. fuel and toll) and our price (cost + 10 %),
plus which products aren't available for the parcel and why.

- **Install:** download the repo as ZIP (Code > Download ZIP), unpack, double-click `Install.cmd`. See `LES MEG.txt`.
- **Updates:** the installed app checks `version.txt` here on start and updates itself (hash- and parse-checked).
- **API key:** asked for at install and stored as the Windows user setting `PROFRAKT_API_KEY`. It is never in this repo.
- **Release:** edit `Fraktpris.ps1`, run `toolselease.ps1 <new version>`, commit and push to `main`.
- **Test without the API:** `Fraktpris.ps1 -SelfTest <saved costs reply.json>` (add `-Shot <png>` to render the window).

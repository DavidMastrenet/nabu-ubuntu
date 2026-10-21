# Nabu charging overlays

`qcom_smbx_nabu.c` starts from upstream `qcom_smbx.c` blob
`67fdb433533883268ef18c10c3ec7081452f3cf1`, with Robin Snyders' five
[SMBx fixes](https://lore-kernel.gnuweeb.org/linux-pm/20260812-qcom-smbx-fixes-v1-0-eb48246be599@snyders.xyz/)
and [SMB5 v4 patch](https://lore-kernel.gnuweeb.org/linux-pm/20260820-submit-qcom-smbx-send-v1-v4-2-818dabb2771e@snyders.xyz/).
Original authors and licenses remain in the source.

Linux 6.17 lacks the power-supply registration initialization callback used
by that series. The backport gates public callbacks with acquire/release
ordering until the battery limits are programmed. A board-specific driver
name and compatible prevent a conflict with the BSP's built-in SMB driver.
The board battery node requests 4.35 V float and 1 A battery current; all
USB input types are capped at 500 mA. Hardware AICL remains enabled.

`ln8000_charger_nabu.c` is adapted from the
[sm8150 6.14.11 driver](https://gitlab.com/sm8150-mainline/linux/-/blob/5181e1358ddd6ea8028e841d928942373e6aebc8/drivers/power/supply/ln8000_charger.c).
It uses the 6.17 firmware-node APIs, samples an already-connected Type-C
supply at probe, and enables its 2:1 charge-pump path only from 8 V upward.
Removal unregisters the notifier, cancels work and releases managed IRQs
without freeing managed allocations twice. Status uses the power-supply
status enum rather than a boolean.

`nabu-charge-guard` suspends the SMB5 input above 5.5 V to hand PD charging
to LN8000. It also suspends SMB5 when temperature or battery voltage is
outside the configured guard, health is not Good, or telemetry is missing.

On the target tablet, 37 samples over 180 seconds showed Charging in every
sample, input current 480425–482695 microamps, temperature 29 C and charger
health Good. Battery current was negative throughout and capacity rose
from 82% to 83% after the kernel update. PD hardware testing was skipped
at the owner's request for this revision.

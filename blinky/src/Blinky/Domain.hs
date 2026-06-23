{-# LANGUAGE NumericUnderscores #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{- |
Terasic Cyclone V GX Starter Kit (C5G) clock domain.

Mirrors @Orangecrab.Domain@ from the upstream clash-starters @orangecrab@
project, swapping the 48 MHz OrangeCrab oscillator for the C5G's 50 MHz one
(@CLOCK_50_B5B@, pin R20). The period is only consumed by the simulator and by
Clash's generated @topEntity.sdc@; for synthesis the real clock constraint comes
straight from that SDC, which Quartus reads.

The default 'vSystem' reset (asynchronous, active-high) is kept as-is: the
top entity ties it permanently de-asserted, so it never reaches hardware.
-}
module Blinky.Domain where

import Clash.Prelude

-- | 50 MHz oscillator clock of the C5G board (CLOCK_50_B5B, pin R20).
createDomain
        vSystem
                { vName = "Dom50"
                , vPeriod = hzToPeriod 50_000_000
                }

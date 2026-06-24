{-# LANGUAGE NumericUnderscores #-}
{-# OPTIONS_GHC -Wno-orphans #-}

{- |
Terasic Cyclone V GX Starter Kit (C5G) clock domain for the pwm-pattern example.

Identical to the @pwm@ example's domain. The default 'vSystem' reset
(asynchronous, active-high) is kept as-is: the top entities tie it permanently
de-asserted, so it never reaches hardware.
-}
module PwmPattern.Domain where

import Clash.Prelude

-- | 50 MHz oscillator clock of the C5G board (CLOCK_50_B5B, pin R20).
createDomain
        vSystem
                { vName = "Dom50"
                , vPeriod = hzToPeriod 50_000_000
                }

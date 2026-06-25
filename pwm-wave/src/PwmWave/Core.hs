{- |
The __vectorized__ PWM core: one carrier, N independent comparators.

Where @pwm-pattern@'s @PwmCore.pwm@ dimmed a single LED, 'pwmVec' drives a whole
'Vec' of them from __one__ free-running carrier counter — the lanes share the
carrier (and so the ~763 Hz period and its boundary) but each compares it against
its own duty. That sharing is the point: the wave decode hands this core a
@Vec n@ of per-LED duties and gets back a @Vec n@ of LED bits, with a single
@w@-bit counter behind all of them rather than @n@ copies of the scalar core.

'pwmVec' keeps the sequential parts (the carrier, the end-of-period tick, and the
duty shadow register); 'pwm' is the small combinational per-lane comparator it
broadcasts across the vector. Mind the name: in the sibling examples @pwm@ is the
/whole/ core, but here it is just @counter < duty@ — 'pwmVec' owns the state.
-}
module PwmWave.Core where

import Clash.Prelude

{- | Vectorized PWM: compare one free-running carrier against a 'Vec' of per-lane
duties, returning a 'Vec' of LED bits plus the shared end-of-period tick.

Three ideas carried over from @PwmCore.pwm@, now vectorized:

  * __One carrier, broadcast.__ A single @counter@ (width @w@, so a
    @50e6 / 2^16 ≈ 763 Hz@ carrier at @w = 16@) is compared against every lane.
    The carrier must run at full clock speed so the eye sees a steady brightness;
    only the /animation/ is slowed downstream, by prescaling 'endOfPeriod'.

  * __Whole-'Vec' shadow register.__ @shadowDuties@ latches the entire duty
    vector at the period boundary ('regEn' gated by 'endOfPeriod'), so a
    mid-period change to any lane is deferred to the next boundary — every lane
    switches together and no period shows a partial (blended) pulse.

  * __The end-of-period tick is returned.__ It is the one ~763 Hz time base the
    wave's position machine prescales to step the bump; exposing it here keeps a
    single counter feeding both the LEDs and the animation clock, rather than a
    second counter built just to make a tick.

Keeping @dutiesIn@ a 'Signal' of a 'Vec' (rather than a fixed parameter) is what
lets the spatial decode drive the brightness without touching this definition.
-}
pwmVec ::
        forall dom n w.
        (HiddenClockResetEnable dom, KnownNat n, KnownNat w, 1 <= w) =>
        -- | Per-lane duty cycles (each out of @2^w@)
        Signal dom (Vec n (Unsigned w)) ->
        -- | (LED per lane — high while the carrier is below that lane's duty;
        --    end-of-period — a one-cycle pulse as the carrier wraps)
        (Signal dom (Vec n Bit), Signal dom Bool)
pwmVec dutiesIn = (leds, endOfPeriod)
    where
        counter :: Signal dom (Unsigned w)
        counter = register 0 (counter + 1)
        endOfPeriod :: Signal dom Bool
        endOfPeriod = counter .==. maxBound
        shadowDuties :: Signal dom (Vec n (Unsigned w))
        shadowDuties = regEn (repeat 0) endOfPeriod dutiesIn
        -- Broadcast the one carrier across every lane: fix the carrier sample
        -- @c@, then 'map' the comparator over the shadow-duty vector.
        leds :: Signal dom (Vec n Bit)
        leds = (\c -> map (pwm c)) <$> counter <*> shadowDuties

{- | One lane's comparator: high while the carrier is below this lane's duty. The
combinational heart of 'pwmVec' (which supplies the carrier and the duty),
factored out so the broadcast in @leds@ reads as @map (pwm c)@. Unlike the @pwm@
of the sibling examples this carries /no/ state — 'pwmVec' owns the counter,
shadow, and tick.
-}
pwm :: Unsigned w -> Unsigned w -> Bit
pwm counter duty = boolToBit (counter < duty)

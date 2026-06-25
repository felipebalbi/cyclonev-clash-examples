{- |
The simplest pattern generator: a __constant__ duty.

Reproduces the @pwm@ example's fixed-brightness behaviour, now expressed through
the 'PatGen' framework — which makes it the natural sanity anchor for the whole
example: @runMoore (initial :: Constant)@ should behave exactly like the old
constant-duty @pwm@. It is also the floor case for the two spellings: the state
never changes, so 'next' is the identity and 'step' ignores the advance tick.

The duty is carried as a field so a top can /choose/ the level by constructing
@Constant n@ and passing it to a driver; 'initial' supplies a 75% default.
-}
module PwmPattern.Pattern.Constant where

import Clash.Prelude
import Control.Monad.State.Strict (gets)
import PwmPattern.Pattern (DutyW, PatGen (..), PatGenMealy (..), PatGenMoore (..))

{- | A constant-duty generator. The field is the brightness it holds forever;
keeping it in the state (rather than hard-coding) is what lets a top pick the
level via @Constant n@ instead of the 'initial' default.
-}
data Constant = Constant (Unsigned DutyW)
        deriving (Generic, NFDataX, Eq, Show)

{- | The default level: @(maxBound \`div\` 4) * 3@ — three-quarters of full scale,
identical to the @pwm@ example's fixed duty.
-}
constDuty :: Unsigned DutyW
constDuty = (maxBound `div` 4) * 3

instance PatGen Constant where
        initial = Constant constDuty

instance PatGenMoore Constant where
        -- A constant has nowhere to go, so the transition is the identity and the
        -- decoder just reads the held level.
        next = id
        duty (Constant d) = d

instance PatGenMealy Constant where
        -- The Mealy spelling: ignore the advance tick and leave the state untouched
        -- ('gets' reads without 'put'ting), yielding the held level. Contrast with
        -- Triangle's 'step', which evolves its state on a tick.
        step _ = gets (\(Constant d) -> d)

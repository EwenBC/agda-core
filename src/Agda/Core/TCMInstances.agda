open import Haskell.Prelude

open import Agda.Core.GlobalScope       using (Globals)
open import Agda.Core.Syntax.Signature  using (Signature)
open import Agda.Core.TCM

module Agda.Core.TCMInstances
    {{@0 globals : Globals}}
    {{@0 sig : Signature}}
  where

private
  fmapTCM : (a → b) → TCM a → TCM b
  fmapTCM f = MkTCM ∘ fmap (fmap f) ∘ runTCM
  {-# COMPILE AGDA2HS fmapTCM #-}

  liftA2TCM : (a → b → c) → TCM a → TCM b → TCM c
  liftA2TCM g ta tb = MkTCM λ e → g <$> runTCM ta e <*> runTCM tb e
  {-# COMPILE AGDA2HS liftA2TCM #-}

  pureTCM : a → TCM a
  pureTCM = MkTCM ∘ const ∘ Right
  {-# COMPILE AGDA2HS pureTCM #-}

  bindTCM : TCM a → (a → TCM b) → TCM b
  bindTCM ma mf = MkTCM λ f → do v ← runTCM ma f ; runTCM (mf v) f
  {-# COMPILE AGDA2HS bindTCM #-}

instance
  iFunctorTCM : Functor TCM
  iFunctorTCM .fmap  = fmapTCM
  iFunctorTCM ._<$_  = λ x m → fmapTCM (λ b → x {{b}}) m
  {-# COMPILE AGDA2HS iFunctorTCM #-}

instance
  iApplicativeTCM : Applicative TCM
  iApplicativeTCM .pure  = pureTCM
  iApplicativeTCM ._<*>_ = liftA2TCM id
  iApplicativeTCM ._<*_  = liftA2TCM (λ z _ → z)
  iApplicativeTCM ._*>_  = liftA2TCM (λ _ z → z)
  {-# COMPILE AGDA2HS iApplicativeTCM #-}

instance
  iMonadTCM : Monad TCM
  iMonadTCM ._>>=_  = bindTCM
  iMonadTCM .return = pureTCM
  iMonadTCM ._>>_   = λ x y → bindTCM x (λ z → y {{z}})
  {-# COMPILE AGDA2HS iMonadTCM #-}

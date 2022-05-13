{-# LANGUAGE RoleAnnotations #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Plutarch.Api.V1.Value (
  PValue (PValue),
  PCurrencySymbol (PCurrencySymbol),
  PTokenName (PTokenName),
  KeyGuarantees (Unsorted, Sorted),
  AmountGuarantees (NoGuarantees, NonZero, Positive),
  passertSorted,
  passertPositive,
  pforgetPositive,
  pforgetSorted,
  pnormalize,
  psingleton,
  psingletonData,
  pconstantSingleton,
  pconstantPositiveSingleton,
  punionWith,
  punionWithData,
  pvalueOf,
) where

import qualified Plutus.V1.Ledger.Api as Plutus

import Plutarch.Api.V1.AssocMap (KeyGuarantees (Sorted, Unsorted), PMap)
import qualified Plutarch.Api.V1.AssocMap as AssocMap
import Plutarch.Lift (
  DerivePConstantViaBuiltin (DerivePConstantViaBuiltin),
  DerivePConstantViaNewtype (DerivePConstantViaNewtype),
  PConstantDecl,
  PLifted,
  PUnsafeLiftDecl,
 )
import Plutarch.Unsafe (punsafeCoerce, punsafeDowncast)
import qualified PlutusTx.Monoid as PlutusTx
import qualified PlutusTx.Semigroup as PlutusTx

import Plutarch.Prelude hiding (psingleton)

newtype PTokenName (s :: S) = PTokenName (Term s PByteString)
  deriving (PlutusType, PIsData, PEq, POrd) via (DerivePNewtype PTokenName PByteString)

instance PUnsafeLiftDecl PTokenName where type PLifted PTokenName = Plutus.TokenName
deriving via
  (DerivePConstantViaBuiltin Plutus.TokenName PTokenName PByteString)
  instance
    PConstantDecl Plutus.TokenName

newtype PCurrencySymbol (s :: S) = PCurrencySymbol (Term s PByteString)
  deriving (PlutusType, PIsData, PEq, POrd) via (DerivePNewtype PCurrencySymbol PByteString)

instance PUnsafeLiftDecl PCurrencySymbol where type PLifted PCurrencySymbol = Plutus.CurrencySymbol
deriving via
  (DerivePConstantViaBuiltin Plutus.CurrencySymbol PCurrencySymbol PByteString)
  instance
    PConstantDecl Plutus.CurrencySymbol

data AmountGuarantees = NoGuarantees | NonZero | Positive

newtype PValue (keys :: KeyGuarantees) (amounts :: AmountGuarantees) (s :: S)
  = PValue (Term s (PMap keys PCurrencySymbol (PMap keys PTokenName PInteger)))
  deriving
    (PlutusType, PIsData)
    via (DerivePNewtype (PValue keys amounts) (PMap keys PCurrencySymbol (PMap keys PTokenName PInteger)))
type role PValue nominal nominal nominal

instance PUnsafeLiftDecl (PValue 'Unsorted 'NonZero) where
  type PLifted (PValue 'Unsorted 'NonZero) = Plutus.Value
deriving via
  ( DerivePConstantViaNewtype
      Plutus.Value
      (PValue 'Unsorted 'NonZero)
      (PMap 'Unsorted PCurrencySymbol (PMap 'Unsorted PTokenName PInteger))
  )
  instance
    PConstantDecl Plutus.Value

instance PEq (PValue 'Sorted 'Positive) where
  a #== b = pto a #== pto b

instance PEq (PValue 'Sorted 'NonZero) where
  a #== b = pto a #== pto b

instance PEq (PValue 'Sorted 'NoGuarantees) where
  a #== b = AssocMap.pall # (AssocMap.pall # plam (#== 0)) # pto (punionWith # plam (-) # a # b)

instance Semigroup (Term s (PValue 'Sorted 'Positive)) where
  a <> b = punsafeDowncast (pto $ punionWith # plam (+) # a # b)

instance PlutusTx.Semigroup (Term s (PValue 'Sorted 'Positive)) where
  a <> b = punsafeDowncast (pto $ punionWith # plam (+) # a # b)

instance Semigroup (Term s (PValue 'Sorted 'NonZero)) where
  a <> b = pnormalize #$ punionWith # plam (+) # a # b

instance PlutusTx.Semigroup (Term s (PValue 'Sorted 'NonZero)) where
  a <> b = pnormalize #$ punionWith # plam (+) # a # b

instance Semigroup (Term s (PValue 'Sorted 'NoGuarantees)) where
  a <> b = punionWith # plam (+) # a # b

instance PlutusTx.Semigroup (Term s (PValue 'Sorted 'NoGuarantees)) where
  a <> b = punionWith # plam (+) # a # b

instance
  Semigroup (Term s (PValue 'Sorted normalization)) =>
  Monoid (Term s (PValue 'Sorted normalization))
  where
  mempty = pcon (PValue AssocMap.pempty)

instance
  PlutusTx.Semigroup (Term s (PValue 'Sorted normalization)) =>
  PlutusTx.Monoid (Term s (PValue 'Sorted normalization))
  where
  mempty = pcon (PValue AssocMap.pempty)

instance
  PlutusTx.Semigroup (Term s (PValue 'Sorted 'NoGuarantees)) =>
  PlutusTx.Group (Term s (PValue 'Sorted 'NoGuarantees))
  where
  inv a = pmapAmounts # plam negate # a

instance
  PlutusTx.Semigroup (Term s (PValue 'Sorted 'NonZero)) =>
  PlutusTx.Group (Term s (PValue 'Sorted 'NonZero))
  where
  inv a = punsafeCoerce $ PlutusTx.inv (punsafeCoerce a :: Term s (PValue 'Sorted 'NoGuarantees))

-- | Construct a constant singleton 'PValue' containing only the given quantity of the given currency.
pconstantSingleton ::
  ClosedTerm PCurrencySymbol ->
  ClosedTerm PTokenName ->
  ClosedTerm PInteger ->
  ClosedTerm (PValue 'Sorted 'NonZero)
pconstantSingleton symbol token amount
  | plift amount == 0 = mempty
  | otherwise = punsafeDowncast (AssocMap.psingleton # symbol #$ AssocMap.psingleton # token # amount)

-- | Construct a constant singleton 'PValue' containing only the given positive quantity of the given currency.
pconstantPositiveSingleton ::
  ClosedTerm PCurrencySymbol ->
  ClosedTerm PTokenName ->
  ClosedTerm PInteger ->
  ClosedTerm (PValue 'Sorted 'Positive)
pconstantPositiveSingleton symbol token amount
  | plift amount == 0 = mempty
  | plift amount < 0 = error "Negative amount"
  | otherwise = punsafeDowncast (AssocMap.psingleton # symbol #$ AssocMap.psingleton # token # amount)

-- | Construct a singleton 'PValue' containing only the given quantity of the given currency.
psingleton ::
  Term
    s
    (PCurrencySymbol :--> PTokenName :--> PInteger :--> PValue 'Sorted 'NonZero)
psingleton = phoistAcyclic $
  plam $ \symbol token amount ->
    pif
      (amount #== 0)
      mempty
      (punsafeDowncast $ AssocMap.psingleton # symbol #$ AssocMap.psingleton # token # amount)

{- | Construct a singleton 'PValue' containing only the given quantity of the
 given currency, taking data-encoded parameters.
-}
psingletonData ::
  Term
    s
    ( PAsData PCurrencySymbol :--> PAsData PTokenName :--> PAsData PInteger
        :--> PValue 'Sorted 'NonZero
    )
psingletonData = phoistAcyclic $
  plam $ \symbol token amount ->
    pif
      (amount #== zeroData)
      mempty
      ( punsafeDowncast
          ( AssocMap.psingletonData # symbol
              #$ pdata
              $ AssocMap.psingletonData # token # amount
          )
      )

-- | Get the quantity of the given currency in the 'PValue'.
pvalueOf :: Term s (PValue _ _ :--> PCurrencySymbol :--> PTokenName :--> PInteger)
pvalueOf = phoistAcyclic $
  plam $ \value symbol token ->
    AssocMap.pfoldAt
      # symbol
      # 0
      # plam (\map -> AssocMap.pfoldAt # token # 0 # plam pfromData # pfromData map)
      # pto value

{- | Combine two 'PValue's applying the given function to any pair of
 quantities with the same asset class. Note that the result is _not_
 'normalize'd and may contain zero quantities.
-}
punionWith ::
  Term
    s
    ( (PInteger :--> PInteger :--> PInteger) :--> PValue 'Sorted _ :--> PValue 'Sorted _
        :--> PValue 'Sorted 'NoGuarantees
    )
punionWith = phoistAcyclic $
  plam $ \combine x y ->
    pcon . PValue $
      AssocMap.punionWith
        # (plam $ \x y -> AssocMap.punionWith # combine # x # y)
        # pto x
        # pto y

{- | Combine two 'PValue's applying the given function to any pair of
 data-encoded quantities with the same asset class. Note that the result is
 _not_ 'normalize'd and may contain zero quantities.
-}
punionWithData ::
  Term
    s
    ( (PAsData PInteger :--> PAsData PInteger :--> PAsData PInteger)
        :--> PValue 'Sorted _
        :--> PValue 'Sorted _
        :--> PValue 'Sorted 'NoGuarantees
    )
punionWithData = phoistAcyclic $
  plam $ \combine x y ->
    pcon . PValue $
      AssocMap.punionWith
        # (plam $ \x y -> AssocMap.punionWithData # combine # x # y)
        # pto x
        # pto y

-- | Normalize the argument to contain no zero quantity nor empty token map.
pnormalize :: Term s (PValue 'Sorted _ :--> PValue 'Sorted 'NonZero)
pnormalize = phoistAcyclic $
  plam $ \value ->
    pcon . PValue $
      AssocMap.pmapMaybe # plam normalizeTokenMap # pto value
  where
    normalizeTokenMap tokenMap =
      plet (AssocMap.pmapMaybeData # plam nonZero # tokenMap) $ \normalMap ->
        pif
          (AssocMap.pnull # normalMap)
          (pcon PNothing)
          (pcon $ PJust normalMap)
    nonZero intData =
      pif (intData #== zeroData) (pcon PNothing) (pcon $ PJust intData)

-- | Assert the value is properly sorted and normalized.
passertSorted :: Term s (PValue _ _ :--> PValue 'Sorted 'NonZero)
passertSorted = phoistAcyclic $
  plam $ \value ->
    pif
      ( AssocMap.pany
          # ( plam $
                \submap ->
                  AssocMap.pnull # (AssocMap.passertSorted # submap)
                    #|| AssocMap.pany # plam (#== 0) # submap
            )
          # pto value
      )
      (ptraceError "Abnormal Value")
      (pcon $ PValue $ AssocMap.passertSorted # pto value)

-- | Assert all amounts in the value are positive.
passertPositive :: Term s (PValue 'Sorted 'NonZero :--> PValue 'Sorted 'Positive)
passertPositive = phoistAcyclic $
  plam $ \value ->
    pif
      ( AssocMap.pall
          # (plam $ \submap -> AssocMap.pall # plam (0 #<) # submap)
          # pto value
      )
      (punsafeDowncast $ pto value)
      (ptraceError "Negative amount in Value")

-- | Forget the knowledge of value's positivity.
pforgetPositive :: Term s (PValue 'Sorted 'Positive) -> Term s (PValue k a)
pforgetPositive = punsafeCoerce

-- | Forget the knowledge of all value's guarantees.
pforgetSorted :: Term s (PValue 'Sorted a) -> Term s (PValue k b)
pforgetSorted = punsafeCoerce

zeroData :: ClosedTerm (PAsData PInteger)
zeroData = pdata 0

-- | Applies a function to every amount in the map.
pmapAmounts :: Term s ((PInteger :--> PInteger) :--> PValue k a :--> PValue k 'NoGuarantees)
pmapAmounts = phoistAcyclic $
  plam $ \f v -> pcon $ PValue $ AssocMap.pmap # plam (AssocMap.pmap # f #) # pto v

{-# LANGUAGE UndecidableInstances #-}

module Plutarch.FFI (
  foreignExport,
  foreignImport,
) where

import Data.Kind (Constraint, Type)
import Data.Text (Text)
import GHC.TypeLits (TypeError)
import qualified GHC.TypeLits as TypeLits
import qualified Generics.SOP as SOP
import Plutarch.Bool (PBool)
import Plutarch.Integer (PInteger)
import Plutarch.Internal (
  ClosedTerm,
  PType,
  RawTerm (RCompiled),
  Term (Term),
  TermResult (TermResult),
  asClosedRawTerm,
  compile',
  (:-->),
 )
import Plutarch.Internal.PlutusType (PlutusType (PInner))
import Plutarch.String (PString)
import Plutus.V1.Ledger.Scripts (Script (unScript), fromCompiledCode)
import PlutusTx.Code (CompiledCode, CompiledCodeIn (DeserializedCode))
import PlutusTx.Prelude (BuiltinString)
import UntypedPlutusCore (fakeNameDeBruijn)
import qualified UntypedPlutusCore as UPLC

data ForallPhantom :: Type
data PhorallPhantom :: PType

foreignExport :: PlutarchInner p PhorallPhantom ~~ PlutusTxInner t ForallPhantom => ClosedTerm p -> CompiledCode t
foreignExport t = DeserializedCode program Nothing mempty
  where
    program =
      UPLC.Program () (UPLC.Version () 1 0 0) $
        UPLC.termMapNames fakeNameDeBruijn $
          compile' $
            asClosedRawTerm t

foreignImport :: PlutarchInner p PhorallPhantom ~~ PlutusTxInner t ForallPhantom => CompiledCode t -> ClosedTerm p
foreignImport c = Term $ const $ TermResult (RCompiled $ UPLC.toTerm $ unScript $ fromCompiledCode c) []

type family a ~~ b :: Constraint where
  ForallPhantom ~~ _ = ()
  _ ~~ ForallPhantom = ()
  a ~~ b = a ~ b

type family PlutarchInner (p :: PType) (any :: PType) :: Type where
  PlutarchInner PBool _ = Bool
  PlutarchInner PInteger _ = Integer
  PlutarchInner PString _ = Text
  PlutarchInner PhorallPhantom _ = ForallPhantom
  PlutarchInner (a :--> b) x = PlutarchInner a b -> PlutarchInner b x
  PlutarchInner p x = PlutarchInner (PInner p x) x

type family PlutusTxInner (t :: Type) (any :: Type) :: Type where
  PlutusTxInner Bool _ = Bool
  PlutusTxInner Integer _ = Integer
  PlutusTxInner BuiltinString _ = Text
  PlutusTxInner ForallPhantom _ = ForallPhantom
  PlutusTxInner (a -> b) x = PlutusTxInner a b -> PlutusTxInner b x
  PlutusTxInner a x = PlutusTxInner (ScottFn (ScottList (SOP.Code a) x) x) x

{- |
  List of scott-encoded constructors of a Haskell type (represented by 'SOP.Code')

  ScottList (Code (Either a b)) c = '[a -> c, b -> c]
-}
type ScottList :: [[Type]] -> Type -> [Type]
type family ScottList code c where
-- We disallow certain shapes because Scott encoding is not appropriate for them.
  ScottList '[] c = TypeError ( 'TypeLits.Text "PlutusType(scott encoding): Data type without constructors not accepted")
  ScottList '[ '[]] c =
    TypeError
      ( 'TypeLits.Text
          "PlutusType(scott encoding): Data type with single nullary constructor not accepted"
      )
  ScottList '[ '[_]] c =
    TypeError
      ( 'TypeLits.Text
          "PlutusType(scott encoding): Data type with single unary constructor not accepted; use newtype!"
      )
  ScottList (xs ': xss) c = ScottFn xs c ': ScottList' xss c

type ScottList' :: [[Type]] -> Type -> [Type]
type family ScottList' code c where
  ScottList' '[] c = '[]
  ScottList' (xs ': xss) c = ScottFn xs c ': ScottList' xss c

{- |
  An individual constructor function of a Scott encoding.

   ScottFn '[a, b] c = (a -> b -> c)
   ScottFn '[] c = c
-}
type ScottFn :: [Type] -> Type -> Type
type family ScottFn xs b where
  ScottFn '[] b = b
  ScottFn (x ': xs) b = x -> ScottFn xs b

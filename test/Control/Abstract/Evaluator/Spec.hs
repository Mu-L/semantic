{-# LANGUAGE TypeOperators #-}
module Control.Abstract.Evaluator.Spec
( spec
) where

import           Control.Abstract
import qualified Control.Abstract.Heap as Heap
import           Data.Abstract.Address.Precise as Precise
import           Data.Abstract.BaseError
import           Data.Abstract.Evaluatable
import           Data.Abstract.FreeVariables
import           Data.Abstract.Module
import qualified Data.Abstract.Number as Number
import           Data.Abstract.Package
import           Data.Abstract.Ref
import qualified Data.Abstract.ScopeGraph as ScopeGraph
import           Data.Abstract.Value.Concrete as Value
import           Data.Algebra
import           Data.Bifunctor (first)
import           Data.Functor.Const
import qualified Data.Map.Strict as Map
import           Data.Sum
import           Data.Text (pack)
import           SpecHelpers hiding (reassociate)
import           System.IO.Unsafe (unsafePerformIO)

spec :: Spec
spec = parallel $ do
  it "constructs integers" $ do
    (_, (_, (_, expected))) <- evaluate (rvalBox (integer 123))
    expected `shouldBe` Right (Rval (Value.Integer (Number.Integer 123)))

  it "calls functions" $ do
    (_, (_, (_, expected))) <- evaluate $
      rvalBox <=< value <=< withLexicalScopeAndFrame $ do
        currentScope' <- currentScope
        let lexicalEdges = Map.singleton Lexical [ currentScope' ]
            x =  SpecHelpers.name "x"
        associatedScope <- newScope lexicalEdges
        declare (ScopeGraph.Declaration "identity") emptySpan (Just associatedScope)
        withScope associatedScope $ do
          declare (Declaration x) emptySpan Nothing
        valueRef <- function "identity" [ x ]
          (SpecEff (LvalMember <$> Heap.lookupDeclaration (ScopeGraph.Declaration (SpecHelpers.name "x")))) associatedScope
        identity <- value valueRef
        val <- pure (integer 123)
        call identity [val]
    expected `shouldBe` Right (Rval $ integer 123)

evaluate
  = runM
  . runTraceByIgnoring
  . runState (lowerBound @(ScopeGraph Precise))
  . runState (lowerBound @(Heap Precise Precise Val))
  . runFresh
  . runReader (PackageInfo (SpecHelpers.name "test") mempty)
  . runReader (ModuleInfo "test/Control/Abstract/Evaluator/Spec.hs")
  . evalState (lowerBound @Span)
  . runReader (lowerBound @Span)
  . runEvaluator
  . runAllocator
  . evalModule
  where
    evalModule action = do
      scopeAddress <- newScope mempty
      frameAddress <- newFrame scopeAddress mempty
      val <- raiseHandler (runReader (scopeAddress, frameAddress))
        . fmap reassociate
        . runScopeError
        . runHeapError
        . runValueError
        . runAddressError
        . runEvalError
        . runDeref @Val
        . runAllocator
        . runReturn
        . runLoopControl
        . runBoolean
        . runFunction runSpecEff
        $ action
      pure ((scopeAddress, frameAddress), val)

reassociate :: Either (SomeError exc1) (Either (SomeError exc2) (Either (SomeError exc3) (Either (SomeError exc4) (Either (SomeError exc5) result)))) -> Either (SomeError (Sum '[exc5, exc4, exc3, exc2, exc1])) result
reassociate = mergeErrors . mergeErrors . mergeErrors . mergeErrors . mergeErrors . Right

type Val = Value SpecEff Precise
newtype SpecEff = SpecEff
  { runSpecEff :: Evaluator SpecEff Precise Val (FunctionC SpecEff Precise Val
                 (Eff (BooleanC Val
                 (Eff (ErrorC (LoopControl Precise Val)
                 (Eff (ErrorC (Return Precise Val)
                 (Eff (AllocatorC Precise
                 (Eff (DerefC Precise Val
                 (Eff (ResumableC (BaseError (EvalError Precise Val))
                 (Eff (ResumableC (BaseError (AddressError Precise Val))
                 (Eff (ResumableC (BaseError (ValueError SpecEff Precise))
                 (Eff (ResumableC (BaseError (HeapError Precise))
                 (Eff (ResumableC (BaseError (ScopeError Precise))
                 (Eff (ReaderC (Precise, Precise)
                 (Eff (AllocatorC Precise
                 (Eff (ReaderC Span
                 (Eff (StateC Span
                 (Eff (ReaderC ModuleInfo
                 (Eff (ReaderC PackageInfo
                 (Eff (FreshC
                 (Eff (StateC (Heap Precise Precise Val)
                 (Eff (StateC (ScopeGraph Precise)
                 (Eff (TraceByIgnoringC
                 (Eff (LiftC IO)))))))))))))))))))))))))))))))))))))))))))
                 (ValueRef Precise Val)
  }

instance Eq SpecEff where _ == _ = True
instance Show SpecEff where show _ = "_"
instance FreeVariables SpecEff where freeVariables _ = lowerBound

instance Declarations SpecEff where
  declaredName eff =
    case unsafePerformIO (evaluate $ runSpecEff eff) of
      (_, (_, (_, Right (Rval (Value.Symbol text))))) -> Just (SpecHelpers.name text)
      _                                               -> error "declaredName for SpecEff should return an RVal"

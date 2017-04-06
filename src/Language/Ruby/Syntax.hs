{-# LANGUAGE DataKinds, GADTs #-}
module Language.Ruby.Syntax where

import Control.Monad.Free.Freer
import Data.Functor.Union
import qualified Data.Syntax.Comment as Comment
import qualified Data.Syntax.Declaration as Declaration
import qualified Data.Syntax.Literal as Literal
import qualified Data.Syntax.Statement as Statement
import Prologue

-- | The type of Ruby syntax.
type Syntax = Union
  '[Comment.Comment
  , Declaration.Class
  , Declaration.Method
  , Literal.Boolean
  , Statement.If
  , Statement.Return
  , Statement.Yield
  ]

-- | Assignment from an AST with some set of 'symbol's onto some other value.
--
--   This is essentially a parser.
type Assignment symbol = Freer (AssignmentF symbol)

data AssignmentF symbol a where
  Rule :: symbol -> a -> AssignmentF symbol a
  Content :: AssignmentF symbol ByteString
  Children :: Assignment symbol a -> AssignmentF symbol [a]
  Fail :: AssignmentF symbol a

-- | Match a node with the given symbol and apply a rule to it to parse it.
rule :: symbol -> Assignment symbol a -> Assignment symbol a
rule symbol = wrap . Rule symbol

-- | A rule to produce a node’s content as a ByteString.
content :: Assignment symbol ByteString
content = Content `Then` return

-- | Match a node by applying an assignment to its children.
children :: Assignment symbol a -> Assignment symbol [a]
children forEach = Children forEach `Then` return


-- | A program in some syntax functor, over which we can perform analyses.
type Program = Freer


-- | Statically-known rules corresponding to symbols in the grammar.
data Grammar = Program | Uninterpreted | BeginBlock | EndBlock | Undef | Alias | Comment | True' | False' | If
  deriving (Enum, Eq, Ord, Show)

-- | Assignment from AST in Ruby’s grammar onto a program in Ruby’s syntax.
assignment :: Assignment Grammar (Program Syntax (Maybe a))
assignment = foldr (>>) (pure Nothing) <$> rule Program (children declaration)
  where declaration = comment

comment :: Assignment Grammar (Program Syntax a)
comment = wrapU . Comment.Comment <$> (rule Comment content)

if' :: Assignment Grammar (Program Syntax a)
if' = rule If (wrapU <$> (Statement.If <$> expr <*> expr <*> expr))

expr :: Assignment Grammar (Program Syntax a)
expr = if'


-- | A rose tree.
data Rose a = Rose a [Rose a]
  deriving (Eq, Functor, Show)

-- | A node in the input AST. We only concern ourselves with its symbol (considered as an element of 'grammar') and content.
data Node grammar = Node { nodeSymbol :: grammar, nodeContent :: ByteString }

-- | An abstract syntax tree.
type AST grammar = Rose (Node grammar)

stepAssignment :: Eq grammar => Assignment grammar a -> [AST grammar] -> Maybe ([AST grammar], a)
stepAssignment = iterFreer (\ assignment yield nodes -> case nodes of
  [] -> Nothing
  Rose Node{..} children : rest -> case assignment of
    Rule symbol subRule ->
      if symbol == nodeSymbol then
        yield subRule nodes
      else
        Nothing
    Content -> yield nodeContent rest
    Children each -> yield (snd (forEach children)) rest
      where forEach rest = case stepAssignment each rest of
              Just (rest, x) -> let (rest', xs) = forEach rest in (rest', x : xs)
              Nothing -> (rest, [])
    Fail -> Nothing) . fmap ((Just .) . flip (,))

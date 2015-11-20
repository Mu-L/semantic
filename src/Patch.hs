module Patch where

data Patch a =
  Replace a a
  | Insert a
  | Delete a
  deriving (Functor, Show, Eq)

after :: Patch a -> Maybe a
after (Replace _ a) = Just a
after (Insert a) = Just a
after _ = Nothing

before :: Patch a -> Maybe a
before (Replace a _) = Just a
before (Delete a) = Just a
before _ = Nothing

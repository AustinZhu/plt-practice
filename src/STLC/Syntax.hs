module STLC.Syntax where

data Term
  = TmVar Int
  | TmAbs String Type Term
  | TmApp Term Term
  | TmTrue
  | TmFalse
  | TmUnit
  | TmInt Int
  | TmString String
  | TmSucc
  | TmLet String Term Term
  | TmIf Term Term Term
  | TmPair Term Term
  | TmFst Term
  | TmSnd Term
  | TmInl Term Type
  | TmInr Term Type
  | TmCase Term Pattern Pattern
  | TmFix Term
  | TmLetRec String Type Term Term

type Pattern = (String, Term)

data Type = TyBool | TyNat | TyString | TyUnit | TyPair Type Type | TyVariant Type Type | TyArr Type Type deriving (Eq)

type NameContext = [String]

fresh :: NameContext -> String -> (NameContext, String)
fresh ctx x = if isNameBound ctx x then fresh ctx (x ++ "'") else (x : ctx, x)
  where
    isNameBound ctx' x' = case ctx' of
      [] -> False
      (y : ys) -> y == x' || isNameBound ys x

indexOf :: NameContext -> String -> Int
indexOf [] x = error (concat ["indentifier ", x, " is not in scope"])
indexOf (y : ys) x = if y == x then 0 else 1 + indexOf ys x

instance Show Term where showsPrec = prettyTm

prettyTm :: Int -> Term -> ShowS
prettyTm prec = go (prec /= 0) []
  where
    go :: Bool -> NameContext -> Term -> ShowS
    go p ctx tm = case tm of
      TmAbs x _ t1 ->
        let (ctx', x') = fresh ctx x
         in showParen p ((concat ["λ", x', ". "] ++) . go False ctx' t1)
      TmApp t1 t2 -> go True ctx t1 . (" " ++) . go True ctx t2
      TmVar x -> (ctx !! x ++)
      TmTrue -> ("true" ++)
      TmFalse -> ("false" ++)
      TmUnit -> ("unit" ++)
      TmInt x -> (show x ++)
      TmString x -> (show x ++)
      TmSucc -> ("succ" ++)
      TmLet x t1 t2 ->
        let (ctx', x') = fresh ctx x
         in showParen p ((concat ["let ", x', " = "] ++) . go False ctx' t1 . (" in " ++) . go False ctx' t2)
      TmIf t1 t2 t3 ->
        showParen p (("if " ++) . go False ctx t1 . (" then " ++) . go False ctx t2 . (" else " ++) . go False ctx t3)
      TmPair t1 t2 -> ("{" ++) . go True ctx t1 . ("," ++) . go True ctx t2 . ("}" ++)
      TmFst t1 -> go True ctx t1 . (".1" ++)
      TmSnd t1 -> go True ctx t1 . (".2" ++)
      TmInl t1 _ -> ("inl " ++) . go True ctx t1
      TmInr t1 _ -> ("inr " ++) . go True ctx t1
      TmCase t pl pr ->
        ("case " ++)
          . go False ctx t
          . (" of\n  inl " ++)
          . (fst pl ++)
          . (" => " ++)
          . go False ctx (snd pl)
          . ("\n| inr " ++)
          . (fst pr ++)
          . (" => " ++)
          . go False ctx (snd pr)
      TmFix t1 -> ("fix " ++) . go True ctx t1
      TmLetRec x _ t1 t2 ->
        let (ctx', x') = fresh ctx x
         in showParen p ((concat ["letrec ", x', " = "] ++) . go False ctx' t1 . (" in " ++) . go False ctx' t2)

module STLC.Parser (parseCode) where

import Control.Applicative ((<**>))
import Data.Functor (($>))
import Data.Kind ()
import Data.Void (Void)
import STLC.Syntax (NameContext, Term (..), Type (..), indexOf)
import System.Exit (exitFailure)
import Text.Megaparsec
  ( MonadParsec (eof, try),
    Parsec,
    between,
    choice,
    errorBundlePretty,
    many,
    optional,
    parse,
    some,
    (<|>),
    anySingleBut
  )
import qualified Text.Megaparsec.Char as C
import qualified Text.Megaparsec.Char.Lexer as L

type Parser = Parsec Void String

whitespace :: Parser ()
whitespace = L.space C.space1 (L.skipLineComment "--") (L.skipBlockComment "{-" "-}")

lexeme :: Parser a -> Parser a
lexeme = L.lexeme whitespace

symbol :: String -> Parser String
symbol = L.symbol whitespace

keywords :: [String]
keywords = ["let", "in", "if", "then", "else", "true", "false", "Nat", "String", "Bool", "Unit", "unit", "succ", "fix", "letrec", "case", "of", "inl", "inr"]

variable :: Parser String
variable = do
  first <- C.letterChar
  rest <- many (C.alphaNumChar <|> C.char '_')
  let name = (first : rest) in if name `elem` keywords
    then fail (name ++ " is a keyword")
    else pure (first : rest)

parens :: Parser a -> Parser a
parens = between (symbol "(") (symbol ")")

quotes :: Parser a -> Parser a
quotes = between (symbol "\"") (symbol "\"")

pTyBool :: Parser Type
pTyBool = symbol "Bool" $> TyBool

pTyNat :: Parser Type
pTyNat = symbol "Nat" $> TyNat

pTyString :: Parser Type
pTyString = symbol "String" $> TyString

pTyUnit :: Parser Type
pTyUnit = symbol "Unit" $> TyUnit

pTyBinary :: String -> (Type -> Type -> Type) -> Parser (Type -> Type)
pTyBinary op cons = do
  symbol op
  ty2 <- parens pTy <|> pTy
  pure (`cons` ty2)

pTyArr :: Parser (Type -> Type)
pTyArr = pTyBinary "->" TyArr

pTyPair :: Parser (Type -> Type)
pTyPair = pTyBinary "*" TyPair

pTyVariant :: Parser (Type -> Type)
pTyVariant = pTyBinary "+" TyVariant

pTyBase :: Parser Type
pTyBase = pTyBool <|> pTyNat <|> pTyString <|> pTyUnit

pTyAtom :: Parser Type
pTyAtom = parens pTy <|> pTyBase

pTy :: Parser Type
pTy = pTyAtom <**> (pTyPair <|> pTyVariant <|> pTyArr <|> pure id)

pTrue :: Parser Term
pTrue = symbol "true" $> TmTrue

pFalse :: Parser Term
pFalse = symbol "false" $> TmFalse

pInt :: Parser Term
pInt = TmInt <$> lexeme L.decimal

pString :: Parser Term
pString = TmString <$> quotes (some $ anySingleBut '"')

pUnit :: Parser Term
pUnit = symbol "unit" $> TmUnit

pConst :: Parser Term
pConst = pTrue <|> pFalse <|> pUnit <|> pInt <|> pString

pSucc :: NameContext -> Parser Term
pSucc ctx = do
  symbol "succ"
  t <- pAtom ctx
  pure $ TmApp TmSucc t

pPair :: NameContext -> Parser Term
pPair ctx = do
  symbol "{"
  t1 <- pAtom ctx
  symbol ","
  t2 <- pAtom ctx
  symbol "}"
  pure $ TmPair t1 t2

pVar :: NameContext -> Parser Term
pVar ctx = do
  x <- lexeme variable
  let idx = indexOf ctx x
  pure $ TmVar idx

pLam :: NameContext -> Parser Term
pLam ctx = do
  symbol "\\"
  x <- lexeme (variable <|> symbol "_")
  symbol ":"
  ty <- pTy
  symbol "."
  tm <- pTerm (x : ctx)
  pure $ TmAbs x ty tm

pLet :: NameContext -> Parser Term
pLet ctx = do
  symbol "let"
  x <- lexeme variable
  symbol "="
  tm1 <- pTerm (x : ctx)
  symbol "in"
  tm2 <- pTerm (x : ctx)
  pure $ TmLet x tm1 tm2

pIf :: NameContext -> Parser Term
pIf ctx = do
  symbol "if"
  tm1 <- pTerm ctx
  symbol "then"
  tm2 <- pTerm ctx
  symbol "else"
  tm3 <- pTerm ctx
  pure $ TmIf tm1 tm2 tm3

pLetRec :: NameContext -> Parser Term
pLetRec ctx = do
  symbol "letrec"
  x <- lexeme variable
  symbol ":"
  ty <- pTy
  symbol "="
  tm1 <- pTerm (x : ctx)
  symbol "in"
  tm2 <- pTerm (x : ctx)
  pure $ TmLetRec x ty tm1 tm2

pApp :: NameContext -> Parser (Term -> Term)
pApp ctx = do
  C.space
  t2 <- pAtom ctx
  pure (`TmApp` t2)

pSeq :: NameContext -> Parser (Term -> Term)
pSeq ctx = do
  symbol ";"
  t2 <- pAtom ctx
  pure $ TmApp (TmAbs "_" TyUnit t2)

pFst :: Parser (Term -> Term)
pFst = symbol ".1" $> TmFst

pSnd :: Parser (Term -> Term)
pSnd = symbol ".2" $> TmSnd

pInl :: NameContext -> Parser Term
pInl ctx = do
  symbol "inl"
  t <- pAtom ctx
  symbol "as"
  TmInl t <$> pTy

pInr :: NameContext -> Parser Term
pInr ctx = do
  symbol "inr"
  t <- pAtom ctx
  symbol "as"
  TmInr t <$> pTy

pCase :: NameContext -> Parser Term
pCase ctx = do
  symbol "case"
  t <- pTerm ctx
  symbol "of"
  symbol "inl"
  xl <- variable
  symbol "=>"
  tl <- pTerm (xl : ctx)
  symbol "|"
  symbol "inr"
  xr <- variable
  symbol "=>"
  tr <- pTerm (xr : ctx)
  pure $ TmCase t (xl, tl) (xr, tr)

pFix :: NameContext -> Parser Term
pFix ctx = do
  symbol "fix"
  t <- pAtom ctx
  pure $ TmFix t

pInit :: NameContext -> Parser Term
pInit ctx = pAtom ctx <**> (pSeq ctx <|> pFst <|> pSnd <|> try (pApp ctx) <|> pure id)

pTerm :: NameContext -> Parser Term
pTerm ctx = pLam ctx <|> pLetRec ctx <|> pLet ctx <|> pFix ctx <|> pIf ctx <|> pCase ctx <|> pSucc ctx <|> pInl ctx <|> pInr ctx <|> pInit ctx <|> pPair ctx

pAtom :: NameContext -> Parser Term
pAtom ctx = parens (pTerm ctx) <|> pConst <|> pVar ctx

pSrc :: Parser Term
pSrc = between whitespace eof (pTerm [])

parseCode :: String -> Term
parseCode src = case parse pSrc "" src of
  Left e -> error (errorBundlePretty e)
  Right t -> t

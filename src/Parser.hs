{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ExplicitForAll #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Parser
( entry
, test
, ParseErr
) where

import           Control.Applicative (liftA2)
import           Data.Text (Text)
import qualified Data.Text as Txt (append, cons, intercalate, pack, singleton, unpack, isPrefixOf, lines)
import           Data.Time (Day)
import qualified Data.Time as T (defaultTimeLocale, parseTimeOrError)
import           Data.Void (Void)
import           Text.Megaparsec (Parsec, ParseErrorBundle, (<|>), sepBy)
import           Text.Megaparsec.Error as ME (errorBundlePretty)
import qualified Text.Megaparsec as M (between, choice, eof, parse)
import qualified Text.Megaparsec.Char as MC (space1, string, char, digitChar)
import qualified Text.Megaparsec.Char.Lexer as L (space, lexeme, decimal, float, symbol, skipLineComment, skipBlockComment)

import Activities.Activity
import Activities.Run
import Activities.Weights

type Parser = Parsec Void Text
type ParseErr = ParseErrorBundle Text Void

data ParseType
  = PBenchPress
  | PCableCrossover
  | PCableRow
  | PDeadlift
  | PLandmine180
  | PLateralRaise
  | PLegCurl
  | PLegPress
  | PPallofPress
  | PPullUp
  | PShoulderPress
  | PShrug
  | PRun
  deriving (Show, Eq)

-- not using comments at the moment
sc :: Parser ()
sc = L.space
  MC.space1
  (L.skipLineComment "//")
  (L.skipBlockComment "/*" "*/")

lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

pList :: Parser a -> Parser [a]
pList p = M.between (L.symbol sc "[") (L.symbol sc "]") $ (p <* sc) `sepBy` (MC.string "," <* sc)

-- 1. Type
pType :: Parser ParseType
pType = M.choice
  [ lexeme $ PBenchPress <$ MC.string "BenchPress"
  , lexeme $ PCableCrossover <$ MC.string "CableCrossover"
  , lexeme $ PCableRow <$ MC.string "CableRow"
  , lexeme $ PDeadlift <$ MC.string "Deadlift"
  , lexeme $ PLandmine180 <$ MC.string "Landmine180"
  , lexeme $ PLateralRaise <$ MC.string "LateralRaise"
  , lexeme $ PLegCurl <$ MC.string "LegCurl"
  , lexeme $ PLegPress <$ MC.string "LegPress"
  , lexeme $ PPallofPress <$ MC.string "PallofPress"
  , lexeme $ PPullUp <$ MC.string "PullUp"
  , lexeme $ PShoulderPress <$ MC.string "ShoulderPress"
  , lexeme $ PShrug <$ MC.string "Shrug"
  , lexeme $ PRun <$ MC.string "Run" ]

-- 2. Date
pDateSep :: Parser Text
pDateSep = fmap Txt.singleton $ MC.char '-' <|> MC.char '/'

pColon :: Parser Text
pColon = fmap Txt.singleton $ MC.char ':'

pTime :: Parser Time
pTime = lexeme $ MkTime <$> pNum2I <* pColon <*> pNum2I <* pColon <*> pNum2I

pNum2 :: Parser Text
pNum2 = liftA2 (\a -> Txt.cons a . Txt.singleton) MC.digitChar MC.digitChar

pNum2I :: Parser Integer
pNum2I = convert <$> pNum2
  where convert = read . Txt.unpack

pNum4 :: Parser Text
pNum4 = liftA2 Txt.append pNum2 pNum2

pDay :: Parser Day
pDay = lexeme $ toDay <$> pNum2 <* pDateSep <*> pNum2 <* pDateSep <*> pNum4
  where toDay d m y = T.parseTimeOrError True T.defaultTimeLocale "%d-%m-%Y" $ toFmtStr d m y
        toFmtStr d m y = Txt.unpack $ Txt.intercalate "-" [d, m, y]

-- 3. Set
pInt :: Parser Integer
pInt = lexeme L.decimal

pSet :: Parser Set
pSet = MkSet <$> pInt <* MC.string "x" <*> pInt

pSets :: Parser [Set]
pSets = pList pSet

pFloat :: Parser Float
pFloat = lexeme L.float

-- 4. All together now
pWeight :: forall (a :: WeightType). Parser (Weight a)
pWeight = MkWeight <$> pDay <*> pInt <*> pSets <* M.eof

pBenchPress :: Parser (Weight 'BenchPress)
pBenchPress = pWeight

pCableCrossover :: Parser (Weight 'CableCrossover)
pCableCrossover = pWeight

pCableRow :: Parser (Weight 'CableRow)
pCableRow = pWeight

pDeadlift :: Parser (Weight 'Deadlift)
pDeadlift = pWeight

pLandmine180 :: Parser (Weight 'Landmine180)
pLandmine180 = pWeight

pLateralRaise :: Parser (Weight 'LateralRaise)
pLateralRaise = pWeight

pLegCurl :: Parser (Weight 'LegCurl)
pLegCurl = pWeight

pLegPress :: Parser (Weight 'LegPress)
pLegPress = pWeight

pPallofPress :: Parser (Weight 'PallofPress)
pPallofPress = pWeight

pPullUp :: Parser (Weight 'PullUp)
pPullUp = pWeight

pShoulderPress :: Parser (Weight 'ShoulderPress)
pShoulderPress = pWeight

pShrug :: Parser (Weight 'Shrug)
pShrug = pWeight

pRun :: Parser Run
pRun = MkRun <$> pDay <*> pFloat <*> pTime <* M.eof

pActivity :: Parser Activity
pActivity = pType >>=
  \case
    PBenchPress -> fmap ActBenchPress pBenchPress
    PCableCrossover -> fmap ActCableCrossover pCableCrossover
    PCableRow -> fmap ActCableRow pCableRow
    PDeadlift -> fmap ActDeadlift pDeadlift
    PLandmine180 -> fmap ActLandmine180 pLandmine180
    PLateralRaise -> fmap ActLateralRaise pLateralRaise
    PLegCurl -> fmap ActLegCurl pLegCurl
    PLegPress -> fmap ActLegPress pLegPress
    PPallofPress -> fmap ActPallofPress pPallofPress
    PPullUp -> fmap ActPullUp pPullUp
    PShoulderPress -> fmap ActShoulderPress pShoulderPress
    PShrug -> fmap ActShrug pShrug
    PRun -> fmap ActRun pRun

entry :: String -> Either ParseErr [Activity]
entry = sequence . parsing . Txt.lines . Txt.pack

parsing :: [Text] -> [Either ParseErr Activity]
parsing = fmap (M.parse pActivity "") . filter (not . skip)
  where skip s = s `elem` ["", "\n"] || "#" `Txt.isPrefixOf` s

test :: Either ParseErr Activity -> String
test (Left bundle) = ME.errorBundlePretty bundle
test (Right _) = "Succeeded! "
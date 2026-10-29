-- JSON (RFC 8259) for Alex, written the way the Alex and Happy tutorials write a lexer: a token for
-- each piece, over a (lazy) ByteString.  A string and a number are kept as the bytes the input holds
-- (nothing unescaped or converted), as the hbnf parsers keep them.
{
module Lexer (Token (..), alexScanTokens) where
import qualified Data.ByteString.Lazy as L
}

%wrapper "basic-bytestring"

$digit = 0-9
$hex   = [0-9a-fA-F]
@int   = \-? (0 | [1-9] $digit*)
@frac  = \. $digit+
@exp   = [eE] [\+\-]? $digit+
@esc   = \\ ([\"\\\/bfnrt] | u $hex $hex $hex $hex)
@str   = \" ([^\"\\ \x00-\x1f] | @esc)* \"

tokens :-
  [\ \t\r\n]+       ;
  \{                { \_ -> TLBrace }
  \}                { \_ -> TRBrace }
  \[                { \_ -> TLBrack }
  \]                { \_ -> TRBrack }
  \:                { \_ -> TColon }
  \,                { \_ -> TComma }
  true              { \_ -> TTrue }
  false             { \_ -> TFalse }
  null              { \_ -> TNull }
  @str              { \s -> TStr s }
  @int @frac? @exp? { \s -> TNum s }

{
data Token = TLBrace | TRBrace | TLBrack | TRBrack | TColon | TComma | TTrue | TFalse | TNull
           | TStr L.ByteString | TNum L.ByteString
}

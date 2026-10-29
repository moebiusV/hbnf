-- JSON (RFC 8259) for Happy, tuned: strict fields in the values, and the lists built by a left
-- recursion that consumes the tokens as they come.
{
module Parser (JValue (..), parseJson) where
import qualified Data.ByteString.Lazy as L
import Lexer
}

%name parseJson
%tokentype { Token }
%error { parseError }

%token
  '{'   { TLBrace }
  '}'   { TRBrace }
  '['   { TLBrack }
  ']'   { TRBrack }
  ':'   { TColon }
  ','   { TComma }
  true  { TTrue }
  false { TFalse }
  null  { TNull }
  str   { TStr $$ }
  num   { TNum $$ }

%%

Value : Object { $1 }
      | Array  { $1 }
      | str    { JStr $1 }
      | num    { JNum $1 }
      | true   { JBool True }
      | false  { JBool False }
      | null   { JNull }

Object : '{' '}'         { JObj [] }
       | '{' Members '}' { JObj (reverse $2) }

Members : Member             { [$1] }
        | Members ',' Member { $3 : $1 }

Member : str ':' Value { ($1, $3) }

Array : '[' ']'        { JArr [] }
      | '[' Elems ']'  { JArr (reverse $2) }

Elems : Value            { [$1] }
      | Elems ',' Value  { $3 : $1 }

{
data JValue = JObj ![(L.ByteString, JValue)] | JArr ![JValue] | JStr !L.ByteString | JNum !L.ByteString
            | JBool !Bool | JNull

parseError :: [Token] -> a
parseError _ = error "parse error"
}

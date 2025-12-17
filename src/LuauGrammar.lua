local Grammar = if game then require(script.Parent.External.termite.Grammar) else require "../external/termite/src/Grammar"
local Rule = if game then require(script.Parent.External.termite.Rule) else require "../external/termite/src/Rule"
local Expression = if game then require(script.Parent.External.termite.Expression) else require "../external/termite/src/Expression"

local LuauGrammar = Grammar.new({
	Rule.fromString([[NUM_HEX = @{ "0" ~ ^"x" ~ ASCII_HEX_DIGIT+ }]]),
	Rule.fromString([[NUM_BIN = @{ "0" ~ ^"b" ~ ASCII_BIN_DIGIT+ }]]),
	Rule.fromString([[NUMBER = @{ (NUM_HEX | NUM_BIN) | (ASCII_DIGIT ~ (ASCII_DIGIT | "_")* ~ ("." ~ (ASCII_DIGIT | "_")*)? ) ~ (^"e" ~ "-"? ~ (("_"+ ~ ASCII_DIGIT) |  ASCII_DIGIT) ~ (ASCII_DIGIT | "_")*)? }]]),

	Rule.fromString([[RAW_STRING = ${ "[" ~ PUSH("="*) ~ "[" ~ RAW_STRING_INTERIOR ~ "]" ~ POP ~ "]" }]]),
	Rule.fromString([[RAW_STRING_INTERIOR = @{ (!("]" ~ PEEK ~ "]") ~ ANY)* }]]),
	Rule.fromString([[RAW_STRING_INCOMP = @{ "[" ~ "="* ~ "[" ~ ANY* ~ EOI }]]),
	Rule.fromString([[QUOTED_STRING = ${ PUSH("\"" | "'") ~ QUOTED_STRING_INTERIOR ~ POP }]]),
	Rule.fromString([[QUOTED_STRING_INTERIOR = @{ (!PEEK ~ ANY)* }]]),
	Rule.fromString([[QUOTED_STRING_INCOMP = ${ ("\"" | "'") ~ (!NEWLINE ~ ANY)* ~ (NEWLINE | EOI) }]]),
	Rule.fromString([[STRING = { QUOTED_STRING | RAW_STRING | QUOTED_STRING_INCOMP | RAW_STRING_INCOMP  }]]),

	Rule.fromString([[NAME = @{ KEYWORD? ~ (ASCII_ALPHA | "_") ~ (ASCII_ALPHANUMERIC | "_")* }]]),

	Rule.fromString('WHITESPACE = _{ " " | "\t" | NEWLINE }'),
	Rule.fromString('COMMENT = _{ "--" ~ (RAW_STRING | RAW_STRING_INCOMP | ((!NEWLINE ~ ANY)* ~ NEWLINE)) }'),

	Rule.fromString([[chunk = { SOI ~ block}]]),
	Rule.fromString([[block = { (stat ~ ";"?)* ~ (laststat ~ ";"?)? }]]),

	Rule.fromString([[VARLIST_ASSIGN = { varlist ~ "=" ~ explist }]]),
	Rule.fromString([[COMPOUND_ASSIGN = { var ~ compoundop ~ exp }]]),
	Rule.fromString([[DO_BLOCK = { "do" ~ block ~ "end" }]]),
	Rule.fromString([[WHILE_BLOCK = { "while" ~ exp ~ "do" ~ block ~ "end" }]]),
	Rule.fromString([[REPEAT_BLOCK = { "repeat" ~ block ~ "until" ~ exp }]]),
	Rule.fromString([[IF_BLOCK = { "if" ~ exp ~ "then" ~ block }]]),
	Rule.fromString([[ELSEIF_BLOCK = { "elseif" ~ exp ~ "then" ~ block }]]),
	Rule.fromString([[ELSE_BLOCK = { ( "else" ~ block ) }]]),
	Rule.fromString([[IF = { IF_BLOCK ~ ELSEIF_BLOCK* ~ ELSE_BLOCK? ~ "end" }]]),
	Rule.fromString([[FOR_NUMBER = { "for" ~ binding ~ "=" ~ exp ~ "," ~ exp ~ ("," ~ exp)? ~ "do" ~ block ~ "end" }]]),
	Rule.fromString([[FOR_IN = { "for" ~ bindinglist ~ "in" ~ explist ~ "do" ~ block ~ "end" }]]),
	Rule.fromString([[FUNC_DEF = { "function" ~ funcname ~ funcbody }]]),
	Rule.fromString([[LOCAL_FUNC_DEF = { "local" ~ "function" ~ NAME ~ funcbody }]]),
	Rule.fromString([[LOCAL_ASSIGN = { "local" ~ bindinglist ~ ("=" ~ explist)? }]]),
	Rule.fromString([[TYPE_EXPORT = { "export" }]]),
	Rule.fromString([[TYPE_DEF = { TYPE_EXPORT? ~ "type" ~ NAME ~ ("<" ~ GenericTypeListWithDefaults ~ ">")? ~ "=" ~ Type }]]),

	Rule.fromString([[stat = {
        LOCAL_ASSIGN |
        VARLIST_ASSIGN |
        COMPOUND_ASSIGN |

        DO_BLOCK |
        WHILE_BLOCK |
        REPEAT_BLOCK |

        IF |

        FOR_IN |
        FOR_NUMBER |

        #func = LOCAL_FUNC_DEF |
        #func = FUNC_DEF |
        FUNC_CALL |
        TYPE_DEF
    }]]),

	Rule.fromString([[RETURN_STAT = { "return" ~ explist? }]]),
	Rule.fromString([[laststat = { RETURN_STAT | "break" | "continue" }]]),

	Rule.fromString("METHOD_NAME = @{ NAME }"),
	Rule.fromString([[funcname = { NAME ~ ("." ~ NAME)* ~ (":" ~ METHOD_NAME)? }]]),
	Rule.fromString([[funcbody = { ("<" ~ GenericTypeList ~ ">")? ~ "(" ~ parlist? ~ ")" ~ (":" ~ ReturnType)? ~ block ~ "end" }]]),
	Rule.fromString([[VARARGS = { "..." }]]),
	Rule.fromString([[parlist = { (VARARGS ~ (":" ~ (GenericTypePack | Type))?) | (bindinglist ~ ("," ~ VARARGS ~ (":" ~ (GenericTypePack | Type))?)?) }]]),

	Rule.fromString([[explist = { (exp ~ ",")* ~ exp }]]),
	Rule.fromString([[namelist = { NAME ~ ("," ~ NAME)* }]]),

	Rule.fromString([[binding = { NAME ~ (":" ~ Type)? }]]),
	Rule.fromString([[bindinglist = { binding ~ ("," ~ binding)* }]]),

	Rule.fromString([[varlist = { (var ~ ",")* ~ var }]]),

	Rule.fromString([[PREFIX_START = { NAME | ("(" ~ exp ~ ")") }]]),
	Rule.fromString([[PREFIX_INDEX_EXP = { "[" ~ exp ~ "]" }]]),
	Rule.fromString([[PREFIX_INDEX_NAME = { "." ~ NAME }]]),
	Rule.fromString([[PREFIX_INDEX = { PREFIX_INDEX_EXP | PREFIX_INDEX_NAME }]]),
	Rule.fromString([[PREFIX_CALL_FUNC = { "." ~ NAME ~ funcargs }]]),
	Rule.fromString([[PREFIX_CALL_METHOD = { ":" ~ NAME ~ funcargs }]]),
	Rule.fromString([[PREFIX_CALL = { funcargs | PREFIX_CALL_FUNC | PREFIX_CALL_METHOD }]]),
	Rule.fromString([[PREFIX_ACCESS = { PREFIX_INDEX_EXP | funcargs | PREFIX_CALL_FUNC | PREFIX_INDEX_NAME | PREFIX_CALL_METHOD }]]),
	Rule.fromString([[FUNC_CALL = { PREFIX_START ~ (!(PREFIX_CALL ~ !PREFIX_ACCESS) ~ PREFIX_ACCESS)* ~ PREFIX_CALL }]]),
	Rule.fromString([[var = { PREFIX_START ~ (!(PREFIX_INDEX ~ !PREFIX_ACCESS) ~ PREFIX_ACCESS)* ~ PREFIX_INDEX? }]]),
	Rule.fromString([[PREFIX_EXP = { PREFIX_START ~ PREFIX_ACCESS* }]]),

	Rule.fromString([[exp = { (asexp ~ (binop ~ exp)*) | (unop ~ exp ~ (binop ~ exp)*) }]]),
	Rule.fromString([[ifelseexp = { "if" ~ exp ~ "then" ~ exp ~ ("elseif" ~ exp ~ "then" ~ exp)* ~ "else" ~ exp }]]),
	Rule.fromString([[asexp = { simpleexp ~ ("::" ~ Type)? }]]),
	Rule.fromString([[stringinterp = { INTERP_BEGIN ~ exp ~ (INTERP_MID ~ exp)* ~ INTERP_END }]]),
	Rule.fromString([[simpleexp = { NUMBER | STRING | "nil" | "true" | "false" | "..." | tableconstructor | ("function" ~ funcbody) | PREFIX_EXP | ifelseexp | stringinterp }]]),
	Rule.fromString([[funcargs = { ("(" ~ explist? ~ ")") | tableconstructor | STRING }]]),

	Rule.fromString([[tableconstructor = { "{" ~ fieldlist? ~ "}" }]]),
	Rule.fromString([[fieldlist = { field ~ (fieldsep ~ field)* ~ fieldsep? }]]),
	Rule.fromString([[field = { ("[" ~ exp ~ "]" ~ "=" ~ exp) | (NAME ~ "=" ~ exp) | exp }]]),
	Rule.fromString([[fieldsep = _{ "," | ";" }]]),

	Rule.fromString([[compoundop = { "+=" | "-=" | "*=" | "/=" | "%=" | "^=" }]]),
	Rule.fromString([[binop = { "+" | "-" | "*" | "/" | "%" | "^" | ".." | "<=" | "<" | ">=" | ">" | "==" | "~=" | "and" | "or" }]]),
	Rule.fromString([[unop = { "-" | "not" | "#" }]]),

	Rule.new("SQUIGGLY_OPEN", "_", Expression.literalString("{")),
	Rule.new("SQUIGGLY_CLOSE", "_", Expression.literalString("}")),
	Rule.fromString([[INTERP_INNER = { (!(SQUIGGLY_OPEN | "`") ~ ANY)* }]]),
	Rule.fromString([[INTERP_END_INNER = { (!"`" ~ ANY)* }]]),
	Rule.fromString([[INTERP_BEGIN = { "`" ~ INTERP_INNER }]]),
	Rule.fromString([[INTERP_MID = { SQUIGGLY_CLOSE ~ INTERP_INNER }]]),
	Rule.fromString([[INTERP_END = { INTERP_END_INNER ~ "`"}]]),

	Rule.fromString([[KEYWORD = {
        "and" |
        "break" |
        "do" |
        "else" |
        "elseif" |
        "end" |
        "false" |
        "for" |
        "function" |
        "if" |
        "in" |
        "local" |
        "nil" |
        "not" |
        "or" |
        "repeat" |
        "return" |
        "then" |
        "true" |
        "until" |
        "while"
    }]]),

	-- TODO: Add support for function attributes

	Rule.fromString([[NIL_TYPE = { "nil" }]]),
	Rule.fromString([[GENERIC_TYPE = { NAME ~ !"..." ~ ("." ~ NAME)? ~ ("<" ~ TypeParams ~ ">")? }]]),
	Rule.fromString([[TYPEOF_TYPE = { "typeof" ~ "(" ~ exp ~ ")" }]]),

	Rule.fromString([[SimpleType = {
        NIL_TYPE |
        SingletonType |
        TYPEOF_TYPE |
        GENERIC_TYPE |
        TableType |
        FunctionType |
        ("(" ~ Type ~ ")")
    }]]),

	Rule.fromString([[SingletonType = { STRING | "true" | "false" }]]),

	Rule.fromString([[NIL_UNION = { "?" }]]),
	Rule.fromString([[Union = {  ("|" ~ SimpleType ~ NIL_UNION?)+ | (SimpleType ~ !"&" ~ NIL_UNION? ~ ("|" ~ SimpleType ~ NIL_UNION?)*) }]]),
	Rule.fromString([[Intersection = { ("&" ~ SimpleType)+ | (SimpleType ~ ("&" ~ SimpleType)*) }]]),
	Rule.fromString([[Type = { Union | Intersection }]]),

	Rule.fromString([[GenericTypePackParameter = { NAME ~ "..." }]]),
	Rule.fromString([[GenericTypeList = { (GenericTypePackParameter | NAME) ~ ("," ~ (GenericTypePackParameter | NAME))* }]]),
	Rule.fromString([[GenericTypePackParameterWithDefault = { NAME ~ "..." ~ "=" ~ (TypePack | VariadicTypePack | GenericTypePack) }]]),
	Rule.fromString([[GenericTypeListWithDefaults = {
        ((NAME ~ ("=" ~ Type)?) | GenericTypePackParameterWithDefault)+
    }]]),

	Rule.fromString([[TypeList = { (Type ~ ("," ~ Type)*)? ~ VariadicTypePack? }]]),
	Rule.fromString([[BoundTypeList = { (GenericTypePack | VariadicTypePack) | (((NAME ~ ":")? ~ Type ~ ("," ~ (NAME ~ ":")? ~ Type)*)? ~ ("," ~ (GenericTypePack | VariadicTypePack))?) }]]),
	Rule.fromString([[TYPE_PARAM = @{ Type | TypePack | VariadicTypePack | GenericTypePack }]]),
	Rule.fromString([[TypeParams = { TYPE_PARAM ~ ("," ~ TYPE_PARAM)* }]]),
	Rule.fromString([[TypePack = { "(" ~ TypeList? ~ ")" }]]),
	-- Includes parentheses since  something like (T...) is an allowed return type
	Rule.fromString([[GenericTypePack = { ("(" ~ NAME ~ "..." ~ ")") | (NAME ~ "...") }]]),
	Rule.fromString([[VariadicTypePack = { "..." ~ Type }]]),
	Rule.fromString([[ReturnType = { Type | TypePack | GenericTypePack | VariadicTypePack }]]),
	Rule.fromString([[TableIndexer = { "[" ~ Type ~ "]" ~ ":" ~ Type }]]),
	Rule.fromString([[TableProp = { NAME ~ ":" ~ Type }]]),
	Rule.fromString([[TablePropOrIndexer = { ("read" | "write")? ~ (TableProp | TableIndexer) }]]),
	Rule.fromString([[PropList = { TablePropOrIndexer ~ (fieldsep ~ TablePropOrIndexer)* ~ fieldsep? }]]),
	Rule.fromString([[TableType = { ("{" ~ Type ~ "}") | ("{" ~ PropList? ~ "}") }]]),
	Rule.fromString([[FunctionType = { ("<" ~ GenericTypeList ~ ">")? ~ "(" ~ BoundTypeList? ~ ")" ~ "->" ~ ReturnType }]]),

	Rule.fromString([[FUNC_SIGNATURE = { SOI ~ "function" ~ funcname ~ ("<" ~ GenericTypeList ~ ">")? ~ "(" ~ parlist? ~ ")" ~ (":" ~ ReturnType)? }]]),
})

export type LuauToken = "GenericTypeList" | "NAME" | "unop" | "WHILE_BLOCK" | "binding" | "NUM_BIN" | "GenericTypePackParameter" | "ELSEIF_BLOCK" | "compoundop" | "RAW_STRING_INCOMP" | "stat" | "simpleexp" | "FUNC_CALL" | "Type" | "RETURN_STAT" | "funcbody" | "GenericTypePack" | "ELSE_BLOCK" | "COMPOUND_ASSIGN" | "tableconstructor" | "PREFIX_ACCESS" | "TypeParams" | "PREFIX_INDEX_EXP" | "METHOD_NAME" | "TableType" | "VARARGS" | "fieldlist" | "DO_BLOCK" | "FUNC_DEF" | "QUOTED_STRING" | "SQUIGGLY_CLOSE" | "stringinterp" | "funcname" | "FOR_NUMBER" | "FunctionType" | "FUNC_SIGNATURE" | "chunk" | "asexp" | "INTERP_BEGIN" | "GenericTypeListWithDefaults" | "PREFIX_INDEX" | "QUOTED_STRING_INTERIOR" | "TypeList" | "TableProp" | "laststat" | "ReturnType" | "TYPE_PARAM" | "QUOTED_STRING_INCOMP" | "TypePack" | "VariadicTypePack" | "BoundTypeList" | "TablePropOrIndexer" | "GenericTypePackParameterWithDefault" | "IF_BLOCK" | "NUMBER" | "PropList" | "IF" | "TYPE_DEF" | "ifelseexp" | "LOCAL_FUNC_DEF" | "explist" | "NIL_UNION" | "SingletonType" | "SimpleType" | "PREFIX_CALL_FUNC" | "namelist" | "TYPEOF_TYPE" | "INTERP_END_INNER" | "RAW_STRING" | "KEYWORD" | "WHITESPACE" | "INTERP_END" | "PREFIX_EXP" | "STRING" | "SQUIGGLY_OPEN" | "exp" | "Intersection" | "GENERIC_TYPE" | "REPEAT_BLOCK" | "INTERP_INNER" | "INTERP_MID" | "NIL_TYPE" | "fieldsep" | "VARLIST_ASSIGN" | "binop" | "COMMENT" | "NUM_HEX" | "funcargs" | "PREFIX_CALL" | "LOCAL_ASSIGN" | "block" | "TYPE_EXPORT" | "varlist" | "RAW_STRING_INTERIOR" | "FOR_IN" | "TableIndexer" | "Union" | "var" | "PREFIX_INDEX_NAME" | "PREFIX_CALL_METHOD" | "PREFIX_START" | "bindinglist" | "parlist" | "field"

return LuauGrammar

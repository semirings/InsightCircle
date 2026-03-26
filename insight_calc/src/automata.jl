# automata.jl — D4M query parser and dispatcher using Automa.jl
# Translates MATLAB-style D4M strings into BigQuery SQL params or D4M.jl getindex calls.

using Automa
using Logging

# ─────────────────────────────────────────────────────────────────────────────
# AST Types
# ─────────────────────────────────────────────────────────────────────────────

abstract type D4MNode end

struct QueryNode  <: D4MNode; rows::D4MNode;          cols::D4MNode          end
struct SetNode    <: D4MNode; elements::Vector{D4MNode}                       end
struct AllNode    <: D4MNode                                                   end
struct ScalarNode <: D4MNode; value::String                                   end
struct RangeNode  <: D4MNode; start::String;           stop::String           end
struct PrefixNode <: D4MNode; prefix::String                                  end

@enum QueryTarget BigQueryTarget D4MTarget

# ─────────────────────────────────────────────────────────────────────────────
# Token types (emitted by the Automa FSM)
# ─────────────────────────────────────────────────────────────────────────────

@enum TokenKind TK_IDENT TK_RANGE_OP TK_STAR TK_COMMA TK_COLON TK_WS TK_ERROR

struct Token
    kind  :: TokenKind
    value :: String
end

# ─────────────────────────────────────────────────────────────────────────────
# Automa 1.x tokenizer
# make_tokenizer defines Base.iterate(::Tokenizer{TokenKind,...}) via @eval.
# Longest-match wins; TK_ERROR is emitted for unrecognised bytes.
# ─────────────────────────────────────────────────────────────────────────────

make_tokenizer((
    TK_ERROR,
    [
        TK_IDENT    => re"[A-Za-z0-9_\-/]+",
        TK_RANGE_OP => re"\.\.",
        TK_STAR     => re"\*",
        TK_COMMA    => re",",
        TK_COLON    => re":",
        TK_WS       => re"[ \t]+",
    ]
)) |> eval

function _lex(s::String)::Vector{Token}
    tokens = Token[]
    for (pos, len, kind) in tokenize(TokenKind, s)
        kind == TK_ERROR && error("Unexpected input at byte $pos: $(repr(s[pos:pos+Int(len)-1]))")
        kind == TK_WS    && continue
        value = s[pos : pos + Int(len) - 1]
        push!(tokens, Token(kind, value))
        @debug "[lex]" kind value
    end
    @debug "[lex] result" tokens
    return tokens
end

# ─────────────────────────────────────────────────────────────────────────────
# Parser — converts token stream into AST
# Grammar:
#   query   := expr COLON expr
#   expr    := COLON                              -> AllNode
#            | item (COMMA item)*
#   item    := IDENT RANGE_OP IDENT               -> RangeNode
#            | IDENT STAR                         -> PrefixNode
#            | IDENT                              -> ScalarNode
# ─────────────────────────────────────────────────────────────────────────────

# Mutable cursor over the token vector
mutable struct _Parser
    tokens :: Vector{Token}
    pos    :: Int
end

_peek(p::_Parser)   = p.pos <= length(p.tokens) ? p.tokens[p.pos] : nothing
_consume(p::_Parser) = (t = p.tokens[p.pos]; p.pos += 1; t)
_done(p::_Parser)   = p.pos > length(p.tokens)

function _parseItem(p::_Parser)::D4MNode
    t = _consume(p)
    t.kind == TK_IDENT || error("Expected identifier, got $(t)")

    next = _peek(p)
    if !isnothing(next) && next.kind == TK_RANGE_OP
        _consume(p)   # consume ".."
        t2 = _consume(p)
        t2.kind == TK_IDENT || error("Expected identifier after '..', got $(t2)")
        node = RangeNode(t.value, t2.value)
        @debug "[parse] RangeNode" start=t.value stop=t2.value
        return node
    elseif !isnothing(next) && next.kind == TK_STAR
        _consume(p)   # consume "*"
        node = PrefixNode(t.value)
        @debug "[parse] PrefixNode" prefix=t.value
        return node
    else
        node = ScalarNode(t.value)
        @debug "[parse] ScalarNode" value=t.value
        return node
    end
end

function _parseExpr(tokens::Vector{Token})::D4MNode
    if isempty(tokens)
        @debug "[parse] AllNode (empty token list)"
        return AllNode()
    end
    # A lone COLON token signals the all-wildcard
    if length(tokens) == 1 && tokens[1].kind == TK_COLON
        @debug "[parse] AllNode (lone ':')"
        return AllNode()
    end

    p     = _Parser(tokens, 1)
    items = D4MNode[]
    while !_done(p)
        push!(items, _parseItem(p))
        # Consume optional trailing comma between items
        if !_done(p) && _peek(p).kind == TK_COMMA
            _consume(p)
        end
    end
    if length(items) == 1
        return items[1]
    else
        node = SetNode(items)
        @debug "[parse] SetNode" count=length(items)
        return node
    end
end

function _splitOnSeparator(tokens::Vector{Token})
    # Find the first COLON that is the row/col separator.
    # A lone COLON (tokens == [COLON]) is AllNode, not a separator.
    idx = findfirst(t -> t.kind == TK_COLON, tokens)
    if isnothing(idx)
        @debug "[parse] no ':' separator — treating all as row, cols=all"
        return (tokens, Token[Token(TK_COLON, ":")])
    end
    @debug "[parse] ':' separator at token index" idx
    return (tokens[1:idx-1], tokens[idx+1:end])
end

function _parse(input::String)::QueryNode
    tokens = _lex(input)
    @debug "[parse] tokens" tokens
    row_tokens, col_tokens = _splitOnSeparator(tokens)
    rows = _parseExpr(row_tokens)
    cols = _parseExpr(col_tokens)
    @debug "[parse] QueryNode" rows cols
    return QueryNode(rows, cols)
end

# ─────────────────────────────────────────────────────────────────────────────
# Public entry point
# ─────────────────────────────────────────────────────────────────────────────

function scan(input::String, target::QueryTarget)
    @debug "[scan] begin" input target
    ast    = _parse(input)
    result = target == BigQueryTarget ? generateBqParams(ast) : applyD4mMath(ast)
    @debug "[scan] result" result
    return result
end

# ─────────────────────────────────────────────────────────────────────────────
# BigQuery dispatcher — multiple dispatch on D4MNode types
# Produces parameterised SQL to prevent injection.
# ─────────────────────────────────────────────────────────────────────────────

struct BQResult
    row_clause :: String
    col_clause :: String
    params     :: Vector{Any}
end

generateBqParams(q::QueryNode) = BQResult(
    _bqClause(q.rows, "row_key"),
    _bqClause(q.cols, "col_key"),
    vcat(_bqParams(q.rows), _bqParams(q.cols)),
)

# Clause builders
_bqClause(::AllNode,      col::String) = "TRUE"
_bqClause(n::ScalarNode,  col::String) = "$col = ?"
_bqClause(n::RangeNode,   col::String) = "$col BETWEEN ? AND ?"
_bqClause(n::PrefixNode,  col::String) = "$col LIKE ?"
_bqClause(n::SetNode,     col::String) =
    "(" * join([_bqClause(e, col) for e in n.elements], " OR ") * ")"

# Parameter extractors
_bqParams(::AllNode)     = Any[]
_bqParams(n::ScalarNode) = Any[n.value]
_bqParams(n::RangeNode)  = Any[n.start, n.stop]
_bqParams(n::PrefixNode) = Any[n.prefix * "%"]
_bqParams(n::SetNode)    = vcat([_bqParams(e) for e in n.elements]...)

# ─────────────────────────────────────────────────────────────────────────────
# D4M dispatcher — multiple dispatch on D4MNode types
# Resolves to getindex / A[rows, cols] via D4M.jl
# ─────────────────────────────────────────────────────────────────────────────

# Convert a D4MNode into the D4M query string expected by Assoc getindex.
_toD4mStr(::AllNode)     = ":"
_toD4mStr(n::ScalarNode) = n.value * ","
_toD4mStr(n::RangeNode)  = n.start * ".." * n.stop * ","
_toD4mStr(n::PrefixNode) = "StartsWith(" * n.prefix * ")"
_toD4mStr(n::SetNode)    = join([_toD4mStr(e) for e in n.elements])

applyD4mMath(q::QueryNode, A) = A[_toD4mStr(q.rows), _toD4mStr(q.cols)]

# Overload for AST-only (no Assoc yet) — returns the row/col strings for inspection
applyD4mMath(q::QueryNode) = (_toD4mStr(q.rows), _toD4mStr(q.cols))

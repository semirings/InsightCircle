# automata.jl — D4M query parser and dispatcher using Automa.jl
# Translates MATLAB-style D4M strings into BigQuery SQL params or D4M.jl getindex calls.

using Automa

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

@enum TokenKind TK_IDENT TK_RANGE_OP TK_STAR TK_COMMA TK_COLON

struct Token
    kind  :: TokenKind
    value :: String
end

# ─────────────────────────────────────────────────────────────────────────────
# Automa grammar definitions
# re"" patterns are combined into a lexer machine.
# Actions use onenter!/onexit! semantics to mark byte positions.
# ─────────────────────────────────────────────────────────────────────────────

const _LEX_MACHINE = let
    # Terminals
    ident    = re"[A-Za-z0-9_\-./]+"  # key characters used in D4M row/col labels
    range_op = re"\.\."               # range separator
    star     = re"\*"                 # prefix wildcard
    comma    = re","                  # list delimiter
    colon    = re":"                  # all-wildcard / query separator
    ws       = re"[ \t]+"             # ignored whitespace

    # onenter! hooks — record start byte of the current token
    ident.actions[:enter]    = [:mark]

    # onexit! hooks — emit token from [mark, p)
    ident.actions[:exit]     = [:emit_ident]
    range_op.actions[:exit]  = [:emit_range_op]
    star.actions[:exit]      = [:emit_star]
    comma.actions[:exit]     = [:emit_comma]
    colon.actions[:exit]     = [:emit_colon]

    Automa.compile(ident | range_op | star | comma | colon | ws)
end

# Generated FSM execution function.
# Produces a Vector{Token} from raw bytes.
@eval function _lex(data::Vector{UInt8})::Vector{Token}
    tokens = Token[]
    mark   = 1

    $(Automa.generate_exec_code(
        _LEX_MACHINE;
        actions = Dict(
            :mark         => :(mark = p),
            :emit_ident   => :(push!(tokens, Token(TK_IDENT,    String(data[mark:p-1])))),
            :emit_range_op => :(push!(tokens, Token(TK_RANGE_OP, ".."))),
            :emit_star    => :(push!(tokens, Token(TK_STAR,     "*"))),
            :emit_comma   => :(push!(tokens, Token(TK_COMMA,    ","))),
            :emit_colon   => :(push!(tokens, Token(TK_COLON,    ":"))),
        )
    ))

    return tokens
end

_lex(s::AbstractString) = _lex(Vector{UInt8}(s))

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
        return RangeNode(t.value, t2.value)
    elseif !isnothing(next) && next.kind == TK_STAR
        _consume(p)   # consume "*"
        return PrefixNode(t.value)
    else
        return ScalarNode(t.value)
    end
end

function _parseExpr(tokens::Vector{Token})::D4MNode
    isempty(tokens) && return AllNode()
    # A lone COLON token signals the all-wildcard
    if length(tokens) == 1 && tokens[1].kind == TK_COLON
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
    return length(items) == 1 ? items[1] : SetNode(items)
end

function _splitOnSeparator(tokens::Vector{Token})
    # Find the first COLON that is the row/col separator.
    # A lone COLON (tokens == [COLON]) is AllNode, not a separator.
    idx = findfirst(t -> t.kind == TK_COLON, tokens)
    isnothing(idx) && return (tokens, Token[Token(TK_COLON, ":")])
    return (tokens[1:idx-1], tokens[idx+1:end])
end

function _parse(input::String)::QueryNode
    tokens               = _lex(input)
    row_tokens, col_tokens = _splitOnSeparator(tokens)
    return QueryNode(_parseExpr(row_tokens), _parseExpr(col_tokens))
end

# ─────────────────────────────────────────────────────────────────────────────
# Public entry point
# ─────────────────────────────────────────────────────────────────────────────

function scan(input::String, target::QueryTarget)
    ast = _parse(input)
    return target == BigQueryTarget ? generateBqParams(ast) : applyD4mMath(ast)
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

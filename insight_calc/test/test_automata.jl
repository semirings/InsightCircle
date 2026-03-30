# test_automata.jl — Tests for the D4M query parser and dispatcher (automata.jl)

using Test
include("../src/automata.jl")

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

# Convenience: parse a query string and return the QueryNode AST
parseQ(s) = _parse(s)

# Convenience wrappers
bq(s)  = generateBqParams(parseQ(s))
d4m(s) = applyD4mMath(parseQ(s))   # returns (row_str, col_str)

# ─────────────────────────────────────────────────────────────────────────────
# 1. Scalar row, all cols — rowId :
# ─────────────────────────────────────────────────────────────────────────────

@testset "Scalar row / all cols" begin
    q = parseQ("rowId:")

    @test q.rows isa ScalarNode
    @test q.rows.value == "rowId"
    @test q.cols isa AllNode

    # BigQuery target
    r = bq("rowId:")
    @test r.row_clause == "row_key = @p1"
    @test r.col_clause == "TRUE"
    @test r.params == [BQParam("p1", "rowId")]

    # D4M target
    row_str, col_str = d4m("rowId:")
    @test row_str == "rowId,"
    @test col_str == ":"
end

# ─────────────────────────────────────────────────────────────────────────────
# 2. All rows, scalar col — : colName
# ─────────────────────────────────────────────────────────────────────────────

@testset "All rows / scalar col" begin
    q = parseQ(":colName")

    @test q.rows isa AllNode
    @test q.cols isa ScalarNode
    @test q.cols.value == "colName"

    r = bq(":colName")
    @test r.row_clause == "TRUE"
    @test r.col_clause == "col_key = @p1"
    @test r.params == [BQParam("p1", "colName")]

    row_str, col_str = d4m(":colName")
    @test row_str == ":"
    @test col_str == "colName,"
end

# ─────────────────────────────────────────────────────────────────────────────
# 3. Set of rows, all cols — rowId1,rowId2,rowId3 :
# ─────────────────────────────────────────────────────────────────────────────

@testset "Set of rows / all cols" begin
    q = parseQ("rowId1,rowId2,rowId3:")

    @test q.rows isa SetNode
    @test length(q.rows.elements) == 3
    @test all(e isa ScalarNode for e in q.rows.elements)
    @test [e.value for e in q.rows.elements] == ["rowId1", "rowId2", "rowId3"]
    @test q.cols isa AllNode

    r = bq("rowId1,rowId2,rowId3:")
    @test r.row_clause == "(row_key = @p1 OR row_key = @p2 OR row_key = @p3)"
    @test r.col_clause == "TRUE"
    @test r.params == [BQParam("p1","rowId1"), BQParam("p2","rowId2"), BQParam("p3","rowId3")]

    row_str, col_str = d4m("rowId1,rowId2,rowId3:")
    @test row_str == "rowId1,rowId2,rowId3,"
    @test col_str == ":"
end

# ─────────────────────────────────────────────────────────────────────────────
# 4. All rows, set of cols — : colName1,colName2,colName3
# ─────────────────────────────────────────────────────────────────────────────

@testset "All rows / set of cols" begin
    q = parseQ(":colName1,colName2,colName3")

    @test q.rows isa AllNode
    @test q.cols isa SetNode
    @test length(q.cols.elements) == 3
    @test [e.value for e in q.cols.elements] == ["colName1", "colName2", "colName3"]

    r = bq(":colName1,colName2,colName3")
    @test r.row_clause == "TRUE"
    @test r.col_clause == "(col_key = @p1 OR col_key = @p2 OR col_key = @p3)"
    @test r.params == [BQParam("p1","colName1"), BQParam("p2","colName2"), BQParam("p3","colName3")]

    row_str, col_str = d4m(":colName1,colName2,colName3")
    @test row_str == ":"
    @test col_str == "colName1,colName2,colName3,"
end

# ─────────────────────────────────────────────────────────────────────────────
# 5. Range of rows, all cols — rowId1..rowId5 :
# ─────────────────────────────────────────────────────────────────────────────

@testset "Range of rows / all cols" begin
    q = parseQ("rowId1..rowId5:")

    @test q.rows isa RangeNode
    @test q.rows.start == "rowId1"
    @test q.rows.stop  == "rowId5"
    @test q.cols isa AllNode

    r = bq("rowId1..rowId5:")
    @test r.row_clause == "row_key BETWEEN @p1 AND @p2"
    @test r.col_clause == "TRUE"
    @test r.params == [BQParam("p1","rowId1"), BQParam("p2","rowId5")]

    row_str, col_str = d4m("rowId1..rowId5:")
    @test row_str == "rowId1..rowId5,"
    @test col_str == ":"
end

# ─────────────────────────────────────────────────────────────────────────────
# 6. All rows, range of cols — : colName1..colName5
# ─────────────────────────────────────────────────────────────────────────────

@testset "All rows / range of cols" begin
    q = parseQ(":colName1..colName5")

    @test q.rows isa AllNode
    @test q.cols isa RangeNode
    @test q.cols.start == "colName1"
    @test q.cols.stop  == "colName5"

    r = bq(":colName1..colName5")
    @test r.row_clause == "TRUE"
    @test r.col_clause == "col_key BETWEEN @p1 AND @p2"
    @test r.params == [BQParam("p1","colName1"), BQParam("p2","colName5")]

    row_str, col_str = d4m(":colName1..colName5")
    @test row_str == ":"
    @test col_str == "colName1..colName5,"
end

# ─────────────────────────────────────────────────────────────────────────────
# 7. Prefix (wildcard) — prefix*:
# ─────────────────────────────────────────────────────────────────────────────

@testset "Prefix row / all cols" begin
    q = parseQ("vid*:")

    @test q.rows isa PrefixNode
    @test q.rows.prefix == "vid"
    @test q.cols isa AllNode

    r = bq("vid*:")
    @test r.row_clause == "row_key LIKE @p1"
    @test r.params == [BQParam("p1","vid%")]

    row_str, col_str = d4m("vid*:")
    @test row_str == "StartsWith(vid)"
    @test col_str == ":"
end

# ─────────────────────────────────────────────────────────────────────────────
# 8. All rows / all cols — ::
# ─────────────────────────────────────────────────────────────────────────────

@testset "All rows / all cols" begin
    q = parseQ("::")

    @test q.rows isa AllNode
    @test q.cols isa AllNode

    r = bq("::")
    @test r.row_clause == "TRUE"
    @test r.col_clause == "TRUE"
    @test isempty(r.params)

    row_str, col_str = d4m("::")
    @test row_str == ":"
    @test col_str == ":"
end

# ─────────────────────────────────────────────────────────────────────────────
# 9. scan() public entry point — end-to-end
# ─────────────────────────────────────────────────────────────────────────────

@testset "scan() end-to-end" begin
    r = scan("rowId1,rowId2:colName", BigQueryTarget)
    @test r isa BQResult
    @test r.params == [BQParam("p1","rowId1"), BQParam("p2","rowId2"), BQParam("p3","colName")]

    row_str, col_str = scan("rowId1..rowId5:colName", D4MTarget)
    @test row_str == "rowId1..rowId5,"
    @test col_str == "colName,"
end

println("All automata tests passed.")

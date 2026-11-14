local tables = require("cnr.tables")

test("deepEqual compares nested tables regardless of key order", function()
  assertEq(tables.deepEqual({a=1, b={c="x"}}, {b={c="x"}, a=1}), true)
  assertEq(tables.deepEqual({a=1}, {a=1, b=2}), false)
  assertEq(tables.deepEqual({a={1,2}}, {a={1,3}}), false)
  assertEq(tables.deepEqual(nil, nil), true)
  assertEq(tables.deepEqual({}, nil), false)
end)

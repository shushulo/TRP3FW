-- tests/framework.lua
-- Tiny zero-dependency test framework for headless Lua 5.1.
-- Usage in a spec file:
--   local T = require("tests.framework")
--   T.describe("thing", function()
--     T.it("does x", function() T.eq(1+1, 2) end)
--   end)

local T = { _suites = {}, _current = nil, passed = 0, failed = 0, failures = {} }

function T.describe(name, fn)
    T._current = name
    fn()
    T._current = nil
end

function T.it(name, fn)
    local label = (T._current and (T._current .. " :: ") or "") .. name
    local ok, err = pcall(fn)
    if ok then
        T.passed = T.passed + 1
        io.write(".")
    else
        T.failed = T.failed + 1
        table.insert(T.failures, { label = label, err = err })
        io.write("F")
    end
end

-- ===================== Assertions =====================

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function T.eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "values not equal") .. ": expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end

function T.neq(actual, notExpected, msg)
    if actual == notExpected then
        error((msg or "values unexpectedly equal") .. ": both " .. fmt(actual), 2)
    end
end

function T.truthy(v, msg)
    if not v then error((msg or "expected truthy") .. ", got " .. fmt(v), 2) end
end

function T.falsy(v, msg)
    if v then error((msg or "expected falsy") .. ", got " .. fmt(v), 2) end
end

function T.is_nil(v, msg)
    if v ~= nil then error((msg or "expected nil") .. ", got " .. fmt(v), 2) end
end

function T.not_nil(v, msg)
    if v == nil then error(msg or "expected non-nil, got nil", 2) end
end

-- Assert that fn() raises (used for "should crash without the fix" / error-path tests)
function T.raises(fn, msg)
    local ok = pcall(fn)
    if ok then error((msg or "expected an error but none was raised"), 2) end
end

-- Assert that fn() does NOT raise (regression guard for nil-safety fixes)
function T.no_raise(fn, msg)
    local ok, err = pcall(fn)
    if not ok then error((msg or "expected no error") .. ", but got: " .. tostring(err), 2) end
end

function T.report()
    print("")
    print(string.rep("-", 50))
    if #T.failures > 0 then
        print("FAILURES:")
        for _, f in ipairs(T.failures) do
            print("  [FAIL] " .. f.label)
            print("         " .. tostring(f.err))
        end
        print(string.rep("-", 50))
    end
    print(string.format("Passed: %d   Failed: %d   Total: %d",
        T.passed, T.failed, T.passed + T.failed))
    return T.failed == 0
end

return T

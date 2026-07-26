-- tests/unit/cache_interface_spec.lua
-- Headless tests for the unified LRU CacheInterface (O(1) get/set/evict + TTL).

local T = require("tests.framework")
local H = require("tests.harness")

local TRP3FW = H.newNamespace()
H.loadModule("core/cache_interface.lua", TRP3FW)
local CI = TRP3FW.CacheInterface
local mock = H.mock

T.describe("CacheInterface basic get/set", function()
    T.it("returns nil + unknown_cache for unregistered caches", function()
        local v, reason = CI:Get("nope", "k")
        T.is_nil(v)
        T.eq(reason, "unknown_cache")
    end)

    T.it("Set on an unregistered cache returns false (the spvpSessions bug)", function()
        -- This is exactly why SPVP replay protection was a no-op before #1:
        -- writing to an unregistered cache silently stores nothing.
        T.eq(CI:Set("nope", "k", {x = 1}), false)
        T.is_nil(CI:Get("nope", "k"))
    end)

    T.it("stores and retrieves after Register", function()
        CI:Register("c1", { maxSize = 10 })
        T.eq(CI:Set("c1", "a", 111), true)
        T.eq(CI:Get("c1", "a"), 111)
    end)

    T.it("GetSize reflects entry count", function()
        CI:Register("c2", { maxSize = 10 })
        CI:Set("c2", "a", 1); CI:Set("c2", "b", 2); CI:Set("c2", "c", 3)
        T.eq(CI:GetSize("c2"), 3)
    end)
end)

T.describe("CacheInterface TTL expiry", function()
    T.it("evicts entries older than ttl", function()
        mock.setClock(1000)
        CI:Register("ttlc", { ttl = 60, maxSize = 10 })
        CI:Set("ttlc", "k", "v")
        T.eq(CI:Get("ttlc", "k"), "v", "fresh entry returns")

        mock.setClock(1000 + 59)
        T.eq(CI:Get("ttlc", "k"), "v", "still within ttl")

        mock.setClock(1000 + 61)
        local v, reason = CI:Get("ttlc", "k")
        T.is_nil(v, "expired entry gone")
        T.eq(reason, "expired")
    end)
end)

T.describe("CacheInterface LRU eviction (O(1) head drop)", function()
    T.it("evicts the oldest entry when over maxSize", function()
        CI:Register("lru", { maxSize = 3 })
        CI:Set("lru", "a", 1)
        CI:Set("lru", "b", 2)
        CI:Set("lru", "c", 3)
        CI:Set("lru", "d", 4)  -- should evict "a" (oldest)
        T.eq(CI:GetSize("lru"), 3)
        T.is_nil(CI:Get("lru", "a"), "oldest evicted")
        T.eq(CI:Get("lru", "d"), 4)
    end)

    T.it("Get refreshes LRU position (recently-used survives)", function()
        CI:Register("lru2", { maxSize = 3 })
        CI:Set("lru2", "a", 1)
        CI:Set("lru2", "b", 2)
        CI:Set("lru2", "c", 3)
        CI:Get("lru2", "a")     -- touch a -> now most-recent
        CI:Set("lru2", "d", 4)  -- should evict "b" (now oldest), not "a"
        T.not_nil(CI:Get("lru2", "a"), "touched entry survives")
        T.is_nil(CI:Get("lru2", "b"), "untouched oldest evicted")
    end)

    T.it("updating an existing key does not grow size", function()
        CI:Register("upd", { maxSize = 3 })
        CI:Set("upd", "a", 1)
        CI:Set("upd", "a", 2)
        T.eq(CI:GetSize("upd"), 1)
        T.eq(CI:Get("upd", "a"), 2)
    end)
end)

T.describe("CacheInterface Clear / Remove", function()
    T.it("Clear empties the cache", function()
        CI:Register("clr", { maxSize = 10 })
        CI:Set("clr", "a", 1); CI:Set("clr", "b", 2)
        CI:Clear("clr")
        T.eq(CI:GetSize("clr"), 0)
        T.is_nil(CI:Get("clr", "a"))
    end)

    T.it("Remove drops a single key and keeps the list consistent", function()
        CI:Register("rmv", { maxSize = 10 })
        CI:Set("rmv", "a", 1); CI:Set("rmv", "b", 2); CI:Set("rmv", "c", 3)
        CI:Remove("rmv", "b")
        T.eq(CI:GetSize("rmv"), 2)
        T.is_nil(CI:Get("rmv", "b"))
        -- list still walkable both ends after a middle removal
        T.eq(CI:Get("rmv", "a"), 1)
        T.eq(CI:Get("rmv", "c"), 3)
    end)
end)

T.describe("CacheInterface Iterator", function()
    T.it("walks newest to oldest", function()
        CI:Register("it1", { maxSize = 10 })
        CI:Set("it1", "a", 1); CI:Set("it1", "b", 2); CI:Set("it1", "c", 3)

        local seen = {}
        for key in CI:Iterator("it1") do table.insert(seen, key) end
        T.eq(table.concat(seen, ","), "c,b,a")
    end)

    T.it("yields nothing for an unknown or empty cache", function()
        local n = 0
        for _ in CI:Iterator("no_such_cache") do n = n + 1 end
        T.eq(n, 0)

        CI:Register("it2", { maxSize = 10 })
        for _ in CI:Iterator("it2") do n = n + 1 end
        T.eq(n, 0)
    end)

    -- Removing while iterating leaves the cursor pointing at a dead key; the
    -- iterator must stop rather than index nil.
    T.it("stops cleanly when the cursor entry is removed mid-iteration", function()
        CI:Register("it3", { maxSize = 10 })
        CI:Set("it3", "a", 1); CI:Set("it3", "b", 2); CI:Set("it3", "c", 3)

        T.no_raise(function()
            for key in CI:Iterator("it3") do
                CI:Remove("it3", key)
            end
        end)
    end)
end)

T.describe("CacheInterface list integrity", function()
    -- Regression: MoveToTail used to detach the previous link and only then bail
    -- when node.next was nil, orphaning the node. With prev == nil that also set
    -- head = nil while size stayed > 0, which permanently disables head-based
    -- eviction in both Set and PruneIncremental (unbounded growth past maxSize).
    T.it("a desynced node does not null out head or strand the list", function()
        CI:Register("desync", { maxSize = 10 })
        CI:Set("desync", "a", 1); CI:Set("desync", "b", 2)

        -- Corrupt the head node's forward link, then touch it via Get (-> MoveToTail).
        local cache = CI.caches["desync"]
        cache.data["a"].next = nil

        T.no_raise(function() CI:Get("desync", "a") end)
        T.not_nil(cache.head, "head survives a MoveToTail on a desynced node")
        T.eq(CI:GetSize("desync"), 2)

        -- Eviction still works, i.e. the list is not stranded.
        CI:Register("desync", { maxSize = 1 })
        CI:PruneIncremental("desync", 100)
        T.eq(CI:GetSize("desync"), 1, "maxSize is still enforceable afterwards")
    end)
end)

T.describe("CacheInterface PruneIncremental", function()
    T.it("drops expired entries within the budget", function()
        CI:Register("pi1", { ttl = 60 })
        mock.setClock(1000)
        CI:Set("pi1", "old", 1)
        mock.setClock(1000 + 120)
        CI:Set("pi1", "fresh", 2)

        local pruned = CI:PruneIncremental("pi1", 100)
        T.eq(pruned, 1)
        T.is_nil(CI:Get("pi1", "old"))
        T.eq(CI:Get("pi1", "fresh"), 2)
    end)

    T.it("enforces maxSize even when entries have not expired", function()
        CI:Register("pi2", { maxSize = 5 })
        for i = 1, 5 do CI:Set("pi2", "k" .. i, i) end
        -- Shrink the cap the way a re-Register would.
        CI:Register("pi2", { maxSize = 2 })

        CI:PruneIncremental("pi2", 100)
        T.eq(CI:GetSize("pi2"), 2)
        -- Oldest go first, so the two newest survive.
        T.eq(CI:Get("pi2", "k5"), 5)
        T.eq(CI:Get("pi2", "k4"), 4)
    end)
end)

return T

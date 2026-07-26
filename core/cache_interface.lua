-- core/cache_interface.lua
-- Unified cache abstraction layer with O(1) LRU optimization

local addonName, TRP3FW = ...

TRP3FW.CacheInterface = {
    caches = {}
}

-- ===================== Linked List Helpers (O(1)) =====================

local function RemoveNode(cache, key)
    local node = cache.data[key]
    if not node then return end

    local prevKey = node.prev
    local nextKey = node.next

    if prevKey then
        cache.data[prevKey].next = nextKey
    else
        cache.head = nextKey -- Removing head
    end

    if nextKey then
        cache.data[nextKey].prev = prevKey
    else
        cache.tail = prevKey -- Removing tail
    end

    cache.data[key] = nil
    cache.size = cache.size - 1
end

local function AddToTail(cache, key, value, now)
    local node = {
        key = key,
        value = value,
        timestamp = now,
        prev = cache.tail,
        next = nil
    }

    if cache.tail then
        cache.data[cache.tail].next = key
    else
        cache.head = key -- First node
    end

    cache.tail = key
    cache.data[key] = node
    cache.size = cache.size + 1
end

local function MoveToTail(cache, key)
    local node = cache.data[key]
    if not node or key == cache.tail then return end -- Already at tail

    local prevKey = node.prev
    local nextKey = node.next

    -- H1: defensive — the early return at the top covers `key == tail` (which implies
    -- nextKey == nil), so under correct invariants nextKey is never nil here. Guard
    -- anyway in case the list falls out of sync (partial Clear, interleaved
    -- Remove/iterate), but bail BEFORE mutating anything: the previous version
    -- detached the prev side first and only then returned, which left the node
    -- orphaned — unlinked from its predecessor but never re-attached at the tail —
    -- and, when prevKey was nil, set cache.head = nil while cache.size stayed > 0.
    -- That permanently breaks head-based eviction (Set and PruneIncremental both
    -- evict via cache.head), so the cache would grow past maxSize forever. Bailing
    -- early leaves the list exactly as it was found.
    if not nextKey then return end

    -- Detach
    if prevKey then
        cache.data[prevKey].next = nextKey
    else
        cache.head = nextKey
    end
    cache.data[nextKey].prev = prevKey

    -- Attach at tail
    node.prev = cache.tail
    node.next = nil
    cache.data[cache.tail].next = key
    cache.tail = key
end

-- ===================== Interface =====================

-- Register a new cache
function TRP3FW.CacheInterface:Register(name, options)
    if self.caches[name] then
        -- Silent update of options if already exists, no need to warn in production
        self.caches[name].options = options or {}
        TRP3FW:Debug("[CacheInterface] Updated options for cache: "..tostring(name), "cache")
        return
    end

    self.caches[name] = {
        data = {},      -- Hash map: [key] -> Node
        head = nil,     -- Key of oldest node
        tail = nil,     -- Key of newest node
        size = 0,
        options = options or {},
        stats = {hits = 0, misses = 0}
    }
    TRP3FW:Debug("[CacheInterface] Registered cache: "..tostring(name), "cache")
end

-- Get value from cache (updates LRU)
function TRP3FW.CacheInterface:Get(name, key)
    local cache = self.caches[name]
    if not cache then return nil, "unknown_cache" end

    local node = cache.data[key]
    if not node then
        cache.stats.misses = cache.stats.misses + 1
        return nil, "miss"
    end

    -- Check TTL
    if cache.options.ttl then
        local age = TRP3FW:GetCurrentTime() - node.timestamp
        if age >= cache.options.ttl then
            RemoveNode(cache, key)
            cache.stats.misses = cache.stats.misses + 1
            return nil, "expired"
        end
    end

    -- Hit: update LRU position
    MoveToTail(cache, key)
    cache.stats.hits = cache.stats.hits + 1
    return node.value, "hit"
end

-- Set value in cache (updates LRU, enforces size)
function TRP3FW.CacheInterface:Set(name, key, value)
    local cache = self.caches[name]
    if not cache then return false end

    local now = TRP3FW:GetCurrentTime()

    if cache.data[key] then
        -- Update existing
        cache.data[key].value = value
        cache.data[key].timestamp = now
        MoveToTail(cache, key)
    else
        -- Add new
        AddToTail(cache, key, value, now)

        -- Enforce size limit (O(1) eviction of head)
        if cache.options.maxSize and cache.size > cache.options.maxSize then
            if cache.head then
                RemoveNode(cache, cache.head)
            end
        end
    end

    return true
end

-- Get cache size
function TRP3FW.CacheInterface:GetSize(name)
    local cache = self.caches[name]
    return cache and cache.size or 0
end

-- Clear a specific cache
function TRP3FW.CacheInterface:Clear(name)
    local cache = self.caches[name]
    if cache then
        cache.data = {}
        cache.head = nil
        cache.tail = nil
        cache.size = 0
        cache.stats = {hits = 0, misses = 0}
        cache.pruneCursorKey = nil
        TRP3FW:Debug("[CacheInterface] Cleared cache: "..tostring(name), "cache")
    end
end

-- Peek at value without updating LRU (for debug/inspection)
function TRP3FW.CacheInterface:Peek(name, key)
    local cache = self.caches[name]
    if not cache or not cache.data[key] then return nil end
    return cache.data[key].value
end

-- Get iterator for cache (newest to oldest)
function TRP3FW.CacheInterface:Iterator(name)
    local cache = self.caches[name]
    if not cache then return function() return nil end end

    local current = cache.tail
    return function()
        if not current then return nil end
        local key = current
        -- Removing entries while iterating is a natural thing for a caller to do,
        -- and would leave `current` pointing at a key that no longer exists. Stop
        -- cleanly instead of indexing nil.
        local node = cache.data[key]
        if not node then
            current = nil
            return nil
        end
        current = node.prev
        return key, node.value
    end
end

-- Prune expired entries from a cache (O(n))
function TRP3FW.CacheInterface:Prune(name)
    local cache = self.caches[name]
    if not cache or not cache.options.ttl then return 0 end

    local now = TRP3FW:GetCurrentTime()
    local ttl = cache.options.ttl
    local pruned = 0

    -- `>=`, matching Get's expiry test (:125) and every TTL consumer in the codebase, all of
    -- which treat age == ttl as already expired. Prune used a strict `>`, so an entry at
    -- exactly the boundary was unreachable via Get (which reports it expired) yet retained by
    -- a prune pass -- a slot held for a value nothing could ever read.
    for key, node in pairs(cache.data) do
        if (now - node.timestamp) >= ttl then
            RemoveNode(cache, key)
            pruned = pruned + 1
        end
    end
    return pruned
end

-- Remove a specific key (used by cache maintenance helpers)
function TRP3FW.CacheInterface:Remove(name, key)
    local cache = self.caches[name]
    if not cache or not cache.data[key] then
        return false
    end
    RemoveNode(cache, key)
    return true
end

-- Incremental prune: trims expired entries with a fixed budget and enforces maxSize strictly
function TRP3FW.CacheInterface:PruneIncremental(name, budget)
    local cache = self.caches[name]
    if not cache then return 0 end

    budget = budget or 100
    local ttl = cache.options.ttl
    local now = ttl and TRP3FW:GetCurrentTime() or nil
    local pruned = 0
    local processed = 0

    local cursorKey = cache.pruneCursorKey
    -- If cursor is invalid or nil, start from head (LRU)
    if not cursorKey or not cache.data[cursorKey] then
        cursorKey = cache.head
    end

    while processed < budget and cursorKey do
        local node = cache.data[cursorKey]
        -- Capture next key BEFORE potentially removing current node
        local nextKey = node.next

        processed = processed + 1

        -- `>=` for the same reason as Prune above: align with Get's boundary.
        if ttl and node.timestamp and (now - node.timestamp) >= ttl then
            RemoveNode(cache, cursorKey)
            pruned = pruned + 1
        end

        cursorKey = nextKey
    end

    cache.pruneCursorKey = cursorKey

    -- Enforce strict cap even if callers skipped Set-based eviction
    local maxSize = cache.options.maxSize
    if maxSize and cache.size > maxSize then
        while cache.size > maxSize and cache.head do
            RemoveNode(cache, cache.head)
            pruned = pruned + 1
        end
    end

    return pruned
end
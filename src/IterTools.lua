local IterTools = {}

--[=[
    @class Iterator
    Largely inspired by and based on the [iterator](https://doc.rust-lang.org/std/iter/trait.Iterator.html) trait from rust.
    It should be noted that iterators ***ALWAYS*** stop upon reaching a nil value
    (i.e. [Iterator:map] returns `nil`).
    If one desires an iterator that can go over "nil" values, consider using
    something like an option value container.

    Additionally, errors that occur in coroutines are always bubbled up. This is for the sake of catching errors
    and debugging them during development, as coroutines can allow your program to silently fail.
]=]
local Iterator = {}
export type Iterator = typeof(Iterator) & {thread: thread}

-- Metatable info
Iterator.__index = Iterator
function Iterator:__iter<T...>() : () -> T...
    return function()
        return self:next()
    end
end
function Iterator:__call()
    return self:next()
end

-- Constructors

--- `init` should take no arguments as the state is self-contained
--- within the context the function is defined or within the function itself.
function Iterator.new<T...>(init: thread | () -> (T...))
    local co: thread =
        if type(init) == "thread" then
            init
        elseif type(init) == "function" then
            coroutine.create(init)
        else
            error(`init must be a function or coroutine, traceback:\n{debug.traceback(nil, 2)}`)
    
    return setmetatable({thread = co}, Iterator)
end

--- Should hopefully be compatible with most iterators, however
--- I am dumb, so there's probably a lot of cases that I haven't covered.
--- Consider using [Iterator.new] directly.
function Iterator.intoIter<T, U, S>(gen: (S, ...T) -> U, state: S, ...: T)
    local initialVarArgs = {...}
    return Iterator.new(function()
        local r = {gen(state, table.unpack(initialVarArgs))}
        while next(r) ~= nil do
            coroutine.yield(table.unpack(r))
            r = {gen(state, table.unpack(r))}
        end
    end)
end

type Iterable<State, Index, Return> = {__iter: ((Iterable<State, Index, Return>) -> ((State?, Index?) -> Return, State?, Index?))?}
--- If `__iter` metamethod is defined, assumes
--- `__iter(obj)` returns tuple `gen, state, index`.
--- Defaults to `for k, v in obj`.
function Iterator.objIntoIter<S, I, R>(obj: Iterable<S, I, R>)
    local metatable = getmetatable(obj)
    if metatable and metatable.__iter then
        local gen, state, index = obj:__iter()
        if type(gen) ~= "function" then return Iterator.objIntoIter(gen) end
        return Iterator.new(function()
            local r = {gen(state, index)}
            while next(r) ~= nil do
                coroutine.yield(table.unpack(r))
                r = {gen(state, r[1])}
            end
            return nil
        end)
    end
    -- t uses "standard" iteration
    return Iterator.new(function()
        for k, v in obj do
            coroutine.yield(k, v)
        end
        return nil
    end)
end

local __IteratorCallConstructValidTypes = {["thread"] = true, ["function"] = true, ["table"] = true}
--- Implementation of `getmetatable(Iterator).__call`,
--- `Iterator` being the module itself, not a constructed one.
--- Resolves to [Iterator.new] for coroutines and functions
--- and [Iterator.objIntoIter] for tables.
function Iterator:__callConstruct<T..., U...>(arg: {__iter: ((U...) -> T...)?} | thread | () -> (T...))
    local argType = type(arg)
    assert(__IteratorCallConstructValidTypes[argType], `Attempt to construct an iterator from type {argType}`)
    if argType == "thread" or argType == "function" then
        return Iterator.new(arg)
    end
    return Iterator.objIntoIter(arg)
end

setmetatable(Iterator, {
    __call = Iterator.__callConstruct
})

-- General methods

function Iterator:exhausted()
    return coroutine.status(self.thread) == "dead"
end

function Iterator:next<T...>() : T...
    if self:exhausted() then return nil end
    local result = {coroutine.resume(self.thread)}

    if not result[1] then
        error(`Error occurred in Iterator {result[2]}, traceback: {debug.traceback(nil, 2)}`)
    end
    return table.unpack(result, 2)
end

--- Used within iterators that need to check
--- if [Iterator:next] returned an empty tuple
function Iterator:nextPacked()
    local result = {self:next()}
    if next(result) == nil then
        return nil
    end
    return result
end

--- Used within iterators for optional yielding if
--- resuming returns `nil`.
function Iterator:optionYieldNext()
    if self:exhausted() then return end
    local result = {coroutine.resume(self.thread)}
    if not result[1] then
        error(`Error occurred in Iterator {result[2]}, traceback: {debug.traceback(nil, 2)}`)
    end
    if next(result, 1) ~= nil then
        coroutine.yield(table.unpack(result))
    end
end

-- Consuming methods

function Iterator:consume() : ()
    while not self:exhausted() do
        self:next()
    end
end

--[=[
    It's important to note that for the sake of consistency, this function returns a
    list of lists containing the return values `{{T...}}`.
    If you know the iterator only returns one or two values,
    or you only plan on using the first or second value,
    consider using [Iterator:collectList] or [Iterator:collectDict],
    or otherwise use [Iterator:collectFunc] to collect in a customized manner
]=]
function Iterator:collect<T...>() : {{T}}
    local collected = {}
    local result = self:nextPacked()
    while result do
        table.insert(collected, result)
        result = self:nextPacked()
    end
    return collected
end

function Iterator:collectList<T>() : {T}
    local collected = {}
    for k in self do
        table.insert(collected, k)
    end
    return collected
end

-- selene: allow(manual_table_clone)
--- Note that repeated key values will be overwritten;
--- use the general [Iterator:collect] method
--- if non-unique values are returned first by the iterator
function Iterator:collectDict<T, U>() : {[T]: U}
    local collected = {}
    for k, v in self do
        collected[k] = v
    end
    return collected
end

--- `func` should be a function that consumes the iterator
--- and turns it into your desired structure or result
function Iterator:collectFunc<T, U>(func: (T) -> U) : U
    return func(self)
end

--- Consumes the iterator and returns number of values contained
function Iterator:count()
    local count = 0
    for _ in self do
        count += 1
    end
    return count
end

--- Consume iterator and returns sum of values.
--- @error This function will error if the values do not implement __add.
function Iterator:sum()
    local sum = 0
    for n in self do
        sum = sum + n
    end
    return sum
end

--- Consume iterator and returns product of values.
--- @error This function will error if the values do not implement __mul.
function Iterator:product()
    local sum = self:next()
    for n in self do
        sum = sum * n
    end
    return sum
end

--- Consume iterator and concatenates all values.
--- Concats `sep` after concatenating.
--- @error This function will error if the values do not implement __concat.
function Iterator:concat(sep: string?)
    sep = sep or ""
    local concatenated = self:next() or ""
    for v in self do
        concatenated = concatenated .. sep .. v
    end
    return concatenated
end

--- Goes over iterator and transforms `init` using `func`
function Iterator:fold<T, U...>(init: T, func: (T, U...) -> T)
    local args = self:nextPacked()
    while args do
        init = func(init, table.unpack(args))
        args = self:nextPacked()
    end
    return init
end

--- Returns `nil` if `n` is greater than the iterator's length.
--- Note that, just like standard lists in lua,
--- the iterators in this module begin indexing at 1.
--- @error Invalid Type -- `n` must be positive integer
--- @error Out of Bounds -- `n > 0` must resolve to true
function Iterator:nth<T...>(n: number) : T...
    assert(n > 0 and math.round(n) == n, `Attempt to get index {n} of iterator; n must be a positive integer greater than 0`)
    return Iterator.new(function()
        local count = 0
        while not self:exhausted() and count < n do
            count += 1
            if count == n then
                return self:next()
            end
            self:next()
        end
        return nil
    end)
end

--- Returns `nil` if the iterator is empty
function Iterator:last()
    local previous = self:nextPacked()
    while true do
        local nextVal = self:nextPacked()
        if nextVal == nil then
            break
        end
        previous = nextVal
    end
    if previous then
        return table.unpack(previous)
    end
    return nil
end

---@return boolean
function Iterator:any<T>(predicate: (T) -> boolean)
    while not self:exhausted() do
        local packed = self:nextPacked()
        if not packed then break end
        if predicate(table.unpack(packed)) then return true end
    end
    return false
end

function Iterator:all<T>(predicate: (T) -> boolean) : boolean
    while not self:exhausted() do
        local packed = self:nextPacked()
        if not packed then break end
        if predicate(table.unpack(packed)) then continue end
        return false
    end
    return true
end

-- Adapting methods

function Iterator:foreach<T...>(func: (T...) -> ())
    return Iterator.new(function()
        local returns = self:nextPacked()
        while returns do
            func(table.unpack(returns))
            coroutine.yield(table.unpack(returns))
            returns = self:nextPacked()
        end
        return nil
    end)
end

--- Note that table converters will only consider the first return type as the index.
--- # Example: Default Values for Table Converters
--- When using a function converter that's essentially a wrapper for a table converter
--- for getting either the table value or a default implementation, you could instead use a table
--- with __index defined to return a default value.
--- ```lua
--- -- Developer/Special are some other function
--- local SpecialUsers = {"Developer" = Developer, "John" = Special, "Jane" = Special}
--- setmetatable(SpecialUsers, {__index = function(_, name: string) return Normal(name) end)})
--- local users = Iterator.objIntoIter(System:GetUserNames()):map(SpecialUsers):collect()
--- ```
--- This concept can be used for other converters and predicates, e.g. [Iterator:filter].
function Iterator:map<T, U>(converter: {[T]: U} | (...T) -> (...U))
    if type(converter) == "function" or (type(converter) == "table" and getmetatable(converter) and getmetatable(converter).__call ~= nil) then
        return Iterator.new(function()
            local returns = self:nextPacked()
            while returns do
                coroutine.yield(converter(table.unpack(returns)))
                returns = self:nextPacked()
            end
            return nil
        end) 
    end
    return Iterator.new(function()
        local _, value = coroutine.resume(self.thread)
        while value ~= nil do
            coroutine.yield(converter[value])
            _, value = coroutine.resume(self.thread)
        end
        return nil
    end)
end

--- Note that table predicates will only consider the first return type as the index.
function Iterator:filter<T>(predicate: {[T]: boolean} | (T) -> boolean)
    if type(predicate) == "function" or (type(predicate) == "table" and getmetatable(predicate) and getmetatable(predicate).__call ~= nil) then
        return Iterator.new(function()
            local returns = self:nextPacked()
            while returns do
                if predicate(table.unpack(returns)) then
                    coroutine.yield(table.unpack(returns))
                end
                returns = self:nextPacked()
            end
            return nil
        end) 
    end
    return Iterator.new(function()
        local returns = self:nextPacked()
        while returns do
            if predicate[returns[1]] then
                coroutine.yield(table.unpack(returns))
            end
            returns = self:nextPacked()
        end
        return nil
    end)
end

--- `filter` should return `nil` for values that should be filtered out
function Iterator:filterMap<T, U>(filter: (T) -> U?)
    return Iterator.new(function()
        local returns = self:nextPacked()
        while returns do
            local filtered = {filter(table.unpack(returns))}
            if next(filtered) ~= nil then
                coroutine.yield(table.unpack(filtered))
            end
            returns = self:nextPacked()
        end
        return nil
    end)
end

--- prepends `startIndex + n` to the iterator's return value,
--- `startIndex` defaulting to 1 and `n` being the iterator's
--- current number of iterations since starting to enumerate
function Iterator:enumerate(startIndex: number?)
    return Iterator.new(function()
        startIndex = startIndex or 1
        local results = self:nextPacked()
        while results do
            coroutine.yield(startIndex, table.unpack(results))
            startIndex = startIndex + 1
            results = self:nextPacked()
        end
        return nil
    end)
end

--- Returns an iterator that removes the first `n` values of a given
--- iteration step, i.e. `(a, b) -> (b)`, `(a, b, c, d) -> (c, d)`.
--- `n` defaults to 1.
--- Note that truncating an iterator with number `n` such that
--- `n` is equal to the number of return values or is negative will
--- cause the iterator to be immediately consumed, as it uses
--- `table.unpack({results}, n + 1)`.
function Iterator:truncate(n: number?)
    return Iterator.new(function()
        n = n or 1
        local results = self:nextPacked()
        while results do
            coroutine.yield(table.unpack(results, n + 1))
            results = self:nextPacked()
        end
        return nil
    end)
end

--- Returns an iterator that will iterate up to
--- `n` times, or the length of the underlying iterator,
--- whichever one is lower. This should be used in combination
--- with unsized iterators to ensure they do not run endlessly,
--- if that behavior is not desired.
--- @error Invalid Type -- `n` must be positive integer
--- @error Out of Bounds -- `n > 0` must resolve to true
function Iterator:take(n: number)
    assert(n > 0 and math.round(n) == n, `Attempt to take {n} iterations; n must be a positive integer greater than 0`)
    return Iterator.new(function()
        local count = 0
        while not self:exhausted() and count < n do
            count += 1
            self:optionYieldNext()
        end
        return nil
    end)
end

--- Unlike [Iterator:filter], stops at the first instance at which `predicate` resolves to false
function Iterator:iterWhile<T>(predicate: {[T]: boolean} | (T) -> boolean)
    if type(predicate) == "function" or (type(predicate) == "table" and getmetatable(predicate) and getmetatable(predicate).__call ~= nil) then
        return Iterator.new(function()
            local returns = self:nextPacked()
            while returns and predicate(table.unpack(returns)) do
                coroutine.yield(table.unpack(returns))
                returns = self:nextPacked()
            end
            return nil
        end) 
    end
    return Iterator.new(function()
        local returns = self:nextPacked()
        while returns and predicate[returns[1]] do
            coroutine.yield(table.unpack(returns))
            returns = self:nextPacked()
        end
        return nil
    end)
end

function Iterator:skipWhile<T>(predicate: {[T]: boolean} | (T) -> boolean)
    if type(predicate) == "function" or (type(predicate) == "table" and getmetatable(predicate) and getmetatable(predicate).__call ~= nil) then
        return Iterator.new(function()
            local returns = self:nextPacked()
            while returns and predicate(table.unpack(returns)) do
                returns = self:nextPacked()
            end
            while returns do
                coroutine.yield(table.unpack(returns))
                returns = self:nextPacked()
            end
            return nil
        end) 
    end
    return Iterator.new(function()
        local returns = self:nextPacked()
        while returns and predicate[returns[1]] do
            returns = self:nextPacked()
        end
        while returns do
            coroutine.yield(table.unpack(returns))
            returns = self:nextPacked()
        end
        return nil
    end)
end

--- Transforms an iterator of lists into an iterator
--- of each list's items, i.e. `{{a, b, c}, {d, e}}`
--- is transformed into {a, b, c, d, e}
function Iterator:flattenList()
    return Iterator.new(function()
        for list in self do
            local subIterator = Iterator.objIntoIter(list)
            for k, v in subIterator do
                coroutine.yield(k, v)
            end
        end
    end)
end

-- Adapters that require consuming the iterator
-- These methods are not recommended for iterating over LARGE structures
-- Additionally, they will likely silently fail
-- for iterators with infinite size

--- Consumes the iterator and iterates in reverse
function Iterator:reverse()
    return Iterator.new(function()
        local c = self:collect()
        for _, packed in c do
            coroutine.yield(table.unpack(packed))
        end
        return nil
    end)
end

--- Collects iterator into `collected` using [Iterator:collectList]
--- and returns an iterator over table.sort(`collected`, `comp`).
function Iterator:sortList<T>(comp: ((T, T) -> boolean)?)
    return Iterator.new(function()
        local collected = self:collectList()
        table.sort(collected, comp)
        for _i, v in collected do
            coroutine.yield(v)
        end
    end)
end

-- Combining methods

function Iterator:chain(...: Iterator)
    local others: {Iterator} = {...}
    return Iterator.new(function()
        repeat
            self:optionYieldNext()
        until self:exhausted()
        -- repeat
        --     other:optionYieldNext()
        -- until other:exhausted()
        for _, other in others do
            repeat
                other:optionYieldNext()
            until other:exhausted()
        end
        return nil
    end)
end

--- Takes `Iterator<A>` and `Iterator<B>`,
--- retrieving their first return values `(A1, B1)`
--- and create's `Iterator<A1, B1>` that is as long
--- as the shorter iterator
function Iterator:zip(other: Iterator)
    return Iterator.new(function()
        local a = self:next()
        local b = other:next()
        while a ~= nil and b ~= nil do
            coroutine.yield(a, b)
            a = self:next()
            b = other:next()
        end
        return nil
    end)
end

--- Similar to [Iterator:zip], however allows
--- for combining based on the n > 1 results of
--- iterators A and B by packing their values into lists
function Iterator:combine<A, B, C>(other: Iterator, combiner: ({A}, {B}) -> C)
    return Iterator.new(function()
        local a = self:nextPacked()
        local b = other:nextPacked()
        while a and b do
            coroutine.yield(combiner(a, b))
            a = self:nextPacked()
            b = other:nextPacked()
        end
    end)
end

IterTools.Table = {}
IterTools.List = {}

-- Iterates over list in reverse order
function IterTools.List.Reverse<T>(list: {T})
    return Iterator.new(function()
        local index = #list
        while index > 0 do
            coroutine.yield(index, list[index])
            index -= 1
        end
        return nil
    end)
end

function IterTools.List.Values<T>(list: {T})
    return Iterator.new(function()
        for _, v in ipairs(list) do
            coroutine.yield(v)
        end
        return nil
    end)
end

function IterTools.Table.Keys<K>(dict: {[K]: any})
    return Iterator.new(function()
        for k, _v in pairs(dict) do
            coroutine.yield(k)
        end
        return nil
    end)
end

function IterTools.Table.Values<V>(dict: {[any]: V})
    return Iterator.new(function()
        for _k, v in pairs(dict) do
            coroutine.yield(v)
        end
        return nil
    end)
end

--- Returns an iterator that goes over all numeric indices of a table
--- in ascending order regardless of whether or not the keys contiguous.
--- Note that this must iterate through all keys up front, and as such,
--- `ipairs` should be preferred if possible
function IterTools.Table.SparseArrayOrdered<V>(tbl: {[number]: V})
    local indices = {}
    for k in pairs(tbl) do
        if typeof(k) == "number" then
            table.insert(indices, k)
        end
    end
    table.sort(indices)

    return Iterator.new(function()
        for _, index in ipairs(indices) do
            coroutine.yield(tbl[index])
        end
        return nil
    end)
end

function IterTools.FromTuple<T...>(...: T...)
    return IterTools.List.Values({...})
end

-- To facilitate creating custom iterators outside of this module
IterTools.CreateCustom = Iterator.new
IterTools.ObjIntoIter = Iterator.objIntoIter
IterTools.IntoIter = Iterator.intoIter

return IterTools
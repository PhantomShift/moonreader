local IterTools = if game then require(script.Parent.IterTools) else require("src/IterTools")

local StringUtils = {}

function StringUtils.IterChars(s: string)
    return IterTools.CreateCustom(function()
        for i = 1, s:len() do
            coroutine.yield(s:sub(i, i))
        end
        return nil
    end)
end

function StringUtils.IterLines(s: string)
    return IterTools.CreateCustom(function()
        for match in s:gmatch("(.-)[\n\r]") do
            coroutine.yield(match)
        end
        coroutine.yield(s:match("[^\n\r]+$"))
        return nil
    end)
end

-- Based on Norman Ramsey's implementation on stackoverflow
-- https://stackoverflow.com/a/1647577
function StringUtils.IterSplit(s: string, pattern: string, returnIndex: boolean?)
    return IterTools.CreateCustom(function()
        local index = 1
        for delta, capture in s:gmatch(`()({pattern})`) do
            coroutine.yield(s:sub(index, delta - 1), returnIndex and index)
            index = delta + capture:len()
        end
        local last = s:sub(index, s:len())
        if last:len() > 0 then
            coroutine.yield(last, returnIndex and index)
        end
        return nil
    end)
end

function StringUtils.MatchRepeated(s: string, pattern: string, sep: string?, init: number?)
	init = init or 0
	local front, back = s:find(pattern, init)
	local initialFront = front
	local collected = {}
	while front do
		table.insert(collected, s:sub(front, back))
		local newFront, newBack = s:find(pattern, back)
		front = newFront
		if front and front - back < 3 then
			back = newBack
		else
			front = nil
		end
	end
	if #collected > 0 then
		return table.concat(collected, sep), initialFront, back
	end
	return nil, initialFront, back
end

function StringUtils.GMatchRepeated(s: string, pattern: string, sep: string?)
	local match, front, back = StringUtils.MatchRepeated(s, pattern, sep, 0)
	local co = coroutine.create(function()
		while match do
			coroutine.yield(match, front, back)
			match, front, back = StringUtils.MatchRepeated(s, pattern, sep, back)
		end
		return nil
	end)
	return function()
		return select(2, coroutine.resume(co))
	end
end

-- Note that this function truncates the window rather than ending iteration when the window is less than given size
function StringUtils.StringWindows(s: string, size: number)
    size = size or 1
    if size < 1 then error(("StringWindows requires a size greater than 0, %s"):format(debug.traceback())) end
    local index = 0
    local co = coroutine.create(function()
        while index < s:len() do
            index += 1
            coroutine.yield(index, s:sub(index, index + size - 1))
        end
        return nil
    end)
    return function()
        return select(2, coroutine.resume(co))
    end
end

local DEPTH_INCREASE = {["{"] = true, ["("] = true}
local DEPTH_DECREASE = {["}"] = true, [")"] = true}
function StringUtils.SplitTopDepth(s: string, sep: string)
    -- This function is potentially expensive for long strings; first check if there's any need to worry about depth
    local hasDepth = false
    for indicator in pairs(DEPTH_INCREASE) do
        if s:find(indicator, 0, true) then
            hasDepth = true;
            break
        end
    end
    if not hasDepth then return s:split(sep) end
    local result: {string} = {}
    local depth = 0
    local lastIndex = 0
    for i: number, sub: string in StringUtils.StringWindows(s, sep:len()) do
        local firstChar = sub:sub(1, 1)
        if DEPTH_INCREASE[firstChar] then
            depth += 1
        elseif DEPTH_DECREASE[firstChar] then
            depth -= 1
        elseif sub == sep and depth == 0 then
            table.insert(result, s:sub(lastIndex, i - 1))
            lastIndex = i + sep:len()
        end
    end
    if #result == 0 then
        table.insert(result, s)
    elseif depth == 0 then
        table.insert(result, s:sub(lastIndex, -1))
    end

    return result
end

-- Right side is `nil` if `sep` is never found
function StringUtils.SplitOnce(s: string, sep: string, init: number?)
    init = (init or 0) % s:len()
    local sepFirst, sepLast = s:find(sep, init, true)
    if sepFirst == nil then
        return s
    end
    return s:sub(1, sepFirst - 1), s:sub(sepLast + 1, -1)
end

function StringUtils.TrimWhitespace(s: string)
    return s:match("^%s*(.*)%s*$") or ""
end

function StringUtils.RemoveWhitespace(s: string)
    return s:gsub("%s", "")
end

local function ContiguousMatchingLines(s: string, pat: string)
	local builder = {}
	local current = {}
	local prevMatched = false
	-- BECAUSE I LOVE ROBLOX LUA SOURCE CONTAINERS
	local nilCount = 0
	for line in StringUtils.IterLines(s) do
		if line:match(pat) then
			nilCount = 0
			if prevMatched then
				table.insert(current, line)
			else
				prevMatched = true
				current = {line}
			end
		else
			if line:len() == 0 then
				nilCount += 1
				if nilCount == 2 then
					nilCount = 0
				else
					continue
				end
			end
			if prevMatched then
				--print(line, line:len(), "lol")
				prevMatched = false
				table.insert(builder, table.concat(current, "\n"))
			end
		end
	end
	if next(current) ~= nil then
		table.insert(builder, table.concat(current, "\n"))
	end
	
	return builder
end

-- Inspired by https://devforum.roblox.com/t/how-to-tell-when-a-text-box-wraps-text/815022/5
function StringUtils.GetRichTextPositionBounds(textContainer: TextButton | TextBox | TextLabel, position: number)
	local screengui = Instance.new("ScreenGui")
	screengui.Archivable = false
	local clone = textContainer:Clone()
	clone.Archivable = false
	clone.Size = UDim2.fromOffset(textContainer.AbsoluteSize.X, textContainer.AbsoluteSize.Y)
	clone.Parent = screengui
	screengui.Parent = game:GetService("StarterGui")

	local text = textContainer.Text:sub(1, position)
	local lastSizeNumber, lastSizeString = IterTools.IntoIter(text:gmatch(`<font.->`))
		:enumerate()
		:filter(function(_i: number, match: string)
			return match:match(`size="%d+"`)
		end)
		:last()
	local lastFontOpenNumber = IterTools.IntoIter(text:gmatch(`<font.->`)):count()
	local lastFontCloseNumber = IterTools.IntoIter(text:gmatch(`</font>`)):count()
	local lineHeight = if lastSizeString and lastSizeNumber == lastFontOpenNumber and lastSizeNumber ~= lastFontCloseNumber then tonumber(lastSizeString:match("%d+")) else textContainer.TextSize

	local tags = {}
	local counts = {}
	for open in text:gmatch("<(%w+).->") do
		table.insert(tags, open)
		if not counts[open] then
			counts[open] = 1
		else
			counts[open] += 1
		end
	end
	for _, tag in IterTools.List.Reverse(tags) do
		local closes = IterTools.IntoIter(text:gmatch(`</{tag}>`)):count()
		if counts[tag] > closes then
			text ..= `</{tag}>`
		end
	end

	clone.Text = text
	local positionBounds = clone.TextBounds

	clone:Destroy()
	screengui:Destroy()

	return positionBounds, lineHeight
end

local RichTextEscapes = {
	["<"] = "&lt;",
	[">"] = "&gt;",
	["\""] = "&quot;",
	["'"] = "&apos;",
	["&"] = "&amp;";
}
setmetatable(RichTextEscapes, {__index = function(_self, index) return index end})

local MagicCharacters = {
	["("] = true,
	[")"] = true,
	["."] = true,
	["%"] = true,
	["+"] = true,
	["-"] = true,
	["*"] = true,
	["?"] = true,
	["["] = true,
	["^"] = true,
	["$"] = true,
}
local function cleanMagicChar(s: string)
	if MagicCharacters[s] then
		return `%{s}`
	end
	return s 
end
-- Note that it does not support newlines/linebreaks
function StringUtils.FindInRichText(text: string, query: string, init: number?, caseSensitive: boolean?)
	if query == "" then return nil end
	init = init or 1
	text = text:sub(init :: number)
	local processedQuery = query:gsub("[<>\"'&]", RichTextEscapes)
	if not caseSensitive then
		processedQuery = processedQuery:lower()
		text = text:lower()
	end
	local len = text:len()
    local firstCharacter = rawget(RichTextEscapes, query:sub(1, 1)) or processedQuery:sub(1, 1)

    for position: number in text:gmatch(`(){cleanMagicChar(firstCharacter)}`) do
        local eol = math.max(text:match("()\n") or 0, text:match("()<br />") or 0, len)
        local subText = text:sub(position, eol)

        if (subText:match("()>") or 0) < (subText:match("()<") or 0) then
            continue -- currently within a tag
        end

        local inTag = false
        local length = 0
        local foundLength = 0
        local found = StringUtils.IterChars(subText):filterMap(function(char)
            length += 1
            if char == ">" then
                inTag = false
                return nil
            elseif char == "<" then
                inTag = true
                return nil
            end
            if not inTag then
                return char
            end
        end):zip(StringUtils.IterChars(processedQuery))
            :iterWhile(function(a, b)
                if a == b then
                    foundLength += length
                    length = 0
                    return true
                end
            end)
            :concat()
        if found == processedQuery then
            return init + position - 1, init + position + foundLength - 2
        end
    end

    return nil
end

function StringUtils.GSubRepeated(input: string, pattern: string, repl: string | {[string]: string} | (...string) -> string, maxReps: number?)
	maxReps = maxReps or math.huge
	local reps = 1
	local result, substitutions = input:gsub(pattern, repl)
	while substitutions > 0 and reps < maxReps do
		result, substitutions = result:gsub(pattern, repl)
		reps += 1
	end

	return result
end


--- Same functionality as gsub but completely ignores pattern directives
--- by using string.find with `plain` set to `true`.
function StringUtils.ReplacePlain(input: string, find: string, replace)
	local i = 0
	local substitutions = 0
	local result = input

	local repl: (string) -> string = if type(replace) == "function" then replace
		elseif type(replace) == "table" then function(r) return replace[r] end
		else function(_) return replace end
	
	while i < result:len() do
		local start, finish, found = result:find(find, i, true)
		if start == nil then
			break
		end

		local r = repl(found)
		result = result:sub(0, start - 1) .. r .. result:sub(finish + 1)
		i = start + r:len()
		substitutions += 1
	end

	return result, substitutions
end

-- Matches given patterns in order, returning the first one that successfully
-- matches or nil if none of them match.
function StringUtils.MatchMultiple(subject: string, ...: string)
	for _, pattern in {...} do
		if subject:match(pattern) then
			return subject:match(pattern)
		end
	end
	return nil
end

function StringUtils.LastMatch(subject: string, pattern: string)
	local g = subject:gmatch(pattern)
	local matches = {g()}
	while matches[1] do
		local new = {g()}
		if not new[1] then break end
	end
	if matches[1] then
		return table.unpack(matches)
	end
	return nil
end

StringUtils.ContiguousMatchingLines = ContiguousMatchingLines

return StringUtils
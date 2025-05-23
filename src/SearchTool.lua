local StringUtils = require "./StringUtils"
local Garbage = require "./Garbage"

local BaseSearchTool = script.Parent.Assets.Search
type SearchToolUi = typeof(BaseSearchTool)

type SearchCacheImpl = {
	__index: SearchCacheImpl,

	get: (self: SearchCache, case: boolean, input: string) -> { Vector3 },
	set: (self: SearchCache, case: boolean, input: string, value: { Vector3 }) -> (),
	pop: (self: SearchCache) -> { Vector3 }?
}
type SearchCache = typeof(setmetatable(
	{} :: {
		size: 				number,
		maxSize: 			number,
		inputQueue:			{ string },
		caseQueue:			{ boolean },
		caseSensitive: 		{ [string]: { Vector3 } },
		caseInsensitive: 	{ [string]: { Vector3 } },
	},
	{} :: SearchCacheImpl
))
local SearchCacheMethods: SearchCacheImpl = {} :: SearchCacheImpl
SearchCacheMethods.__index = SearchCacheMethods
function SearchCacheMethods:get(case, input)
	local ref = if case then self.caseSensitive else self.caseInsensitive
	return ref[input]
end
function SearchCacheMethods:set(case, input, val)
	local ref = if case then self.caseSensitive else self.caseInsensitive
	table.insert(self.caseQueue, case)
	table.insert(self.inputQueue, input)
	self.size += 1
	if self.size > self.maxSize then
		self:pop()
	end
	ref[input] = val
end
function SearchCacheMethods:pop()
	local case = table.remove(self.caseQueue, 1)
	local input = table.remove(self.inputQueue, 1)
	if case == nil or input == nil then return nil end
	local ref = if case then self.caseSensitive else self.caseInsensitive
	local val = ref[input]
	ref[input] = nil

	return val
end

local DEFAULT_CACHE_SIZE = 10
local function SearchCache(maxSize: number) : SearchCache
	return setmetatable({
		maxSize = maxSize,
		size = 0,
		inputQueue = {},
		caseQueue = {},
		caseSensitive = {},
		caseInsensitive = {}
	}, SearchCacheMethods)
end

type SearchToolImpl = {
	__index: SearchToolImpl,

	SetParent: 		(self: SearchTool, parent: Instance?) -> (),
	FindAll: 		(self: SearchTool, input: string, overrideCache: boolean?) -> { [number]: Vector3, total_found: number },
	Activate:		(self: SearchTool) -> RBXScriptSignal<Vector3>,
	Deactivate: 	(self: SearchTool) -> (),
	SetDocuments:	(self: SearchTool, documents: { string }) -> (),

	new: (documents: { string }) -> SearchTool
}

type SearchTool = typeof(setmetatable(
	{} :: {
		Documents: { string },
		CachedSearches: SearchCache,
		Connections: Garbage.Garbage,
		UiObject: SearchToolUi,
		Active: boolean,
		CaseSensitive: BoolValue
	},
	{} :: SearchToolImpl
))

local SearchTool: SearchToolImpl = {} :: SearchToolImpl
SearchTool.__index = SearchTool

function SearchTool.new(documents: {[number]: string})
	local tool = {
		Documents = documents,
		CachedSearches = SearchCache(DEFAULT_CACHE_SIZE),
		Connections = Garbage.new(),
		UiObject = BaseSearchTool:Clone() :: SearchToolUi,
		Active = false,
		CaseSensitive = Instance.new("BoolValue")
	}

	tool.UiObject.Case.Activated:Connect(function()
		tool.CaseSensitive.Value = not tool.CaseSensitive.Value
		if tool.CaseSensitive.Value then
			tool.UiObject.Case.BackgroundTransparency = 0.5
		else
			tool.UiObject.Case.BackgroundTransparency = 1
		end
	end)

	return setmetatable(tool, SearchTool)
end

function SearchTool:SetParent(parent: Instance?)
	self.UiObject.Parent = parent
end

function SearchTool:FindAll(input: string, overrideCache: boolean?)
	if input == "" then return {total_matches = 0} end
	local cached = self.CachedSearches:get(self.CaseSensitive.Value, input)
	if not overrideCache and cached ~= nil then
		return cached
	end

	local documents = self.Documents :: {[number]: string}
    local found = {}
    local total_matches = 0
    for index, document in pairs(documents) do
        local maximum_matches = document:len()
        local matches = 0
        local front, back = StringUtils.FindInRichText(document, input, nil, self.CaseSensitive.Value)
        while front ~= nil and matches < maximum_matches do
            total_matches += 1
            matches += 1
            table.insert(found, Vector3.new(index, front, back))
            front, back = StringUtils.FindInRichText(document, input, back + 2, self.CaseSensitive.Value)
        end
    end
    found.total_matches = total_matches
	self.CachedSearches:set(self.CaseSensitive.Value, input, found)
	return found
end

function SearchTool:Activate()
	if self.Active then return end
	self.Active = true
	local searchTool = self.UiObject :: typeof(BaseSearchTool)
	local searchIndex = 0

	local lastSearchQuery = ""
	local nextSearchQuery = ""
	local documentPosition = Instance.new("Vector3Value")
	local currentSearchResults = {}  :: {total_matches: number, [number]: Vector3}
	self.Connections.TextChanged = searchTool.TextBoxContainer.TextBox:GetPropertyChangedSignal("Text"):Connect(function()
		nextSearchQuery = searchTool.TextBoxContainer.TextBox.Text
	end)

	local function invokeSearch()
		lastSearchQuery = nextSearchQuery
		currentSearchResults = self:FindAll(nextSearchQuery)
		if currentSearchResults.total_matches > 0 then
			searchIndex = 1
		else
			searchIndex = 0
		end
		documentPosition.Value = currentSearchResults[searchIndex] or Vector3.zero
	end
	self.Connections.CaseToggled = self.CaseSensitive.Changed:Connect(invokeSearch)
	self.Connections.EnterPressed = searchTool.TextBoxContainer.TextBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			invokeSearch()
		end
	end)
	self.Connections.Next = searchTool.Next.Activated:Connect(function()
		searchIndex = math.min(currentSearchResults.total_matches, math.max(1, (searchIndex + 1) % (currentSearchResults.total_matches + 1)))
		documentPosition.Value = currentSearchResults[searchIndex] or Vector3.zero
	end)
	self.Connections.Previous = searchTool.Previous.Activated:Connect(function()
		searchIndex = if searchIndex == 1 then currentSearchResults.total_matches else searchIndex -1
		documentPosition.Value = currentSearchResults[searchIndex] or Vector3.zero
	end)
	self.Connections.Matches = documentPosition.Changed:Connect(function(newIndex)
		if lastSearchQuery == "" then
			searchTool.Matches.Text = ""
		elseif newIndex == Vector3.zero then
			searchTool.Matches.Text = "0 matches"
		else
			searchTool.Matches.Text = `{searchIndex} of {currentSearchResults.total_matches} matches`
		end
	end)
	self.Connections.DocumentPosition = documentPosition

	return documentPosition.Changed
end
function SearchTool:Deactivate()
	if not self.Active then return end
	self.Connections:Sweep()
	self.Active = false
end

function SearchTool:SetDocuments(docs: {[number]: string})
	self:Deactivate()
	self.CachedSearches = SearchCache(DEFAULT_CACHE_SIZE)
	self.Documents = docs
end

return SearchTool
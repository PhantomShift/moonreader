local TextService = game:GetService("TextService")

local StringUtils = require(script.Parent.StringUtils)
local Garbage = require(script.Parent.Garbage)

local BaseSearchTool = script.Parent.Assets.Search
type SearchToolUi = typeof(BaseSearchTool)

local SearchTool = {}
SearchTool.__index = SearchTool

function SearchTool.new(documents: {[number]: string})
	local tool = {
		Documents = documents,
		CachedSearches = {},
		Connections = Garbage.new(),
		UiObject = BaseSearchTool:Clone() :: SearchToolUi,
		Active = false
	}

	-- Making limited-size textboxes follow the position of the cursor
	-- Based partially on the code by user nicemike40 on the devforum
	-- https://devforum.roblox.com/t/how-to-make-textboxes-follow-current-cursor-position/1368429/6
	local container = tool.UiObject.TextBoxContainer
	container.ClipsDescendants = true
	local textBox = container.TextBox
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = container.AbsoluteSize
	container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		sizeConstraint.MinSize = container.AbsoluteSize
	end)
	local padding: UIPadding = textBox.UIPadding
	textBox:GetPropertyChangedSignal("CursorPosition"):Connect(function()
		local cursorPosition = textBox.CursorPosition
		if cursorPosition < 1 then
			-- Unfocused
			textBox.Position = UDim2.new()
		else
			local width = TextService:GetTextSize(
				textBox.Text:sub(1, cursorPosition),
				textBox.TextSize,
				textBox.Font,
				Vector2.new(math.huge, textBox.AbsoluteSize.Y)
			).X
			local totalPadding = padding.PaddingRight.Offset * 2 - padding.PaddingLeft.Offset
			textBox.Position = UDim2.fromOffset(math.min(0, container.AbsoluteSize.X - width - totalPadding), 0)
		end
	end)

	return setmetatable(tool, SearchTool)
end

function SearchTool:SetParent(parent: Instance)
	self.UiObject.Parent = parent
end

function SearchTool:FindAll(input: string, plain: boolean?, overrideCache: boolean?)
	if input == "" then return {total_matches = 0} end
	plain = if plain == nil then true else plain
	assert(type(plain) == "boolean", "plain must be a boolean or nil")
	if self.CachedSearches[input] ~= nil and self.CachedSearches[input][plain] ~= nil and not overrideCache then
		return self.CachedSearches[input][plain]
	end
	if self.CachedSearches[input] == nil or overrideCache then
		self.CachedSearches[input] = {}
	end
	local documents = self.Documents :: {[number]: string}
    local found = {}
    local total_matches = 0
    for index, document in pairs(documents) do
        local maximum_matches = document:len()
        local matches = 0
        local front, back = StringUtils.FindInRichText(document, input, nil, false)
        while front ~= nil and matches < maximum_matches do
            total_matches += 1
            matches += 1
            table.insert(found, Vector3.new(index, front, back))
            front, back = StringUtils.FindInRichText(document, input, back + 2, false)
        end
    end
    found.total_matches = total_matches
	self.CachedSearches[input][plain] = found
	return found
end

function SearchTool:Activate()
	if self.Active then return end
	self.Active = true
	local searchTool = self.UiObject :: typeof(BaseSearchTool)
	local searchIndex = 0

	local nextSearchQuery = ""
	local documentPosition = Instance.new("Vector3Value")
	local currentSearchResults = {}  :: {total_matches: number, [number]: Vector3}
	self.Connections.TextChanged = searchTool.TextBoxContainer.TextBox:GetPropertyChangedSignal("Text"):Connect(function()
		nextSearchQuery = searchTool.TextBoxContainer.TextBox.Text
	end)
	self.Connections.EnterPressed = searchTool.TextBoxContainer.TextBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			currentSearchResults = self:FindAll(nextSearchQuery)
			if currentSearchResults.total_matches > 0 then
				searchIndex = 1
			else
				searchIndex = 0
			end
			documentPosition.Value = currentSearchResults[searchIndex] or Vector3.zero
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
		if currentSearchResults.total_matches == 0 then
			searchTool.Matches.Text = ""
		elseif newIndex == 0 then
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
	self.CachedSearches = {}
	self.Documents = docs
end

return SearchTool
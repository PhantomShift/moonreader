local TextService = game:GetService("TextService")
local ScriptEditorService = game:GetService("ScriptEditorService")

local Parser = require(script.Parent.Parser)
local Markdown = require(script.Parent.Markdown)
local IterTools = require(script.Parent.IterTools)
local Garbage = require(script.Parent.Garbage)

local QuickSearchTool = {}
QuickSearchTool.Containers = {}
QuickSearchTool.CurrentOpen = nil

local QuickSearchUi = script.Parent.Assets.QuickSearch
local Entries = QuickSearchUi.Children
local EntryExample = Entries.__MoonreaderExampleEntry
EntryExample.Visible = false
type QuickSearchContainer = typeof(EntryExample)

local GarbageMan = Garbage.new()

local TWEEN_TIME = 0.5

function QuickSearchTool.AddEntry(entry: Parser.ParsedComment)
	local base = entry.within
	local concatenator = if entry.method then ":" else "."
	local name = entry.method or entry["function"]
	local args = {}
	if entry.param ~= nil then
		for argName, info in pairs(entry.param) do
			local arg = argName
			if info[2] ~= nil then
				arg = arg .. `: {info[2]}`
			end
			args[info.order] = arg
		end
	end
	
	local returnString = if entry["return"] ~= nil then ` : {table.concat(entry["return"], ", ")}` else ""
	local argString = table.concat(args, ", ")
	
	local container = EntryExample:Clone()
	container.Name = base
	container.Visible = true
	container.Expand.Text = `{base}{concatenator}{name}({argString}){returnString}`
	container.Description.Size = UDim2.fromScale(1, 0)

	container.Description.RichText = true
	-- container.Description.TextEditable = false
	if #args > 0 then
		container.Description.Text ..= Markdown("__Params__\n" .. IterTools.List.Values(args):map(function(s: string)
			return "* `" .. s .. "`"
		end):concat("\n"), QuickSearchTool.StyleInfo) .. "<br />"
	end
	if entry["return"] then
		container.Description.Text ..= Markdown("__Returns__\n" .. "`" .. (table.concat(entry["return"], ", ")) .. "`", QuickSearchTool.StyleInfo) .. "<br />"
	end
	if entry.description then
		container.Description.Text ..= Markdown(entry.description, QuickSearchTool.StyleInfo, true)
	end
	
	container.Parent = Entries
	
	GarbageMan[container.Expand] = container.Expand.Activated:Connect(function()
		if QuickSearchTool.CurrentOpen ~= nil then
			if QuickSearchTool.CurrentOpen == container then
				QuickSearchTool.Close(container)
				return
			end
			QuickSearchTool.Close()
		end
		QuickSearchTool.Open(container)
	end)
	GarbageMan[container.GotoSource] = container.GotoSource.Activated:Connect(function()
		local result = ScriptEditorService:OpenScriptDocumentAsync(entry.__source)
		if result == true then
			local doc: ScriptDocument? = ScriptEditorService:FindScriptDocument(entry.__source)
			if doc ~= nil then
				local lineNumber = math.min(
					doc:GetLineCount(),
					1 + IterTools.ObjIntoIter(entry.__source.source:sub(1, entry.__start):gmatch("\n")):count()
				)
				doc:RequestSetSelectionAsync(lineNumber, 1)
			end
		end
	end)
	GarbageMan[container] =  QuickSearchUi:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if container == QuickSearchTool.CurrentOpen then
			local height = TextService:GetTextSize(container.Description.ContentText, container.Description.TextSize, Enum.Font.SourceSans, Vector2.new(container.Description.AbsoluteSize.X, math.huge)).Y
			container.Description:TweenSize(UDim2.new(1, 0, 0, height), nil, nil, TWEEN_TIME, true)
		end
	end)
	table.insert(QuickSearchTool.Containers, container)
end

function QuickSearchTool.Clear()
	for _, child in pairs(Entries:GetChildren()) do
		if child:IsA("GuiBase") and child.Visible then
			child:Destroy()
		end
	end
	QuickSearchTool.CurrentOpen = nil
end

function QuickSearchTool.Open(entryContainer: QuickSearchContainer)
	if entryContainer.Description.Text:len() == 0 or entryContainer.Description.Text == "\n" or entryContainer.Description.Text == " " then
		return
	end
	QuickSearchTool.CurrentOpen = entryContainer
	local height = TextService:GetTextSize(entryContainer.Description.ContentText, entryContainer.Description.TextSize, Enum.Font.SourceSans, Vector2.new(entryContainer.Description.AbsoluteSize.X, math.huge)).Y
	entryContainer.Description:TweenSize(UDim2.new(1, 0, 0, height), nil, nil, TWEEN_TIME, true)
end

function QuickSearchTool.Close(entryContainer: QuickSearchContainer?)
	entryContainer = entryContainer or QuickSearchTool.CurrentOpen
	if entryContainer then
		entryContainer.Description:TweenSize(UDim2.new(1, 0, 0, 0), nil, nil, TWEEN_TIME, true)
		if entryContainer == QuickSearchTool.CurrentOpen then
			QuickSearchTool.CurrentOpen = nil
		end
	end
end

function QuickSearchTool.SetParent(parent: Instance)
	QuickSearchUi.Parent = parent
end

function QuickSearchTool.SetStyleInfo(styleInfo)
	QuickSearchTool.StyleInfo = styleInfo
end

local CaseSensitivityActive = false
local function QuickSearchFilter()
	local text = QuickSearchUi.FilterBar.Text
	if not CaseSensitivityActive then
		text = text:lower()
	end
	local empty = text:len() == 0
	QuickSearchTool.Close()
	IterTools.ObjIntoIter(QuickSearchTool.Containers)
	:truncate()
	:foreach(function(container: QuickSearchContainer)
		if not container:IsA("GuiObject") then return end
		if empty then container.Visible = true return end
		local containerText = container.Expand.Text
		if not CaseSensitivityActive then
			containerText = containerText:lower()
		end
		if containerText:find(text, 0, true) then
			container.Visible = true
		else
			container.Visible = false
		end
	end)
	:consume()
end

QuickSearchUi.CaseSensitivity.TextTransparency = 0.5
QuickSearchUi.FilterBar.ClearTextOnFocus = false

QuickSearchUi.FilterBar:GetPropertyChangedSignal("Text"):Connect(QuickSearchFilter)
QuickSearchUi.CaseSensitivity.Activated:Connect(function()
	CaseSensitivityActive = not CaseSensitivityActive
	if CaseSensitivityActive then
		QuickSearchUi.CaseSensitivity.TextTransparency = 0
	else
		QuickSearchUi.CaseSensitivity.TextTransparency = 0.5
	end
	if QuickSearchUi.FilterBar.Text ~= "" then
		QuickSearchFilter()
	end
	QuickSearchUi.FilterBar:CaptureFocus()
end)


return QuickSearchTool
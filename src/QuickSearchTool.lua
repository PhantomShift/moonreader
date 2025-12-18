local TextService = game:GetService("TextService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local TweenService = game:GetService("TweenService")

local Parser = require "./Parser"
local Markdown = require "./Markdown"
local IterTools = require "./IterTools"
local Garbage = require "./Garbage"

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
local function ScrollToView(scroll: ScrollingFrame, child: GuiObject, tweenTime: number?, padding: number?)
	tweenTime = if tweenTime == nil then TWEEN_TIME else tweenTime
	padding = if padding == nil then 64 else padding
	TweenService:Create(scroll, TweenInfo.new(tweenTime), {
		CanvasPosition = child.AbsolutePosition - Vector2.new(0, padding) + scroll.CanvasPosition
	}):Play()
end

function QuickSearchTool.AddEntry(entry: Parser.ParsedComment & {__source: LocalScript | ModuleScript | Script})
	local base = entry.within
	local concatenator = if entry.method then ":" else "."
	local name = entry.method or entry["function"]
	local args = {}
	if entry.param ~= nil then
		for p, info in pairs(entry.param) do
			args[p] = if info.luaType then `{info.name}: {info.luaType}` else info.name
		end
	end

	local returnString = ""
	if entry["return"] then
		if #entry["return"] > 1 then
			local concatted = IterTools.List.Values(entry["return"]):map(function(r) return r.luaType end):concat(", ")
			returnString = ` : ({concatted})`
		elseif #entry["return"] == 1 then
			returnString = ` : {entry["return"][1].luaType}`
		end
	end

	local argString = table.concat(args, ", ")
	local typeParamString = if entry.__typeParams then `<{table.concat(entry.__typeParams, ", ")}>` else ""
	
	local container = EntryExample:Clone()
	container.Name = base
	container.Visible = true
	container.Expand.Text = `{base}{concatenator}{name}{typeParamString}({argString}){returnString}`
	container.Description.Size = UDim2.fromScale(1, 0)
	container.Description.AutomaticSize = Enum.AutomaticSize.None

	container.Description.RichText = true
	-- container.Description.TextEditable = false
	if #entry.param > 0 then
		local collected = {}
		for _, param in entry.param do
			local t = if param.luaType then `: {param.luaType}` else ""
			local d = if param.description then ` -- {param.description}` else ""
			table.insert(collected, `* \`{param.name}{t}\`{d}`)
		end
		container.Description.Text ..= Markdown(`__Params__\n{table.concat(collected, "\n")}`, QuickSearchTool.StyleInfo) .. "<br />"
	end
	if entry["return"] and #entry["return"] > 0 then
		local concatted = IterTools.List.Values(entry["return"]):map(function(r)
			return `* \`{r.luaType}\`{if r.description then " -- " .. r.description else "" }`
		end):concat("\n")
		container.Description.Text ..= Markdown("__Returns__\n" .. (concatted), QuickSearchTool.StyleInfo) .. "<br />"
	end
	if entry.description then
		container.Description.Text ..= Markdown(entry.description, QuickSearchTool.StyleInfo, false)
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
					1 + IterTools.ObjIntoIter(entry.__source.Source:sub(1, entry.__start):gmatch("\n") :: IterTools.Iterable<nil, string?, nil>):count()
				)
				doc:RequestSetSelectionAsync(lineNumber, 1)
			end
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
	QuickSearchUi.FilterBar.Text = ""
	table.clear(QuickSearchTool.Containers)
	QuickSearchTool.CurrentOpen = nil
end

function QuickSearchTool.Open(entryContainer: QuickSearchContainer)
	if entryContainer.Description.Text:len() == 0 or entryContainer.Description.Text:match("^%s+$") then
		return
	end
	QuickSearchTool.CurrentOpen = entryContainer
	entryContainer.Description.AutomaticSize = Enum.AutomaticSize.Y
	ScrollToView(Entries, entryContainer)
end

function QuickSearchTool.Close(entryContainer: QuickSearchContainer?)
	entryContainer = entryContainer or QuickSearchTool.CurrentOpen
	if entryContainer then
		entryContainer.Description.AutomaticSize = Enum.AutomaticSize.None
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
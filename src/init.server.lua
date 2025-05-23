local Parser = require(script.Parser)
local SearchTool = require(script.SearchTool)
local Markdown = require(script.Markdown)
local StringUtils = require(script.StringUtils)
local IterTools = require(script.IterTools)
local QuickSearchTool = require(script.QuickSearchTool)

local HIGHLIGHT_PADDING_LINES = 10

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false)

local Assets = script.Assets

local Scroll = Assets.Scroll
local BaseTextLabel = Scroll.HiddenFolder.BaseLabel
local BlockPadding = Scroll.HiddenFolder.UIPadding
local Highlighter = Scroll.HighlighterFolder.Highlighter

local SearchButton = Assets.SearchButton

local toolbar = plugin:CreateToolbar("Moonreader")

local SettingsInterface = require(script.Settings)
SettingsInterface.init(plugin, widgetInfo, toolbar)

local Search
local searchPos = Vector3.zero
local function updateHighlight()
	if not Search then return end
	if searchPos == Vector3.zero or not Search.UiObject.Visible then
		Highlighter.Visible = false
	else
		local child = Scroll:FindFirstChild(tostring(searchPos.X))
		local bounds, lineHeight = StringUtils.GetRichTextPositionBounds(child, searchPos.Z)
		Scroll.CanvasPosition = Vector2.new(0, 0)
		local y_pos = child.AbsolutePosition.Y + bounds.Y
		if child:FindFirstChildOfClass("UIPadding") then
			y_pos += 16
		end
		Highlighter.Position = UDim2.fromOffset(0, y_pos)
		Scroll.CanvasPosition = Vector2.new(0, y_pos - child.TextSize * HIGHLIGHT_PADDING_LINES)
		Highlighter.Size = UDim2.new(1, 0, 0, lineHeight)
		Highlighter.ZIndex = 1000
		Highlighter.Visible = true
	end
end

Scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateHighlight)

local widget: DockWidgetPluginGui = plugin:CreateDockWidgetPluginGui("__moonreaderDocuments", widgetInfo)
widget.Title = "Moonreader Documents"

local quickSearchWidget = plugin:CreateDockWidgetPluginGui("__moonreaderQuickSearch", widgetInfo)
quickSearchWidget.Title = "Moonreader Quick Search"

QuickSearchTool.SetParent(quickSearchWidget)
SearchButton.Parent = widget
Scroll.Parent = widget

local function generateDocs()
	QuickSearchTool.Clear()
	for _, child in pairs(Scroll:GetChildren()) do
		if child:IsA("GuiBase2d") then
			child:Destroy()
		end
	end
	
	local styleInfo = SettingsInterface.getStyleInfo()
	local function MarkdownStyled(text: string)
		return Markdown(text, styleInfo)
	end
	QuickSearchTool.SetStyleInfo(SettingsInterface.getStyleInfo())
	Scroll.BackgroundColor3 = Markdown.stringToColor3(styleInfo.backgroundColor)
	BaseTextLabel.BackgroundColor3 = Markdown.stringToColor3(styleInfo.backgroundColor)
	BaseTextLabel.TextColor3 = Markdown.stringToColor3(styleInfo.textColor)

	local classes = {}
	local ignored_classes = {}
	local ignoredPaths: string | {string}? = SettingsInterface.PlaceSettings:get("IgnoredPaths")
	local globalIgnoredPaths = SettingsInterface.GlobalSettings:get("IgnoredPaths")
	if globalIgnoredPaths then
		if not ignoredPaths then
			ignoredPaths = globalIgnoredPaths
		else
			ignoredPaths ..= "\n" .. globalIgnoredPaths
		end
	end
	if ignoredPaths then
		ignoredPaths = StringUtils.IterLines(ignoredPaths :: string):filterMap(function(pattern)
			if pattern == "" or pattern == "^%s*$" then return nil end
			local globPattern = pattern:match("^%$(.+)")
			if globPattern then
				return StringUtils.IgnorePattern(globPattern)
			end
			return pattern
		end):collectList()
	end
	for info: Parser.ParsedComment in
		IterTools.ObjIntoIter(game:GetDescendants())
			:filterMap(function(_index: number, desc: Instance)
				if desc:IsA("LuaSourceContainer") then
					if ignoredPaths then
						local fullName = desc:GetFullName()
						if IterTools.List.Values(ignoredPaths)
								:any(function(line)
									return fullName:match(line) ~= nil
								end)
						then
							return nil
						end
					end

					return Parser.ReadScript(desc :: Parser.EditableScript)
				end

				return nil
			end)
			:flattenList()
			:truncate()
	do
		if info.ignore then
			if info.class ~= nil then
				ignored_classes[info.class] = true
			end
			continue
		end
		if ignored_classes[info.class or info.within] then
			continue
		end

		if info.class ~= nil and classes[info.class] == nil or info.within ~= nil and classes[info.within] == nil then
			local newClass = {
				class = info.class or info.within,
				entries = {} :: { Parser.ParsedComment },
			}

			classes[newClass.class] = newClass
		end

		if info.class ~= nil then
			classes[info.class].rootComment = info
		elseif info.within ~= nil then
			table.insert(classes[info.within].entries, info)
		end
	end
	
	for i: number, className: string, class: {class: string, entries: {Parser.ParsedComment}, rootComment: Parser.ParsedComment} in IterTools.ObjIntoIter(classes):enumerate() do
		if ignored_classes[className] then
			continue
		end
		
		local classEntry = BaseTextLabel:Clone()
		-- Idk how crazy people will be
		local classIndex = i * 10000
		classEntry.LayoutOrder = classIndex
		classEntry.Name = tostring(classIndex)
		classEntry.Text = MarkdownStyled(`# {className}`)
		if class.rootComment ~= nil and class.rootComment.description:len() > 0 then
			local pre = StringUtils.IterLines(class.rootComment.description)
			:map(function(s) return s:gsub("^\t", ""):gsub("^    ", "") end)
			:concat("\n")
			classEntry.Text = classEntry.Text .. "<br />" .. MarkdownStyled(pre)
		end
		classEntry.Parent = Scroll
	
		-- Like I said, who knows how crazy people will be
		local numInterfaces = classIndex + 1000
		local numProps = classIndex + 2000
		local numFunctions = classIndex + 3000
	
		for _, entry in pairs(class.entries) do
			-- For now, by default, entries tagged with "ignore" or "private" will be hidden by default
			-- TODO: Add options to view private functions
			if entry.ignore or entry.private then
				continue
			end

			local entryLabel = BaseTextLabel:Clone()
			entryLabel.BackgroundColor3 = Markdown.stringToColor3(styleInfo.backgroundColor)
			local head = ""
			if entry.prop then
				head = MarkdownStyled(`### {entry.within}.{entry.prop[1]} : {entry.prop[2] or "unknown"}`)
				if entry.readonly then
					head ..= MarkdownStyled(" 📙 Read Only")
				end
				numProps += 1
				entryLabel.LayoutOrder = numProps
				entryLabel.Name = tostring(numProps)
			elseif entry.interface then
				head = MarkdownStyled(`### {entry.interface}`)
				numInterfaces += 1
				entryLabel.LayoutOrder = numInterfaces
				entryLabel.Name = tostring(numInterfaces)
				if entry.field then
					local names = {}
					local fields = IterTools.ObjIntoIter(entry.field):map(function(name, field)
						table.insert(names, name)
						if field[1] and field[2] and field[3] then
							return `{field[1]}: {field[2]} -- {field[3]}`
						end
						if field[1] and field[3] then
							return `{field[1]} -- {field[3]}`
						end
						if field[1] and field[2] then
							return `{field[1]}: {field[2]}`
						end
						return field[1]
					end):concat("\n    ")
					local subEntryLabel = BaseTextLabel:Clone()
					local body = MarkdownStyled("```" .. `\n interface {entry.interface} ` .. "{\n    " .. fields .. "\n}\n```") :: string
					body = body:gsub("interface", `<font color="rgb({styleInfo.keyword})">interface</font>`)
					for _, name in names do
						body = StringUtils.ReplacePlain(body, `{name}:`, `<font color="rgb({styleInfo.keyword})">{name}</font>:`)
					end
					subEntryLabel.Text = body
					numInterfaces += 1
					subEntryLabel.LayoutOrder = numInterfaces
					subEntryLabel.Name = tostring(numInterfaces)
					subEntryLabel.Parent = Scroll
				end
			else
				QuickSearchTool.AddEntry(entry)
				-- Entry is a function/method
				local args = {}
				if entry.param ~= nil then
					for name, info in pairs(entry.param) do
						local arg = name
						if info[2] ~= nil then
							arg = arg .. `: {info[2]}`
						end
						args[info.order] = arg
					end
				end
				head = MarkdownStyled(`### {entry.method or entry["function"]}`)
				numFunctions += 1
				entryLabel.LayoutOrder = numFunctions
				entryLabel.Name = tostring(numFunctions)
				
				-- local returnString = if entry["return"] ~= nil then ` : {next(entry["return"])}` else ""
				local returnString = if entry["return"] ~= nil then ` : {table.concat(entry["return"], ", ")}` else ""
				local argString = ""
				if #args > 1 then
					argString = "\n" .. IterTools.List.Values(args):map(function(s) return "    " .. s end):concat(",\n") .. "\n"
				else
					argString = table.concat(args, ", ")
				end
				local concatenator = if entry.method ~= nil then ":" else "."
				local subEntryLabel = BaseTextLabel:Clone()
				local body = MarkdownStyled("```\n" .. `{entry.within}{concatenator}{entry.method or entry["function"]}({argString}){returnString}` .. "\n```")
				body = `<font size="{styleInfo.h4}">{body}</font>`
				subEntryLabel.Text = body
				numFunctions += 1
				subEntryLabel.LayoutOrder = numFunctions
				subEntryLabel.Name = tostring(numFunctions)
				subEntryLabel.Parent = Scroll
			end

			-- Labels that apply for all entries
			if entry.server then
				head ..= MarkdownStyled(" 🌐 Server")
			end
			if entry.client then
				head ..= MarkdownStyled(" 🖥️ Client")
			end
			if entry.client then
				head ..= MarkdownStyled(" 📃 Plugin")
			end
			if entry.yields then
				head ..= MarkdownStyled(" ⚠️ Yields")
			end
			if entry.unreleased then
				head ..= " <i>Unreleased</i>"
			end
			-- TODO: Deprecated tag
			if entry.since then
				head ..= ` <i>since {entry.since}</i>`
			end

			entryLabel.Text = entryLabel.Text .. head
			entryLabel.Parent = Scroll
			if entry.description ~= nil and entry.description:len() > 0 then
				for _, subEntry in Markdown(entry.description, styleInfo, nil, true) do
					local subEntryLabel = BaseTextLabel:Clone()
					subEntryLabel.Text = subEntry
					if subEntry:match(`<moonreader type="%w*">`) then
						local blockType = subEntry:match(`<moonreader type="(%w*)">`)
						local rounding = Instance.new("UICorner")
						subEntryLabel.Size = UDim2.new(1, -50, 0, 0)
						subEntryLabel.BackgroundColor3 = Markdown.stringToColor3(styleInfo[blockType] or styleInfo.backgroundColor)
						rounding.Parent = subEntryLabel
					else
						subEntryLabel.BackgroundColor3 = Markdown.stringToColor3(styleInfo.backgroundColor)
					end
					BlockPadding:Clone().Parent = subEntryLabel
					subEntryLabel.Parent = Scroll
					if entry.prop then
						numProps += 1
						subEntryLabel.LayoutOrder = numProps
					elseif entry.interface then
						numInterfaces += 1
						subEntryLabel.LayoutOrder = numInterfaces
					else
						numFunctions += 1
						subEntryLabel.LayoutOrder = numFunctions
					end
					subEntryLabel.Name = tostring(subEntryLabel.LayoutOrder)
				end
			end

			if entry.error ~= nil then
				local errorEntryLabel = BaseTextLabel:Clone()
				errorEntryLabel.Text = MarkdownStyled("#### Errors")
				for _num, error in entry.error do
					local errType, errDesc = table.unpack(error)
					errorEntryLabel.Text ..= "\n" .. MarkdownStyled(("`%s`"):format(errType))
					if errDesc then
						errorEntryLabel.Text ..= " - " .. MarkdownStyled(errDesc)
					end
				end
				numFunctions += 1
				errorEntryLabel.LayoutOrder = numFunctions
				errorEntryLabel.Name = tostring(errorEntryLabel.LayoutOrder)
				errorEntryLabel.Parent = Scroll
			end
		end
		for _, h in {
				{"Types", classIndex + 1000, numInterfaces},
				{"Properties",  classIndex + 2000, numProps},
				{"Functions", classIndex + 3000 , numFunctions},
			} do
			if h[3] > h[2] then
				local entryLabel = BaseTextLabel:Clone()
				entryLabel.Text = MarkdownStyled(`## {h[1]}`)
				entryLabel.BackgroundColor3 = Markdown.stringToColor3(styleInfo.backgroundColor)
				entryLabel.LayoutOrder = h[2]
				entryLabel.Name = tostring(h[2])
				entryLabel.Parent = Scroll
			end
		end
	end
	
	local children = Scroll:GetChildren()
	table.sort(children, function(a, b) return a:IsA("TextLabel") and b:IsA("TextLabel") and a.LayoutOrder < b.LayoutOrder end)
	local min = 1
	for _, child in pairs(children) do
		if not child:IsA("TextLabel") or not child.Visible then continue end
		child.LayoutOrder = min
		child.Name = tostring(min)
		min += 1
	end

	local documents = IterTools.ObjIntoIter(Scroll:GetChildren())
		:filterMap(function(_, child: Instance)
			if not child:IsA("TextLabel") or not child.Visible then return nil end
			return child.LayoutOrder, child.Text
		end)
		:collectDict()
	if not Search then
		Search = SearchTool.new(documents)
		Search:SetParent(widget)
	else
		Search:SetDocuments(documents)
	end
	Search:Activate():Connect(function(newIndex)
		searchPos = newIndex
		updateHighlight()
	end)
	Search.UiObject.Visible = false
	Search.UiObject.CloseContainer.Close.Activated:Connect(function()
		Search.UiObject.Visible = false
		Highlighter.Visible = false
	end)
end

generateDocs()

local openMoonreaderButton = toolbar:CreateButton("Open Docs", "Open documentation", "rbxassetid://4458901886")
openMoonreaderButton.ClickableWhenViewportHidden = true
openMoonreaderButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	openMoonreaderButton:SetActive(false)
end)

local quickSearchButton = toolbar:CreateButton("Quick Search", "Quickly glance through functions", "rbxassetid://4458901886")
quickSearchButton.ClickableWhenViewportHidden = true
quickSearchButton.Click:Connect(function()
	quickSearchWidget.Enabled = not quickSearchWidget.Enabled
	quickSearchButton:SetActive(false)
end)

local generateDocsButton = toolbar:CreateButton("Generate Docs", "(Re)generate documents", "rbxassetid://4458901886")
generateDocsButton.ClickableWhenViewportHidden = true
generateDocsButton.Click:Connect(function ()
	generateDocs()
	generateDocsButton:SetActive(false)
end)

local openDocSearchAction = plugin:CreatePluginAction(
	"MoonreaderDocumentationSearch",
	"Search Moonreader Documentation",
	"Search through Moonreader documentation",
	"rbxasset://textures/ui/SearchIcon.png",
	true
)

openDocSearchAction.Triggered:Connect(function()
	widget.Enabled = true
	Search.UiObject.Visible = true
	task.wait()
	Search.UiObject.TextBoxContainer.TextBox:CaptureFocus()
end)

SearchButton.Activated:Connect(function()
	Search.UiObject.Visible = true
	task.wait()
	Search.UiObject.TextBoxContainer.TextBox:CaptureFocus()
end)

local quickSearchAction = plugin:CreatePluginAction(
	"MoonreaderQuickSearch", 
	"Moonreader QuickSearch", 
	"Open Moonreader Quick Search Widget",
	"rbxasset://textures/ui/SearchIcon.png",
	true
)

quickSearchAction.Triggered:Connect(function()
	quickSearchWidget.Enabled = true
end)

local moonreaderMenu = plugin:CreatePluginMenu(
	"MoonreaderPluginMenu",
	"Moonreader",
	nil
)

moonreaderMenu:AddAction(quickSearchAction)
moonreaderMenu:AddAction(openDocSearchAction)
local CollectionService = game:GetService("CollectionService")

local StringUtils = require(script.Parent.StringUtils)
local IterTools = require(script.Parent.IterTools)
local Markdown = require(script.Parent.Markdown)

local Assets = script.Parent.Assets
local SettingsFrame = Assets.Settings
local BaseLabel = Assets.Scroll.HiddenFolder.BaseLabel
local BlockPadding = Assets.Scroll.HiddenFolder.UIPadding

local SettingsMethods = {}
SettingsMethods.__index = SettingsMethods

function SettingsMethods.set(self, name: string, val: any)
    if self:validate(name, val) then
        self.Inner[name] = val
        return true
    end
    return false
end

function SettingsMethods.setUnchecked(self, name: string, val: any)
    self.Inner[name] = val
end

function SettingsMethods.get(self, name: string)
    return self.Inner[name]
end

function SettingsMethods.validate(self, name: string, val: any)
    local validator = self.Validators[name]
    if validator == nil then
        return true
    end

    local valid, _err = validator(val)
    return valid
end

function SettingsMethods.load(self, data)
    self.Inner = data
end

function SettingsMethods.__iter(self)
    return next, self.Order
end

type SettingsMethods = typeof(setmetatable({}, SettingsMethods))

type EntryType = "TextEntry" | "Checkbox"
local EntryType = {
    TextEntry = function(textbox: TextBox)
        return textbox.Text
    end,
    Checkbox = function(button: GuiButton) : boolean
        return button:GetAttribute("Checked") :: boolean
    end
}
local function Tag(s: string) : string
    return "__Moonreader" .. s
end

local SettingsBuilder = {}
SettingsBuilder.__index = SettingsBuilder

type SettingsBuilder = typeof(SettingsBuilder)

function SettingsBuilder.new()
    return setmetatable({}, SettingsBuilder)
end

function SettingsBuilder:addEntry(
    name: string,
    alias: string,
    default: any,
    entryType: EntryType,
    validator: ((any) -> (boolean, string?))?
)
    table.insert(self, {
        Name = name,
        Alias = alias,
        Default = default,
        EntryType = entryType,
        Validator = validator
    })

    return self :: SettingsBuilder
end

function SettingsBuilder:build()
    local settings = {
        Inner = {},
        Validators = {},
        Defaults = {},
        Aliases = {},
        EntryType = {},
        Order = {}
    }
    for _, info in ipairs(self) do
        settings.Inner[info.Name] = info.Default
        settings.Validators[info.Name] = info.Validator
        settings.Defaults[info.Name] = info.Default
        settings.Aliases[info.Name] = info.Alias
        settings.EntryType[info.Name] = info.EntryType
        table.insert(settings.Order, info.Name)
    end

    return setmetatable(settings, SettingsMethods)
end

local GlobalSettings: SettingsMethods = SettingsBuilder.new()
    :addEntry("IgnoredPaths", "Ignored Paths", "PluginDebugService", "TextEntry")
    :build()

local PlaceSettings: SettingsMethods = SettingsBuilder.new()
    :addEntry("IgnoredPaths", "Ignored Paths", "", "TextEntry")
    :build()

local function validateColor(s: string) : (boolean, string?)
    local split = s:split(", ")
    local valid = #split == 3
    if valid then
        for _, c in split do
            local n = tonumber(c)
            if not n or n ~= math.clamp(n, 0, 255) then
                valid = false
                break
            end
        end
    end

    if valid then return true end

    return false, "%s should be a valid 0-255 RGB triple 'R, G, B'"
end

local function validateFontSize(s: string) : (boolean, string?)
    local n = tonumber(s)
    if n and n > 0 and math.round(n) == n then
        return true
    end
    return false, "%s should be an integer greater than 0"
end

local StyleSettings: SettingsMethods = SettingsBuilder.new()
    :addEntry("useCustomStyle", "Use Custom Styling", false, "Checkbox")
    :addEntry("backgroundColor", "Background Color", "47, 47, 47", "TextEntry", validateColor)
    :addEntry("codeblock", "Codeblock Background Color", "26, 13, 51", "TextEntry", validateColor)
    :addEntry("textColor", "Text Color", "255, 255, 255", "TextEntry", validateColor)
    :addEntry("preColor", "Preformatted Text Color", "215, 174, 255", "TextEntry", validateColor)
    :addEntry("hyperlinkColor", "Hyperlink Color", "42, 154, 235", "TextEntry", validateColor)
    :addEntry("h1", "Heading 1 Size", "40", "TextEntry", validateFontSize)
    :addEntry("h2", "Heading 2 Size", "30", "TextEntry", validateFontSize)
    :addEntry("h3", "Heading 3 Size", "26", "TextEntry", validateFontSize)
    :addEntry("h4", "Heading 4 Size", "20", "TextEntry", validateFontSize)
    :addEntry("TextSize", "Text Size", "16", "TextEntry", validateFontSize)
    :addEntry("iden", "Default Code Color", "234, 234, 234", "TextEntry", validateColor)
    :addEntry("keyword", "Keyword Color", "215, 174, 255", "TextEntry", validateColor)
    :addEntry("builtin", "Built-in Keyword Color", "131, 206, 255", "TextEntry", validateColor)
    :addEntry("string", "String Literal Color", "196, 255, 193", "TextEntry", validateColor)
    :addEntry("number", "Number Literal Color", "255, 125, 125", "TextEntry", validateColor)
    :addEntry("comment", "Comment Color", "140, 140, 155", "TextEntry", validateColor)
    :addEntry("operator", "Operator Color", "255, 239, 148", "TextEntry", validateColor)
    :addEntry("custom", "Custom Color", "119, 122, 255", "TextEntry", validateColor)
    :addEntry("info", "Info Block Color", "51, 105, 132", "TextEntry", validateColor)
    :addEntry("tip", "Tip Block Color", "43, 99, 55", "TextEntry", validateColor)
    :addEntry("caution", "Caution Block Color", "176, 126, 39", "TextEntry", validateColor)
    :addEntry("warning", "Warning Block Color", "130, 18, 18", "TextEntry", validateColor)
    :build()

local SettingsInterface = {}
SettingsInterface.PlaceSettings = PlaceSettings
SettingsInterface.StyleSettings = StyleSettings
SettingsInterface.GlobalSettings = GlobalSettings

type StyleInfo = {
    useCustomStyle: boolean,
    backgroundColor: string,
    codeblock: string,
    textColor: string,
    preColor: string,
    hyperlinkColor: string,
    h1: number,
    h2: number,
    h3: number,
    h4: number,
    TextSize: number,
    iden: string,
    keyword: string,
    string: string,
    number: string,
    comment: string,
    operator: string,
    custom: string,
    info: string,
    tip: string,
    caution: string,
    warning: string,
}

function SettingsInterface.getStyleInfo() : StyleInfo
    local getMethod = if StyleSettings:get("useCustomStyle") then StyleSettings.get else function(s: SettingsMethods, name: string)
        return s.Defaults[name]
    end
    
    local info = {}
    for _i: number, name: string in StyleSettings do
        local data =  getMethod(StyleSettings, name)
        local validator = StyleSettings.Validators[name]
        if validator == validateFontSize then
            info[name] = tonumber(data)
        else
            info[name] = data
        end
    end

    return info
end

function SettingsInterface.getStyleInfoPreview() : StyleInfo
    local info = {}

    local useDefault = false
    for _, entry in CollectionService:GetTagged(Tag("StyleSetting")) do
        if entry:GetAttribute("StyleSetting") == "useCustomStyle" then
            useDefault = not entry:GetAttribute("Checked")
            break
        end
    end

    for _i, entry in CollectionService:GetTagged(Tag("StyleSetting")) do
        local name = entry:GetAttribute("StyleSetting")
        local entryType = entry:GetAttribute("EntryType")
        local data = if entryType == "TextEntry" then entry.Text else entry:GetAttribute("Checked")
        local validator = StyleSettings.Validators[name]
        if useDefault or (validator and not validator(data)) then
            data = StyleSettings.Defaults[name]
        end

        if validator == validateFontSize then
            info[name] = tonumber(data)
        else
            info[name] = data
        end
    end

    return info
end

function SettingsInterface.init(plugin: Plugin, widgetInfo: DockWidgetPluginGuiInfo, toolbar: PluginToolbar)
    local styleSettings = plugin:GetSetting("StyleSettings")
    if styleSettings then
        StyleSettings:load(styleSettings)
    end
    local placeSettings = plugin:GetSetting(`{game.PlaceId}`)
    if placeSettings then
        PlaceSettings:load(placeSettings)
    end
    local globalSettings = plugin:GetSetting("GlobalSettings")
    if globalSettings then
        GlobalSettings:load(globalSettings)
    end
    
    local Styling = SettingsFrame.SettingsContainer.Styling
    local StylingEntries = Styling.Entries
    local StylingTextEntry = StylingEntries.TextEntryProto
    StylingTextEntry.Parent = nil
    local StylingCheckbox = StylingEntries.CheckboxProto
    StylingCheckbox.Parent = nil
    for i: number, name: string in StyleSettings do
        local entryType = StyleSettings.EntryType[name]
        local entry = if  entryType == "TextEntry" then StylingTextEntry:Clone() else StylingCheckbox:Clone()
        entry.LayoutOrder = i
        entry.Name = name
        entry.TextLabel.Text = StyleSettings.Aliases[name]
        
        if entryType == "TextEntry" then
            entry.TextBox:AddTag(Tag("StyleSetting"))
            entry.TextBox:SetAttribute("StyleSetting", name)
            entry.TextBox:SetAttribute("EntryType", entryType)
            entry.TextBox.Text = StyleSettings:get(name)
        elseif entryType == "Checkbox" then
            local isEnabled = StyleSettings:get(name) :: boolean
            entry.Button:AddTag(Tag("StyleSetting"))
            entry.Button:SetAttribute("StyleSetting", name)
            entry.Button:SetAttribute("EntryType", entryType)
            entry.Button:SetAttribute("Checked", isEnabled)

            entry.Button.Activated:Connect(function()
                local checked = not entry.Button:GetAttribute("Checked")
                entry.Button:SetAttribute("Checked", checked)
                
                if checked then
                    entry.Button.Text = utf8.char(0x2705) -- Checkmark emoji
                else
                    entry.Button.Text = ""
                end
            end)
        end

        entry.Parent = StylingEntries
    end
    
    local Preview = Styling.Preview
    local PreviewButtonContainer = Preview.ButtonContainer

    PreviewButtonContainer.Button.Activated:Connect(function()
        for _, child in Preview.PreviewContainer:GetChildren() do
            if child:IsA("TextLabel") then
                child:Destroy()
            end
        end

        local previewText = [[
# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading numbers above 4 default to 4
Normal Text, `Preformatted Text`, *Italic Text*, **Bold Text**, ***Bold Italic Text***

```lua
-- Comment
local RunService = game:GetService("RunService")

local conn = RunService.Heartbeat:Connect(function(dt)
    print(`Elapsed time: {dt}`)
    print(`Immediate FPS: {dt / 60}`)
end)
```
:::info
The code above makes use of *string interpolation*, which allows you to evaluate values and embed them within a string directly. 
:::
:::caution
The info above does not represent the views and opinions of PhantomShift GigaCorp LLC
:::
:::warning
The caution above is a joke.
:::
:::tip
One of us is lying; trust nobody.
:::
]]
        local styleInfo = SettingsInterface.getStyleInfoPreview()
        for i, entry in Markdown.ProcessMarkdown(previewText, styleInfo, false, true) do
            if entry:match("^%s*$") then continue end

            local label = BaseLabel:Clone()
            label.LayoutOrder = i
            label.BackgroundColor3 = Markdown.stringToColor3(styleInfo.backgroundColor)
            label.TextColor3 = Markdown.stringToColor3(styleInfo.textColor)
            label.TextSize = styleInfo.TextSize
            BlockPadding:Clone().Parent = label

            if entry:match(`<moonreader type="%w*">`) then
                local blockType = entry:match(`<moonreader type="(%w*)">`)
                local rounding = Instance.new("UICorner")
                label.BackgroundColor3 = Markdown.stringToColor3(styleInfo[blockType] or styleInfo.backgroundColor)
                rounding.Parent = label
            end

            label.Text = entry

            label.Parent = Preview.PreviewContainer
        end
    end)
    
    local widget: DockWidgetPluginGui = plugin:CreateDockWidgetPluginGui("__moonreaderSettings", widgetInfo)
    SettingsFrame.Parent = widget
    
    local widgetButton = toolbar:CreateButton("Open Settings", "Open settings", "rbxassetid://4458901886")
    widgetButton.ClickableWhenViewportHidden = true
    widgetButton.Click:Connect(function()
        widget.Enabled = not widget.Enabled
        widgetButton:SetActive(false)

        if widget.Enabled then
            SettingsFrame.SettingsContainer.IgnoredPaths.TextBox.Text = PlaceSettings:get("IgnoredPaths")
            SettingsFrame.SettingsContainer.GlobalIgnoredPaths.TextBox.Text = GlobalSettings:get("IgnoredPaths")

            for _, entry in CollectionService:GetTagged(Tag("StyleSetting")) do
                local entryType = entry:GetAttribute("EntryType")
                local entryName = entry:GetAttribute("StyleSetting")
                if entryType == "TextEntry" then
                    entry.Text = StyleSettings:get(entryName)
                elseif entryType == "Checkbox" then
                    local checked = StyleSettings:get(entryName)
                    entry:SetAttribute("Checked", checked)
                    if checked then
                        entry.Text = utf8.char(0x2705) -- Checkmark emoji
                    else
                        entry.Text = ""
                    end
                end
            end
        end
    end)

    SettingsFrame.BottomButtons.Cancel.Activated:Connect(function()
        -- SettingsFrame.IgnoredPaths.TextBox.Text = ""
        widget.Enabled = false
    end)

    SettingsFrame.BottomButtons.Reset.Activated:Connect(function()
        SettingsFrame.SettingsContainer.IgnoredPaths.TextBox.Text = ""
        
        for _, entry in CollectionService:GetTagged(Tag("StyleSetting")) do
            local entryName = entry:GetAttribute("StyleSetting")
            local entryType = entry:GetAttribute("EntryType")

            if entryType == "TextEntry" then
                entry.Text = StyleSettings.Defaults[entryName]
            elseif entryType == "Checkbox" then
                local checked = StyleSettings.Defaults[entryName]
                entry:SetAttribute("Checked", checked)
                if checked then
                    entry.Text = utf8.char(0x2705) -- Checkmark emoji
                else
                    entry.Text = ""
                end
            end
        end
    end)

    SettingsFrame.BottomButtons.Apply.Activated:Connect(function()

        PlaceSettings:set("IgnoredPaths", StringUtils.TrimWhitespace(SettingsFrame.SettingsContainer.IgnoredPaths.TextBox.Text or ""))
        GlobalSettings:set("IgnoredPaths", StringUtils.TrimWhitespace(SettingsFrame.SettingsContainer.GlobalIgnoredPaths.TextBox.Text or ""))

        for _, entry in CollectionService:GetTagged(Tag("StyleSetting")) do
            local entryName = entry:GetAttribute("StyleSetting")
            local entryType = entry:GetAttribute("EntryType")
            local validator = StyleSettings.Validators[entryName]
            local data = EntryType[entryType](entry)

            if validator then
                local valid, err = validator(data)
                if not valid then
                    warn("[Moonreader] [Setting Not Saved]", err:format(StyleSettings.Aliases[entryName]))
                else
                    StyleSettings:setUnchecked(entryName, EntryType[entryType](entry))
                end
            else
                StyleSettings:setUnchecked(entryName, EntryType[entryType](entry))
            end
        end

        plugin:SetSetting("StyleSettings", StyleSettings.Inner)
        plugin:SetSetting(`{game.PlaceId}`, PlaceSettings.Inner)
        plugin:SetSetting("GlobalSettings", GlobalSettings.Inner)

        widget.Enabled = false
    end)
end

return SettingsInterface
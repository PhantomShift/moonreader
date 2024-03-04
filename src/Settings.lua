local ServerStorage = game:GetService("ServerStorage")

local StringUtils = require(script.Parent.StringUtils)

local Assets = script.Parent.Assets
local SettingsFrame = Assets.Settings

local Settings = {}

function Settings.init(plugin: Plugin, widgetInfo: DockWidgetPluginGuiInfo, toolbar: PluginToolbar)
    local widget: DockWidgetPluginGui = plugin:CreateDockWidgetPluginGui("__moonreaderSettings", widgetInfo)
    SettingsFrame.Parent = widget
    
    local widgetButton = toolbar:CreateButton("Open Settings", "Open settings", "rbxassetid://4458901886")
    widgetButton.ClickableWhenViewportHidden = true
    widgetButton.Click:Connect(function()
        widget.Enabled = not widget.Enabled
        widgetButton:SetActive(false)

        if widget.Enabled then
            if ServerStorage:FindFirstChild("Moonreader") and ServerStorage:FindFirstChild("Moonreader"):FindFirstChild("IgnoredPaths") then
                SettingsFrame.IgnoredPaths.TextBox.Text = game:GetService("ServerStorage"):FindFirstChild("Moonreader"):FindFirstChild("IgnoredPaths").Value
            end
        end
    end)

    SettingsFrame.Buttons.Cancel.Activated:Connect(function()
        SettingsFrame.IgnoredPaths.TextBox.Text = ""
        widget.Enabled = false
    end)
    SettingsFrame.Buttons.Apply.Activated:Connect(function()
        local settingsFolder = ServerStorage:FindFirstChild("Moonreader")
        if not settingsFolder then
            settingsFolder = Instance.new("Folder")
            settingsFolder.Name = "Moonreader"
            settingsFolder.Parent = ServerStorage
        end

        -- I'll modularize when there are more settings
        local ignoredPaths = settingsFolder:FindFirstChild("IgnoredPaths") :: StringValue
        if not settingsFolder:FindFirstChild("IgnoredPaths") then
            ignoredPaths = Instance.new("StringValue")
            ignoredPaths.Name = "IgnoredPaths"
            ignoredPaths.Parent = settingsFolder
        end

        ignoredPaths.Value = StringUtils.TrimWhitespace(SettingsFrame.IgnoredPaths.TextBox.Text or "")
        
        widget.Enabled = false
    end)
end

function Settings.get(name: string)
    local settingsFolder = ServerStorage:FindFirstChild("Moonreader")
    if not settingsFolder then return nil end
    local dataValue = settingsFolder:FindFirstChild(name) :: ValueBase
    if not dataValue then return nil end
    return dataValue.Value
end

return Settings
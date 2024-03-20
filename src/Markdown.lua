local StringUtils = if game then require(script.Parent.StringUtils) else require("src/StringUtils")
local IterTools = if game then require(script.Parent.IterTools) else require("src/IterTools")
local lexer = if game then require(script.Parent.External.lexer) else require("external/Highlighter/src/lexer/init")

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

local MonospaceFontName = "RobotoMono"

-- Taken from https://github.com/boatbomber/Highlighter/blob/main/src/init.lua
local TokenColors = {
	["background"] = "47, 47, 47",
	["iden"] = "234, 234, 234",
	["keyword"] = "215, 174, 255",
	["builtin"] = "131, 206, 255",
	["string"] = "196, 255, 193",
	["number"] = "255, 125, 125",
	["comment"] = "140, 140, 155",
	["operator"] = "255, 239, 148",
	["custom"] = "119, 122, 255",
}

local SupportedLanguages = {
	["lua"] = {
		["keyword"] = {
			["function"] = true,
			["local"] = true,
			["self"] = true
		},
		["builtin"] = {
			["print"] = true
		},
		["special"] = {

		}
	}
}

local RichTextTags = {
	bold = {"<b>", "</b>"},
	italic = {"<i>", "</i>"},
	strikethrough = {"<s>", "</s>"},
	underline = {"<u>", "</u>"}
}

local MoonreaderOpen = `<moonreader type="%s">`
local MoonreaderClose = `</moonreader>`

local RichTextEscapes = {
	["<"] = "&lt;",
	[">"] = "&gt;",
	["\""] = "&quot;",
	["'"] = "&apos;",
	["&"] = "&amp";
}

setmetatable(RichTextEscapes, {
	__index = function(_self, index)
		return index
	end
})

local MarkdownTextTags = {
	["*"] = RichTextTags.italic,
	["**"] = RichTextTags.bold,
	["***"] = {RichTextTags.bold[1]..RichTextTags.italic[1], RichTextTags.italic[2]..RichTextTags.bold[2]},
	["__"] = RichTextTags.underline,
	["~~"] = RichTextTags.strikethrough,
	["`"] = {`<pre><font face="{MonospaceFontName}">`, "</font></pre>"}
}

local HeaderFontSize = {
	[1] = 40,
	[2] = 30,
	[3] = 26,
	[4] = 20,
}

local TabLength = 4

local function isInsidePreformatted(line: string, pos: number)
	local open = StringUtils.LastMatch(line:sub(1, pos), "()<pre>")
	if open == nil then return false end
	local close = line:match("()</pre>", open)

    return close > pos
end

local function ProcessMarkdownText(s: string, styleInfo: StyleInfo, maintainSize: boolean?)
	local prevEmpty = false
	return StringUtils.IterLines(s)
	:map(function(line: string)
		return line:gsub("\t", (" "):rep(TabLength))
	end)
	:map(function(line: string)
		return line:gsub("[<>\"'&]", RichTextEscapes)
	end)
	-- apply markdown spacing
	:map(function(line: string)
		-- This is necessary because with rich text active, empty lines render slightly bigger than they should
		-- https://devforum.roblox.com/t/using-richtext-slightly-offsets-all-text-except-for-first-line/1290819/14
		if maintainSize and line == "" then return " " end

		if line == "" and not prevEmpty then
			prevEmpty = true
			return "<br />"
		elseif line ~= "" then
			prevEmpty = false
		end
		-- return line .. " "
		return line:gsub("%g$", function(p) return p .. " " end)
		-- return line .. "\n"
	end)
	-- format headers
	:map(function(line: string)
		if maintainSize then return line:gsub("^#+", "") end

		return line:gsub("^(#+)%s*(.+)", function(shebangs, capture)
            return `<br /><font size="{styleInfo[`h{math.min(4, shebangs:len())}`]}">{capture}</font>`
        end)
	end)
	-- evaluate preformatted before other text tags
	:map(function(line: string)
		return line:gsub("`([^\n\r]-)`", function(text)
			if maintainSize then
				return `<pre><font color="rgb({styleInfo.preColor})">{text}</font></pre>`
			else
				return `<font color="rgb({styleInfo.preColor})">` .. MarkdownTextTags["`"][1] .. text .. MarkdownTextTags["`"][2] .. "</font>"
			end
		end)
	end)
	-- text tags
	:map(function(line: string)
		return line:gsub("^((%s*)%* )", function(_capture, indentation)
			-- temporary measure for unordered list elements
			return (indentation or "") .. " • "
		end):gsub("()(%*%*%*([^\n\r%*]-)%*%*%*)", function(pos, orig, text)
			if maintainSize then return text end
			if isInsidePreformatted(line, pos) then return orig end
			return MarkdownTextTags["***"][1] .. text .. MarkdownTextTags["***"][2]
		end):gsub("()(%*%*([^\n\r%*]-)%*%*)", function(pos, orig, text)
			if maintainSize  then return text end
			if isInsidePreformatted(line, pos) then return orig end
			return MarkdownTextTags["**"][1] .. text .. MarkdownTextTags["**"][2]
		end):gsub("()(%*([^\n\r%*]-)%*)", function(pos, orig, text)
			if maintainSize then return text end
			if isInsidePreformatted(line, pos) then return orig end
			return MarkdownTextTags["*"][1] .. text .. MarkdownTextTags["*"][2]
		end):gsub("()(__([^\n\r]-)__)", function(pos, orig, text)
			if isInsidePreformatted(line, pos) then return orig end
			return MarkdownTextTags["__"][1] .. text .. MarkdownTextTags["__"][2]
		end):gsub("()(~~([^\n\r]-)~~)", function(pos, orig, text)
			if isInsidePreformatted(line, pos) then return orig end
			return MarkdownTextTags["~~"][1] .. text .. MarkdownTextTags["~~"][2]
		end):gsub("()((%b[])(%b()))", function(pos, orig, text, link)
			if isInsidePreformatted(line, pos) then return text end
			return `<hyperlink link="{link:sub(2, -2)}"><font color="rgb({styleInfo.hyperlinkColor})">{text:sub(2, -2)}</font></hyperlink>`
		end):gsub("()(%b[])", function(pos, text)
			-- Hyperlinks to functions/properties
			if isInsidePreformatted(line, pos) then return text end
			return `<hyperlink><font color="rgb({styleInfo.hyperlinkColor})">{text:sub(2, -2)}</font></hyperlink>`
		end)
	end)
	:concat("<br />") :: string
end

local function ProcessMarkdown(text: string, styleInfo: StyleInfo, maintainSize: boolean?, splitSections: boolean?)
	local indices = {}
	local processed = {}

	for i, _block, language, comment in text:gmatch("()(```(%w*)\n(.-)\n```)") do
		-- print("Codeblock:", comment)
		comment = comment:gsub("\t", (" "):rep(TabLength)):gsub("[<>]", RichTextEscapes)
		local build = {}
		for token, content in lexer.scan(comment) do
			content = content:gsub("^\n", "")
			if SupportedLanguages[language] ~= nil and TokenColors[token] then
				table.insert(build, `<font color="rgb({styleInfo[token]})" token="{token}">{content}</font>`)
			else
				table.insert(build, content)
			end
		end

		if maintainSize then
			processed[i] = MoonreaderOpen:format("codeblock") .. table.concat(build):gsub("\n\n", "\n \n") .. MoonreaderClose
		else
			processed[i] = MoonreaderOpen:format("codeblock") .. `<font face="{MonospaceFontName}">{table.concat(build)}</font>` .. MoonreaderClose
		end
		if not splitSections then
			processed[i] = `<br />{processed[i]}<br />`
		end
		table.insert(indices, i)
	end
	for i, blockType, comment in text:gmatch("():::(%w*)\n(.-)\n:::") do
		-- print(i, blockType, comment)
		processed[i] = `{MoonreaderOpen:format(blockType)}{ProcessMarkdownText(comment, styleInfo, maintainSize)}{MoonreaderClose}`
		-- print(processed[i])
		table.insert(indices, i)
	end
	for m, i in StringUtils.IterSplit(text, "\n*```.-```\n*", true) do
		for mm, ii in StringUtils.IterSplit(m, "\n*:::.-:::\n*", true) do
			-- print(mm:len(), mm)
			if mm:len() == 1 then continue end
			processed[i + ii] = StringUtils.GSubRepeated(ProcessMarkdownText(mm, styleInfo, maintainSize), "^<br />", "")
			table.insert(indices, i + ii)
		end
	end
	table.sort(indices)
	if splitSections then
		return IterTools.List.Values(indices):map(processed):collectList() :: {string}
	end
	return IterTools.List.Values(indices):map(processed):concat("\n")
end

local Markdown = {}
Markdown.ProcessMarkdown = ProcessMarkdown
Markdown.TokenColors = TokenColors
Markdown.HeaderSizes = HeaderFontSize

setmetatable(Markdown, {
	__call = function(_self, ...)
		return ProcessMarkdown(...)
	end
})

if game then
	local BlockColors = {
		["tip"] = Color3.fromRGB(43, 99, 55),
		["warning"] = Color3.fromRGB(130, 18, 18),
		["info"] = Color3.fromRGB(51, 105, 132),
		["caution"] = Color3.fromRGB(176, 126, 39),
		["codeblock"] = Color3.new(0.1, 0.05, 0.2)
	}
	local function tostringRGB(color: Color3)
		return `{color.R * 255}, {color.G * 255}, {color.B * 255}`
	end
	local function stringToColor3(s: string)
		local r, g, b = table.unpack(s:split(", "))
		return Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b))
	end
	Markdown.BlockColors = BlockColors
	Markdown.color3ToRGB = tostringRGB
	Markdown.stringToColor3 = stringToColor3
end

return Markdown :: typeof(Markdown) & typeof(ProcessMarkdown)
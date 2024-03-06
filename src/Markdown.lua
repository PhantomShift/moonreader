local StringUtils = if game then require(script.Parent.StringUtils) else require("src/StringUtils")
local IterTools = if game then require(script.Parent.IterTools) else require("src/IterTools")
local lexer = if game then require(script.Parent.External.lexer) else require("external/Highlighter/src/lexer/init")

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
	["`"] = {`<font face="{MonospaceFontName}">`, "</font>"}
}

local HeaderFontSize = {
	[1] = 40,
	[2] = 30,
	[3] = 26,
	[4] = 20,
}

local TabLength = 4

local function ProcessMarkdownText(s: string, maintainSize: boolean?)
	local prevEmpty = false
	return StringUtils.IterLines(s)
	:map(function(line: string)
		return line:gsub("\t", (" "):rep(TabLength))
	end)
	:map(function(line: string)
		return StringUtils.IterChars(line)
		:map(function(char: string)
			local escape = RichTextEscapes[char]
			return if escape ~= nil then escape else char
		end)
		:concat()
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
            return `<br /><font size="{HeaderFontSize[math.min(4, shebangs:len())]}">{capture}</font>`
        end)
	end)
	-- text tags
	:map(function(line: string)
		return line:gsub("^((%s*)%* )", function(_capture, indentation)
			-- temporary measure for unordered list elements
			return (indentation or "") .. " • "
		end):gsub("%*%*%*([^\n\r%*])-%*%*%*", function(text)
			if maintainSize then return text end
			return MarkdownTextTags["***"][1] .. text .. MarkdownTextTags["***"][2]
		end):gsub("%*%*([^\n\r%*])-%*%*", function(text)
			if maintainSize then return text end
			return MarkdownTextTags["**"][1] .. text .. MarkdownTextTags["**"][2]
		end):gsub("%*([^\n\r%*])-%*", function(text)
			if maintainSize then return text end
			return MarkdownTextTags["*"][1] .. text .. MarkdownTextTags["*"][2]
		end):gsub("(__)([^\n\r]-)(__)", function(left, text, right)
			if left == right then
				return MarkdownTextTags[left][1] .. text .. MarkdownTextTags[right][2]
			end
		end):gsub("(~~)([^\n\r]-)(~~)", function(left, text, right)
			if left == right then
				return MarkdownTextTags[left][1] .. text .. MarkdownTextTags[right][2]
			end
		end):gsub("(`)([^\n\r]-)(`)", function(left, text, right)
			if left == right then
				if maintainSize then
					return `<font color="rgb({TokenColors.keyword})">{left .. text .. right}</font>`
				else
					return `<font color="rgb({TokenColors.keyword})">` .. MarkdownTextTags[left][1] .. text .. MarkdownTextTags[right][2] .. "</font>"
				end
			end
		end):gsub("(%b[])(%b())", function(text, link)
			return `<hyperlink link="{link:sub(2, -2)}"><font color="rgb(42, 154, 235)">{text:sub(2, -2)}</font></hyperlink>`
		end):gsub("%b[]", function(text)
			-- Hyperlinks to functions/properties
			return `<hyperlink><font color="rgb(42, 154, 235)">{text:sub(2, -2)}</font></hyperlink>`
		end)
	end)
	:concat("<br />") :: string
end

local function ProcessMarkdown(text: string, maintainSize: boolean?, splitSections: boolean?)
	local indices = {}
	local processed = {}

	for i, _block, language, comment in text:gmatch("()(```(%w*)\n(.-)\n```)") do
		-- print("Codeblock:", comment)
		comment = StringUtils.IterChars(comment:gsub("\t", (" "):rep(TabLength))):map(function(c)
			if c == "<" then
				return RichTextEscapes["<"]
			elseif c == ">" then
				return RichTextEscapes[">"]
			end
			return c
		end):concat()
		local build = {}
		for token, content in lexer.scan(comment) do
			content = content:gsub("^\n", "")
			if SupportedLanguages[language] ~= nil and TokenColors[token] then
				table.insert(build, `<font color="rgb({TokenColors[token]})" token="{token}">{content}</font>`)
			else
				table.insert(build, content)
			end
		end

		if maintainSize then
			processed[i] = MoonreaderOpen:format("codeblock") .. table.concat(build):gsub("\n\n", "\n \n") .. MoonreaderClose
		else
			processed[i] = MoonreaderOpen:format("codeblock") .. `<font face="{MonospaceFontName}">{table.concat(build)}</font>` .. MoonreaderClose
		end
		table.insert(indices, i)
	end
	for i, blockType, comment in text:gmatch("():::(%w*)\n(.-)\n:::") do
		-- print(i, blockType, comment)
		processed[i] = `{MoonreaderOpen:format(blockType)}{ProcessMarkdownText(comment, maintainSize)}{MoonreaderClose}`
		-- print(processed[i])
		table.insert(indices, i)
	end
	for m, i in StringUtils.IterSplit(text, "\n*```.-```\n*", true) do
		for mm, ii in StringUtils.IterSplit(m, "\n*:::.-:::\n*", true) do
			-- print(mm:len(), mm)
			if mm:len() == 1 then continue end
			processed[i + ii] = StringUtils.GSubRepeated(ProcessMarkdownText(mm, maintainSize), "^<br />", "")
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
	Markdown.BlockColors = BlockColors
	Markdown.color3ToRGB = tostringRGB
end

return Markdown :: typeof(Markdown) & typeof(ProcessMarkdown)
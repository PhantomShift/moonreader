local StringUtils = if game then require(script.Parent.StringUtils) else require("./src/StringUtils")
local IterTools = if game then require(script.Parent.IterTools) else require("./src/IterTools")
local Parser = {}
local LONG_COMMENT_PATTERN = "--%[=%[[\n\r].-%]=%]"
local DASHED_COMMENT_PATTERN = "%-%-%-.-\n"
local LINE_CAPTURE = "[^\n\r]+"

--TODO?: Support function definitions spanning multiple lines
local FUNCTION_CAPTURE = "function (%w-)([%.:]?)(%w+)%s*(%b())"
local GENERIC_CAPTURE = "function (%w-)([%.:]?)(%w+)%b<>%s*(%b())"
local RETURN_TYPE_CAPTURE = "%)%s*:[\t ]*([^\n\r]+)"
local function CaptureFunction(s: string, init: number)
	local line = s:match(LINE_CAPTURE, init)
	local capture = {line:match(FUNCTION_CAPTURE)}
	if #capture == 0 then
		capture = {line:match(GENERIC_CAPTURE)}
	end
	if #capture == 0 then return nil end

	-- TODO: Handle case of function containing `self` as its first argument

	capture[5] = line:match(RETURN_TYPE_CAPTURE)
	if capture[5] then
		capture[5] = StringUtils.SplitTopDepth(capture[5], ", ")
	end
	for k, v in pairs(capture) do
		if v == "" then capture[k] = nil end
	end
	local indexer = capture[2]
	return {
		within = capture[1] :: string?,
		funcType = if indexer == nil or indexer == "." then "function" elseif indexer == ":" then "method" else "none" :: "function" | "method" | "none",
		name = capture[3] :: string,
		arguments = capture[4] :: string,
		returnType = capture[5] :: {string}?
	}
end

local Tags = {
	-- Doc comments
	class = "@class (%w+)",
	within = "@within (%w+)",
	prop = "@prop ([%w_]+) ([^\n\r]+)",
	type = "@type (%w+) ([^\n\r]+)",
	["function"] = "@function ([%w_]+)",
	method = "@method ([%w_]+)",
	ignore = "@ignore", --TODO: automatically skip processing of classes and other comments tagged `ignore`

	-- Interface stuff
	interface = "@interface (%w+)",
	field = "@field ([^\n\r]*)",
	["."] = "%s*%.(%S[^\n\r]*)", -- interface shorthand

	-- Tag tag
	tag = "@tag (%w+)",

	-- Function tags
	yields = "@yields",
	param = "@param ([^\n\r]*)",
	["return"] = "@return ([^\n\r]*)"

	--TODO: Other tags
}

local REQUIRED_TAGS = { class = true, within = true }
local REPEATABLE_TAGS = { param = true, tag = true, ["return"] = true, field = true, ["."] = true }
local MARKER_TAGS = {
	yields = true,
	ignore = true,

	-- tags yet to be implemented
	-- usage
	unreleased = true,

	-- visibility
	private = true,
	
	-- realm
	client = true,
	server = true,
	plugin = true,

	-- property
	readonly = true 
}
local function __name_type_comment_parse(s: string)
	local front, comment = StringUtils.SplitOnce(s, " -- ")
	local name, par_type = StringUtils.SplitOnce(front, " ")
	return table.pack(name, par_type or "", comment)
end
local COMPLEX_TAGS = {
	param = __name_type_comment_parse,
	field = __name_type_comment_parse,
	["."] = __name_type_comment_parse,
	["return"] = function(s: string)
		return table.pack(StringUtils.SplitOnce(s, " -- "))
	end
}

export type ParsedComment = {
	__source: string | EditableScript,
	__start: number,
	__end: number,
	class: string,
	within: string,
	prop: {string},
	type: {string},
	interface: string,
	["function"]: string,
	method: string,

	ignore: boolean,

	tag: {[string]: {string}},

	yields: boolean,
	param: {
		[string]: {[number]: string, order: number}
	},
	["return"]: {string},

	description: string,
	__commentType: "Long" | "Dashed"
}

local NewlineInducers = {
	["%*"] = true,
	["%-"] = true,
	[":::"] = true,
	["#"] = true
}

function Parser.ParseCommentGroup(source: string, comment: string, commentType: "Long" | "Dashed") : ParsedComment
	local result = {
		__source = source,
		__commentType = commentType
	}
	result.__start, result.__end = source:find(comment, 0, true)

	local paramNumber = 1
	local returnNumber = 1

	for tag, pattern in pairs(Tags) do
		local g = comment:gmatch(pattern)
		local info = table.pack(g())
		while info do
			if #info > 0 then
				if COMPLEX_TAGS[tag] then
					info = COMPLEX_TAGS[tag](info[1])
				end
	
				if REPEATABLE_TAGS[tag] then
					if tag == "." then tag = "field" end
	
					if result[tag] == nil then result[tag] = {} end
					if tag == "return" then
						result[tag][returnNumber] = info[1]
					else
						result[tag][info[1]] = info
					end
					if tag == "param" then
						result[tag][info[1]].order = paramNumber
						paramNumber = paramNumber + 1
					end
				elseif MARKER_TAGS[tag] then
					result[tag] = true
				else
					-- if tag == "return" then
					-- 	print(table.concat({comment:match(pattern)}, "\t"))
					-- end
					result[tag] = if info.n == 1 then info[1] else info
				end
			else
				break
			end
			info = table.pack(g())
		end

		-- local info = table.pack(comment:match(pattern))
		-- if #info > 0 then
			
		-- end
	end
	-- Overall entry description
	if commentType == "Long" then
		local indentation = comment:match("\n(%s*)")
		local prevEmpty = false
		local inCodeBlock = false
		local inNonCodeBlock = false
		result.description = StringUtils.IterLines(comment)
		:filterMap(function(line)
			if not inNonCodeBlock and line:match("^%s+:::") then
				inNonCodeBlock = true
				return line:gsub(`^{indentation}`, "\n") .. "\n"
			end
			if inNonCodeBlock and line:match("^%s+:::") then
				inNonCodeBlock = false
				return line:gsub(`^{indentation}`, "\n\n")
			end
			if line:match("^%s+```") then
				inCodeBlock = not inCodeBlock
				return line:gsub(`^{indentation}`, "\n")
			end
			if inCodeBlock then
				return line:gsub(`^{indentation}`, "\n")
			end
			if line == "" or line:match("^%s+$") and not prevEmpty then
				if prevEmpty then
					return nil
				end
				prevEmpty = true
				return "\n"
			end
			-- if line == "" and not prevEmpty then prevEmpty = true return line end
			if line:match("^%s+") and not line:match("^%s+@") and not line:match("^%s+%.%S") then
				prevEmpty = false
				for pattern in NewlineInducers do
					if line:match(`^%s+{pattern}`) then
						return line:gsub(`^{indentation}`, "\n")
					end
				end
				return line:gsub(`^{indentation}`, "") .. " "
			end
		end)
		:concat("")
		:gsub("(%s*)$", "")
	elseif commentType == "Dashed" then
		local first = comment:match("^(.-)[\n\r]")
		local indentation = first:match("^%s*%-+%s*")
		local idents = indentation:len()
		local inCodeBlock = false
		local prevEmpty = false
		result.description = StringUtils.IterLines(comment)
			:filterMap(function(line)
				local text = line:sub(idents + 1)
				if not text:match("^%s*@") and not text:match("^%s*%.%S") then
					if text:match("^```") then
						inCodeBlock = not inCodeBlock
						return `{text}\n`
					end
					if inCodeBlock then
						-- not entirely sure what's causing these to exist?
						if text == "" or text == " " then
							return nil
						end
						return `{text}\n`
					end
					
					if text == "" or text:match("^%s+$") then
						if prevEmpty then
							return nil
						end
						prevEmpty = true
						return "\n"
					end

					for pattern in NewlineInducers do
						if text:match(`^{pattern}`) then
							return `\n{text}\n`
						end
					end
					return `{text} `
				end
			end)
			:concat()
			-- :gsub("\n\n", "\n")
	end
	return result
end

function Parser.InferFunctionInformation(parsedComment: ParsedComment)   
	local init: number = parsedComment.__end + 1
	local rawFunctionInfo = CaptureFunction(parsedComment.__source :: string, init)
	-- print(parsedComment.param)
	if rawFunctionInfo == nil then return end
	parsedComment.within = parsedComment.within or rawFunctionInfo.within
	parsedComment[rawFunctionInfo.funcType] = parsedComment[rawFunctionInfo.funcType] or rawFunctionInfo.name
	parsedComment["return"] = parsedComment["return"] or rawFunctionInfo.returnType
	if rawFunctionInfo.arguments:len() > 2 then
		local paramNumber = 1
		for _, argument in pairs(StringUtils.SplitTopDepth(rawFunctionInfo.arguments:sub(2, -2), ", ")) do
			local left, right = StringUtils.SplitOnce(argument, ": ")
			-- print(left, right)
			if parsedComment.param == nil then
				parsedComment.param = {[left] = {left, right, order = paramNumber}}
			elseif parsedComment.param[left] == nil then
				parsedComment.param[left] = {left, right, order = paramNumber}
			end
			if parsedComment.param[left][2] == "" then
				parsedComment.param[left][2] = right
			end
			parsedComment.param[left].order = paramNumber
			paramNumber = paramNumber + 1
		end
	end
end

function Parser.ReadSource(src: string) : {ParsedComment}
	local results = {}
	for match in src:gmatch(LONG_COMMENT_PATTERN) do
		table.insert(results, Parser.ParseCommentGroup(src, match, "Long"))
	end
	for _match, front, back in StringUtils.GMatchRepeated(src, DASHED_COMMENT_PATTERN) do
		table.insert(results, Parser.ParseCommentGroup(src, src:sub(front, back), "Dashed"))
	end

	for _, result in pairs(results) do
		Parser.InferFunctionInformation(result)
	end

	for _, result in pairs(results) do
		result.__source = nil
	end

	return results
end

export type EditableScript = Script | ModuleScript | LocalScript
-- Wrapper around Parser.ReadSource that replaces `result.__source` with `source`
function Parser.ReadScript(source: EditableScript) : ParsedComment
	local results = Parser.ReadSource(source.Source)
	for _, result in pairs(results) do
		result.__source = source
	end
	
	return results
end
return Parser